# Walmart Chile ↔ Jumpseller Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Ruby integration that publishes Jumpseller products to Walmart Chile, syncs inventory in real-time via webhooks (with daily fallback), and creates Jumpseller orders from Walmart purchases.

**Architecture:** Sinatra app receives Jumpseller `product.updated` webhooks and updates Walmart inventory immediately. Rake tasks handle initial product publishing, daily inventory reconciliation, and Walmart order polling. GitHub Actions runs the daily cron; Render.com hosts the webhook server.

**Tech Stack:** Ruby, Sinatra, Faraday, Rake, RSpec + WebMock, dotenv, Render.com, GitHub Actions

---

## File Map

| File | Responsibility |
|---|---|
| `Gemfile` | Dependencies |
| `.env.example` | Documents required env vars |
| `lib/walmart_client.rb` | Walmart Chile API wrapper (OAuth2, auto token refresh) |
| `lib/jumpseller_client.rb` | Jumpseller API wrapper (paginated products, create orders) |
| `lib/product_mapper.rb` | Jumpseller product → Walmart spec 4.46 feed payload |
| `lib/order_mapper.rb` | Walmart order → Jumpseller order payload |
| `app.rb` | Sinatra: receives Jumpseller `product.updated` webhooks |
| `config.ru` | Rack entry point for Render |
| `Rakefile` | Tasks: publish_products, sync_inventory, sync_orders, status |
| `.last_order_id` | Cursor: last Walmart purchaseOrderId processed (gitignored) |
| `.github/workflows/daily_sync.yml` | GitHub Actions cron: 06:00 UTC daily |
| `spec/spec_helper.rb` | RSpec + WebMock setup |
| `spec/walmart_client_spec.rb` | Tests for WalmartClient |
| `spec/jumpseller_client_spec.rb` | Tests for JumpsellerClient |
| `spec/product_mapper_spec.rb` | Tests for ProductMapper |
| `spec/order_mapper_spec.rb` | Tests for OrderMapper |
| `spec/app_spec.rb` | Tests for Sinatra webhook endpoint |

---

## Task 1: Project setup

**Files:**
- Create: `Gemfile`
- Create: `.env.example`
- Create: `.gitignore`
- Create: `spec/spec_helper.rb`

- [ ] **Step 1: Create Gemfile**

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'faraday', '~> 2.0'
gem 'faraday-retry'
gem 'sinatra', '~> 3.0'
gem 'dotenv'
gem 'json'
gem 'base64'
gem 'rack'

group :development, :test do
  gem 'rspec', '~> 3.0'
  gem 'webmock'
  gem 'rack-test'
end
```

- [ ] **Step 2: Install dependencies**

Run: `bundle install`
Expected: `Bundle complete!` with no errors

- [ ] **Step 3: Create .env.example**

```bash
# .env.example
JUMPSELLER_LOGIN=your_login
JUMPSELLER_AUTH_TOKEN=your_auth_token
JUMPSELLER_WEBHOOK_SECRET=your_webhook_secret
JUMPSELLER_PAYMENT_METHOD_ID=walmart

WALMART_CLIENT_ID=your_client_id
WALMART_CLIENT_SECRET=your_client_secret
WALMART_ENV=sandbox

# Optional: override default product category (must match exactly a Walmart Chile category)
WALMART_DEFAULT_CATEGORY=Decoración de Hogar, Cocina y Otros
```

- [ ] **Step 4: Create .gitignore**

```
.env
.last_order_id
```

- [ ] **Step 5: Create spec/spec_helper.rb**

```ruby
# spec/spec_helper.rb
require 'webmock/rspec'
require 'dotenv'

Dotenv.load('.env.test')

WebMock.disable_net_connect!(allow_localhost: true)

ENV['JUMPSELLER_LOGIN']           ||= 'test_login'
ENV['JUMPSELLER_AUTH_TOKEN']      ||= 'test_token'
ENV['JUMPSELLER_WEBHOOK_SECRET']  ||= 'test_secret'
ENV['WALMART_CLIENT_ID']          ||= 'test_client_id'
ENV['WALMART_CLIENT_SECRET']      ||= 'test_client_secret'
ENV['WALMART_ENV']                ||= 'sandbox'
```

- [ ] **Step 6: Verify RSpec runs**

Run: `bundle exec rspec --dry-run`
Expected: `0 examples, 0 failures`

- [ ] **Step 7: Commit**

```bash
git init
git add Gemfile Gemfile.lock .env.example .gitignore spec/spec_helper.rb
git commit -m "chore: project setup with dependencies and RSpec"
```

---

## Task 2: WalmartClient — authentication

**Files:**
- Create: `lib/walmart_client.rb`
- Create: `spec/walmart_client_spec.rb`

**Context:** Walmart uses OAuth2 `client_credentials`. Token lasts 15 minutes. The client auto-refreshes before expiry. All requests need `WM_MARKET: cl`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/walmart_client_spec.rb
require 'spec_helper'
require_relative '../lib/walmart_client'

RSpec.describe WalmartClient do
  let(:client) { WalmartClient.new }
  let(:token_url) { 'https://marketplace.walmartapis.com/v3/token' }

  def stub_token
    stub_request(:post, token_url)
      .to_return(
        status: 200,
        body: { access_token: 'test_token_123', expires_in: 900 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '#token (via authenticated request)' do
    it 'fetches an OAuth2 token using Basic auth' do
      stub_token
      stub_request(:get, 'https://marketplace.walmartapis.com/v3/orders')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      client.get_orders
      expect(WebMock).to have_requested(:post, token_url)
        .with(body: 'grant_type=client_credentials')
    end

    it 'reuses the token when not expired' do
      stub_token
      stub_request(:get, 'https://marketplace.walmartapis.com/v3/orders')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
        .times(2)

      client.get_orders
      client.get_orders
      expect(WebMock).to have_requested(:post, token_url).once
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/walmart_client_spec.rb`
Expected: `LoadError: cannot load such file -- .../lib/walmart_client`

- [ ] **Step 3: Implement WalmartClient with auth**

```ruby
# lib/walmart_client.rb
require 'faraday'
require 'faraday/retry'
require 'json'
require 'base64'

class WalmartClient
  BASE_URL = 'https://marketplace.walmartapis.com'.freeze

  def initialize
    @client_id     = ENV.fetch('WALMART_CLIENT_ID')
    @client_secret = ENV.fetch('WALMART_CLIENT_SECRET')
    @token         = nil
    @token_expires_at = Time.now - 1
  end

  def create_items_feed(payload)
    post('/v3/feeds?feedType=MP_ITEM_INTL', payload)
  end

  def get_feed_status(feed_id)
    get("/v3/feeds/#{feed_id}")
  end

  def update_inventory(sku, quantity)
    put("/v3/inventory?sku=#{URI.encode_www_form_component(sku)}",
        { sku: sku, quantity: { amount: quantity, unit: 'EACH' } })
  end

  def get_orders(status: 'Created', created_start_date: nil)
    params = { status: status, limit: 200 }
    params[:createdStartDate] = created_start_date if created_start_date
    get('/v3/orders', params)
  end

  def acknowledge_order(purchase_order_id)
    post("/v3/orders/#{purchase_order_id}/acknowledge", {})
  end

  private

  def token
    refresh_token if Time.now >= @token_expires_at
    @token
  end

  def refresh_token
    credentials = Base64.strict_encode64("#{@client_id}:#{@client_secret}")
    conn = Faraday.new(url: BASE_URL) do |f|
      f.request :url_encoded
    end
    response = conn.post('/v3/token') do |req|
      req.headers['Authorization']  = "Basic #{credentials}"
      req.headers['WM_MARKET']      = 'cl'
      req.headers['Accept']         = 'application/json'
      req.body = 'grant_type=client_credentials'
    end
    data = JSON.parse(response.body)
    @token = data['access_token']
    @token_expires_at = Time.now + data['expires_in'].to_i - 60
  end

  def connection
    Faraday.new(url: BASE_URL) do |f|
      f.request  :json
      f.request  :retry, max: 3, interval: 1, backoff_factor: 2,
                          exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
    end
  end

  def default_headers
    {
      'Authorization'                 => "Bearer #{token}",
      'WM_MARKET'                     => 'cl',
      'WM_CONSUMER.CHANNEL.TYPE'      => 'jumpseller',
      'Accept'                        => 'application/json',
      'Content-Type'                  => 'application/json'
    }
  end

  def get(path, params = {})
    response = connection.get(path) do |req|
      req.headers.merge!(default_headers)
      req.params.merge!(params)
    end
    JSON.parse(response.body)
  end

  def post(path, body)
    response = connection.post(path) do |req|
      req.headers.merge!(default_headers)
      req.body = body.to_json
    end
    JSON.parse(response.body)
  end

  def put(path, body)
    response = connection.put(path) do |req|
      req.headers.merge!(default_headers)
      req.body = body.to_json
    end
    JSON.parse(response.body)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/walmart_client_spec.rb`
Expected: `2 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/walmart_client.rb spec/walmart_client_spec.rb
git commit -m "feat: WalmartClient with OAuth2 auto token refresh"
```

---

## Task 3: WalmartClient — inventory and orders tests

**Files:**
- Modify: `spec/walmart_client_spec.rb`

- [ ] **Step 1: Add inventory and orders tests**

Append to `spec/walmart_client_spec.rb` (inside the `RSpec.describe WalmartClient do` block, after existing tests):

```ruby
  describe '#update_inventory' do
    it 'sends PUT with sku and quantity' do
      stub_token
      sku = 'SKU-42'
      stub_request(:put, "https://marketplace.walmartapis.com/v3/inventory?sku=SKU-42")
        .with(body: hash_including('sku' => sku, 'quantity' => { 'amount' => 5, 'unit' => 'EACH' }))
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      result = client.update_inventory(sku, 5)
      expect(result).to eq({})
    end
  end

  describe '#get_orders' do
    it 'fetches orders with Created status' do
      stub_token
      orders_response = { 'list' => { 'elements' => { 'order' => [] } } }
      stub_request(:get, 'https://marketplace.walmartapis.com/v3/orders')
        .with(query: hash_including('status' => 'Created'))
        .to_return(status: 200, body: orders_response.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.get_orders
      expect(result).to eq(orders_response)
    end
  end

  describe '#acknowledge_order' do
    it 'posts to the acknowledge endpoint' do
      stub_token
      stub_request(:post, 'https://marketplace.walmartapis.com/v3/orders/PO-123/acknowledge')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      result = client.acknowledge_order('PO-123')
      expect(result).to eq({})
    end
  end
```

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/walmart_client_spec.rb`
Expected: `5 examples, 0 failures`

- [ ] **Step 3: Commit**

```bash
git add spec/walmart_client_spec.rb
git commit -m "test: add WalmartClient inventory and orders tests"
```

---

## Task 4: JumpsellerClient

**Files:**
- Create: `lib/jumpseller_client.rb`
- Create: `spec/jumpseller_client_spec.rb`

**Context:** Jumpseller REST API v1. Auth via `?login=&authtoken=` query params. Products endpoint returns an array of `{"product": {...}}` objects. Paginated with `page` and `limit`.

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/jumpseller_client_spec.rb
require 'spec_helper'
require_relative '../lib/jumpseller_client'

RSpec.describe JumpsellerClient do
  let(:client) { JumpsellerClient.new }
  let(:base)   { 'https://api.jumpseller.com/v1' }
  let(:auth)   { { login: 'test_login', authtoken: 'test_token' } }

  describe '#products' do
    it 'returns products for a given page' do
      response_body = [
        { 'product' => { 'id' => 1, 'name' => 'Product 1', 'price' => 5000, 'stock' => 10 } }
      ].to_json
      stub_request(:get, "#{base}/products.json")
        .with(query: hash_including(auth.merge(page: '1', limit: '100')))
        .to_return(status: 200, body: response_body,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.products(page: 1)
      expect(result.first['product']['name']).to eq('Product 1')
    end
  end

  describe '#all_products' do
    it 'paginates until an empty page is returned' do
      page1 = Array.new(100) { |i| { 'product' => { 'id' => i, 'name' => "P#{i}" } } }.to_json
      page2 = [{ 'product' => { 'id' => 100, 'name' => 'P100' } }].to_json

      stub_request(:get, "#{base}/products.json")
        .with(query: hash_including(page: '1')).to_return(status: 200, body: page1,
                                                           headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "#{base}/products.json")
        .with(query: hash_including(page: '2')).to_return(status: 200, body: page2,
                                                           headers: { 'Content-Type' => 'application/json' })

      result = client.all_products
      expect(result.length).to eq(101)
    end
  end

  describe '#create_order' do
    it 'posts order payload to Jumpseller' do
      order_data = { 'status' => 'paid', 'products' => [{ 'id' => 1, 'qty' => 2 }] }
      stub_request(:post, "#{base}/orders.json")
        .to_return(status: 201, body: { 'order' => { 'id' => 999 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.create_order(order_data)
      expect(result['order']['id']).to eq(999)
    end
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/jumpseller_client_spec.rb`
Expected: `LoadError: cannot load such file -- .../lib/jumpseller_client`

- [ ] **Step 3: Implement JumpsellerClient**

```ruby
# lib/jumpseller_client.rb
require 'faraday'
require 'faraday/retry'
require 'json'

class JumpsellerClient
  BASE_URL = 'https://api.jumpseller.com/v1'.freeze

  def initialize
    @login     = ENV.fetch('JUMPSELLER_LOGIN')
    @authtoken = ENV.fetch('JUMPSELLER_AUTH_TOKEN')
  end

  def products(page: 1, limit: 100)
    get('/products.json', page: page, limit: limit)
  end

  def all_products
    results = []
    page = 1
    loop do
      batch = products(page: page)
      results.concat(batch)
      break if batch.size < 100
      page += 1
    end
    results
  end

  def create_order(order_data)
    post('/orders.json', { order: order_data })
  end

  private

  def auth_params
    { login: @login, authtoken: @authtoken }
  end

  def connection
    Faraday.new(url: BASE_URL) do |f|
      f.request :retry, max: 3, interval: 1, backoff_factor: 2,
                        exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
    end
  end

  def get(path, params = {})
    response = connection.get(path) do |req|
      req.params.merge!(auth_params.merge(params.transform_keys(&:to_s)))
      req.headers['Accept'] = 'application/json'
    end
    JSON.parse(response.body)
  end

  def post(path, body)
    response = connection.post(path) do |req|
      req.params.merge!(auth_params.transform_keys(&:to_s))
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept']       = 'application/json'
      req.body = body.to_json
    end
    JSON.parse(response.body)
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/jumpseller_client_spec.rb`
Expected: `3 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/jumpseller_client.rb spec/jumpseller_client_spec.rb
git commit -m "feat: JumpsellerClient with paginated products and order creation"
```

---

## Task 5: ProductMapper

**Files:**
- Create: `lib/product_mapper.rb`
- Create: `spec/product_mapper_spec.rb`

**Context:** Transforms a Jumpseller product (from `{"product": {...}}` wrapper) into Walmart spec 4.46 format. Key rules: prefix name with "TEST - ", force inventory to 0 for sandbox, minimum price 1400 CLP, fake GTIN using product ID padded to 14 digits.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/product_mapper_spec.rb
require 'spec_helper'
require_relative '../lib/product_mapper'

RSpec.describe ProductMapper do
  let(:jumpseller_product) do
    {
      'id'          => 42,
      'name'        => 'Camiseta Roja',
      'sku'         => 'CAM-001',
      'price'       => 9990.0,
      'stock'       => 15,
      'brand'       => 'MiMarca',
      'description' => 'Una camiseta roja de algodón',
      'weight'      => 0.3,
      'images'      => [{ 'url' => 'https://example.com/img.jpg' }]
    }
  end

  describe '.to_walmart' do
    subject(:result) { ProductMapper.to_walmart(jumpseller_product) }

    it 'prefixes product name with TEST -' do
      expect(result['Orderable']['productName']).to start_with('TEST - ')
    end

    it 'uses Jumpseller product id as SKU' do
      expect(result['Orderable']['sku']).to eq('42')
    end

    it 'sets price in CLP' do
      expect(result['Orderable']['price']['currency']).to eq('CLP')
      expect(result['Orderable']['price']['amount']).to eq(9990)
    end

    it 'enforces minimum price of 1400 CLP' do
      cheap_product = jumpseller_product.merge('price' => 500)
      result = ProductMapper.to_walmart(cheap_product)
      expect(result['Orderable']['price']['amount']).to eq(1400)
    end

    it 'generates a 14-digit fake GTIN from product id' do
      gtin = result['Orderable']['productIdentifiers']['productId']
      expect(gtin.length).to eq(14)
    end

    it 'includes main image URL in Visible section' do
      category = ENV.fetch('WALMART_DEFAULT_CATEGORY', 'Decoración de Hogar, Cocina y Otros')
      expect(result['Visible'][category]['productDescription']['mainImageUrl'])
        .to eq('https://example.com/img.jpg')
    end
  end

  describe '.feed_payload' do
    it 'wraps products in MPItemFeedHeader and MPItem' do
      payload = ProductMapper.feed_payload([jumpseller_product])
      expect(payload['MPItemFeedHeader']['version']).to eq('4.46')
      expect(payload['MPItemFeedHeader']['mart']).to eq('WALMART_CL')
      expect(payload['MPItem'].length).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/product_mapper_spec.rb`
Expected: `LoadError`

- [ ] **Step 3: Implement ProductMapper**

```ruby
# lib/product_mapper.rb

class ProductMapper
  MIN_PRICE_CLP      = 1400
  DEFAULT_CATEGORY   = ENV.fetch('WALMART_DEFAULT_CATEGORY', 'Decoración de Hogar, Cocina y Otros')

  def self.to_walmart(product)
    sku   = product['id'].to_s
    price = [product['price'].to_f.round, MIN_PRICE_CLP].max

    {
      'Orderable' => {
        'sku'                => sku,
        'productIdentifiers' => {
          'productIdType' => 'GTIN',
          'productId'     => fake_gtin(sku)
        },
        'productName'              => "TEST - #{product['name']}",
        'brand'                    => product['brand'] || 'Sin marca',
        'price'                    => { 'currency' => 'CLP', 'amount' => price },
        'ShippingWeight'           => product['weight']&.to_f || 0.5,
        'shippingDimensionsHeight' => 10,
        'ShippingDimensionsWidth'  => 10,
        'ShippingDimensionsDepth'  => 10,
        'multipackQuantity'        => 1,
        'startDate'                => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')
      },
      'Visible' => {
        DEFAULT_CATEGORY => {
          'productDescription' => {
            'shortDescription' => (product['description'] || product['name'])[0, 500],
            'mainImageUrl'     => product.dig('images', 0, 'url') || ''
          }
        }
      }
    }
  end

  def self.feed_payload(products)
    {
      'MPItemFeedHeader' => {
        'sellingChannel' => 'marketplace',
        'processMode'    => 'REPLACE',
        'subset'         => 'EXTERNAL',
        'locale'         => 'es',
        'version'        => '4.46',
        'mart'           => 'WALMART_CL'
      },
      'MPItem' => products.map { |p| to_walmart(p) }
    }
  end

  def self.fake_gtin(sku)
    numeric = sku.gsub(/\D/, '').rjust(14, '0')
    numeric[-14, 14] || numeric.rjust(14, '0')
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/product_mapper_spec.rb`
Expected: `6 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/product_mapper.rb spec/product_mapper_spec.rb
git commit -m "feat: ProductMapper transforms Jumpseller products to Walmart spec 4.46"
```

---

## Task 6: OrderMapper

**Files:**
- Create: `lib/order_mapper.rb`
- Create: `spec/order_mapper_spec.rb`

**Context:** Transforms a Walmart order into a Jumpseller order. Payment method comes from `JUMPSELLER_PAYMENT_METHOD_ID` env var (the user creates a payment method named "walmart" in their Jumpseller store settings and puts its ID here). Order is created with `status: paid`.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/order_mapper_spec.rb
require 'spec_helper'
require_relative '../lib/order_mapper'

RSpec.describe OrderMapper do
  let(:walmart_order) do
    {
      'purchaseOrderId' => 'WM-ORDER-001',
      'customerOrderId' => 'CUST-001',
      'orderLines' => {
        'orderLine' => [
          {
            'item' => { 'sku' => '42', 'productName' => 'TEST - Camiseta Roja' },
            'orderLineQuantity' => { 'unitOfMeasurement' => 'EACH', 'amount' => '2' }
          }
        ]
      }
    }
  end

  describe '.to_jumpseller' do
    subject(:result) { OrderMapper.to_jumpseller(walmart_order) }

    it 'sets status to paid' do
      expect(result['status']).to eq('paid')
    end

    it 'sets payment method from env var' do
      ENV['JUMPSELLER_PAYMENT_METHOD_ID'] = 'walmart'
      expect(result['payment_method_id']).to eq('walmart')
    end

    it 'maps order lines to products with id and qty' do
      expect(result['products']).to eq([{ 'id' => 42, 'qty' => 2 }])
    end

    it 'includes Walmart order ID in additional_information' do
      expect(result['additional_information']).to include('WM-ORDER-001')
    end
  end

  describe 'with single order line (not array)' do
    it 'handles a single orderLine object (not wrapped in array)' do
      single_line_order = walmart_order.merge(
        'orderLines' => {
          'orderLine' => {
            'item' => { 'sku' => '7', 'productName' => 'TEST - Otro' },
            'orderLineQuantity' => { 'unitOfMeasurement' => 'EACH', 'amount' => '1' }
          }
        }
      )
      result = OrderMapper.to_jumpseller(single_line_order)
      expect(result['products']).to eq([{ 'id' => 7, 'qty' => 1 }])
    end
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/order_mapper_spec.rb`
Expected: `LoadError`

- [ ] **Step 3: Implement OrderMapper**

```ruby
# lib/order_mapper.rb

class OrderMapper
  def self.to_jumpseller(walmart_order)
    lines = walmart_order.dig('orderLines', 'orderLine')
    lines = [lines] unless lines.is_a?(Array)

    {
      'status'                 => 'paid',
      'payment_method_id'      => ENV.fetch('JUMPSELLER_PAYMENT_METHOD_ID', 'walmart'),
      'products'               => lines.map { |line|
        {
          'id'  => line.dig('item', 'sku').to_i,
          'qty' => line.dig('orderLineQuantity', 'amount').to_i
        }
      },
      'additional_information' => "Walmart Order: #{walmart_order['purchaseOrderId']}"
    }
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/order_mapper_spec.rb`
Expected: `4 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/order_mapper.rb spec/order_mapper_spec.rb
git commit -m "feat: OrderMapper translates Walmart orders to Jumpseller format"
```

---

## Task 7: Rake tasks

**Files:**
- Create: `Rakefile`

**Context:** 4 tasks. `publish_products` publishes all Jumpseller products to Walmart in batches of 20. `sync_inventory` reconciles all stock. `sync_orders` polls Walmart for new orders and creates them in Jumpseller. `status` shows last feed status and last processed order ID.

- [ ] **Step 1: Create Rakefile**

```ruby
# Rakefile
require 'dotenv/load'
require_relative 'lib/walmart_client'
require_relative 'lib/jumpseller_client'
require_relative 'lib/product_mapper'
require_relative 'lib/order_mapper'

LAST_ORDER_FILE = '.last_order_id'.freeze

def log(task, message)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [#{task}] #{message}"
end

desc 'Publish all Jumpseller products to Walmart Marketplace'
task :publish_products do
  walmart  = WalmartClient.new
  js       = JumpsellerClient.new

  log('publish_products', 'Fetching products from Jumpseller...')
  raw      = js.all_products
  products = raw.map { |p| p.is_a?(Hash) && p['product'] ? p['product'] : p }

  log('publish_products', "Found #{products.size} products. Publishing in batches of 20...")

  products.each_slice(20).with_index(1) do |batch, i|
    payload  = ProductMapper.feed_payload(batch)
    response = walmart.create_items_feed(payload)
    feed_id  = response['feedId']
    log('publish_products', "Batch #{i}: feedId=#{feed_id}")

    # Poll until feed is processed (max 2 minutes)
    30.times do
      sleep 4
      status = walmart.get_feed_status(feed_id)
      processing = status['feedStatus']
      log('publish_products', "  feedId=#{feed_id} status=#{processing}")
      break if %w[PROCESSED ERROR].include?(processing)
    end
  end

  log('publish_products', 'Done.')
end

desc 'Reconcile all Jumpseller inventory into Walmart (daily fallback)'
task :sync_inventory do
  walmart  = WalmartClient.new
  js       = JumpsellerClient.new

  log('sync_inventory', 'Fetching products from Jumpseller...')
  raw      = js.all_products
  products = raw.map { |p| p.is_a?(Hash) && p['product'] ? p['product'] : p }

  products.each do |product|
    sku   = product['id'].to_s
    stock = product['stock'].to_i
    begin
      walmart.update_inventory(sku, stock)
      log('sync_inventory', "SKU #{sku} → #{stock} units")
    rescue => e
      log('sync_inventory', "ERROR SKU #{sku}: #{e.message}")
    end
  end

  log('sync_inventory', 'Done.')
end

desc 'Fetch new Walmart orders and create them in Jumpseller'
task :sync_orders do
  walmart = WalmartClient.new
  js      = JumpsellerClient.new

  last_id = File.exist?(LAST_ORDER_FILE) ? File.read(LAST_ORDER_FILE).strip : nil
  start_date = last_id ? nil : (Time.now - 86400).strftime('%Y-%m-%dT%H:%M:%SZ')

  log('sync_orders', "Fetching orders from Walmart (since: #{start_date || "last id=#{last_id}"})...")

  response = walmart.get_orders(status: 'Created', created_start_date: start_date)
  orders_data = response.dig('list', 'elements', 'order') || []
  orders_data = [orders_data] unless orders_data.is_a?(Array)
  orders_data = orders_data.compact

  if orders_data.empty?
    log('sync_orders', 'No new orders.')
    next
  end

  newest_id = nil
  orders_data.each do |order|
    po_id = order['purchaseOrderId']
    next if last_id && po_id <= last_id

    begin
      jumpseller_payload = OrderMapper.to_jumpseller(order)
      js.create_order(jumpseller_payload)
      walmart.acknowledge_order(po_id)
      log('sync_orders', "Order #{po_id} → created in Jumpseller and acknowledged")
      newest_id = po_id if newest_id.nil? || po_id > newest_id
    rescue => e
      log('sync_orders', "ERROR order #{po_id}: #{e.message}")
    end
  end

  File.write(LAST_ORDER_FILE, newest_id) if newest_id
  log('sync_orders', 'Done.')
end

desc 'Show integration status'
task :status do
  last_id = File.exist?(LAST_ORDER_FILE) ? File.read(LAST_ORDER_FILE).strip : 'none'
  puts "Last processed Walmart order ID: #{last_id}"
  puts "WALMART_ENV: #{ENV.fetch('WALMART_ENV', 'not set')}"
  puts "JUMPSELLER_LOGIN: #{ENV.fetch('JUMPSELLER_LOGIN', 'not set')}"
end
```

- [ ] **Step 2: Test rake task loads without errors**

Run: `bundle exec rake -T`
Expected:
```
rake publish_products  # Publish all Jumpseller products to Walmart Marketplace
rake status            # Show integration status
rake sync_inventory    # Reconcile all Jumpseller inventory into Walmart (daily fallback)
rake sync_orders       # Fetch new Walmart orders and create them in Jumpseller
```

- [ ] **Step 3: Test status task runs**

Run: `bundle exec rake status`
Expected: prints env status with no errors

- [ ] **Step 4: Commit**

```bash
git add Rakefile
git commit -m "feat: Rake tasks for publish_products, sync_inventory, sync_orders, status"
```

---

## Task 8: Sinatra webhook receiver

**Files:**
- Create: `app.rb`
- Create: `config.ru`
- Create: `spec/app_spec.rb`

**Context:** Receives Jumpseller `product.updated` webhook. Validates HMAC-SHA256 signature using `JUMPSELLER_WEBHOOK_SECRET`. Payload contains `{"product": {"id": 42, "stock": 15, ...}}`. On valid request: updates Walmart inventory for that SKU.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/app_spec.rb
require 'spec_helper'
require 'rack/test'
require 'openssl'
require_relative '../app'

RSpec.describe 'Webhook App' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  let(:secret)  { ENV['JUMPSELLER_WEBHOOK_SECRET'] }
  let(:payload) { { product: { id: 42, stock: 7 } }.to_json }

  def signature_for(body)
    OpenSSL::HMAC.hexdigest('SHA256', secret, body)
  end

  describe 'POST /webhook/inventory' do
    context 'with valid signature' do
      it 'returns 200 and triggers inventory update' do
        stub_request(:post, 'https://marketplace.walmartapis.com/v3/token')
          .to_return(status: 200,
                     body: { access_token: 'tok', expires_in: 900 }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
        stub_request(:put, 'https://marketplace.walmartapis.com/v3/inventory?sku=42')
          .to_return(status: 200, body: '{}',
                     headers: { 'Content-Type' => 'application/json' })

        post '/webhook/inventory',
             payload,
             'CONTENT_TYPE'            => 'application/json',
             'HTTP_X_JUMPSELLER_HMAC_SHA256' => signature_for(payload)

        expect(last_response.status).to eq(200)
      end
    end

    context 'with invalid signature' do
      it 'returns 401' do
        post '/webhook/inventory',
             payload,
             'CONTENT_TYPE'            => 'application/json',
             'HTTP_X_JUMPSELLER_HMAC_SHA256' => 'invalidsignature'

        expect(last_response.status).to eq(401)
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/app_spec.rb`
Expected: `LoadError: cannot load such file -- .../app`

- [ ] **Step 3: Implement app.rb**

```ruby
# app.rb
require 'sinatra'
require 'json'
require 'openssl'
require 'dotenv/load'
require_relative 'lib/walmart_client'

WEBHOOK_SECRET = ENV.fetch('JUMPSELLER_WEBHOOK_SECRET')

helpers do
  def valid_signature?(body, received_sig)
    expected = OpenSSL::HMAC.hexdigest('SHA256', WEBHOOK_SECRET, body)
    Rack::Utils.secure_compare(expected, received_sig.to_s)
  end

  def log(message)
    puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [webhook] #{message}"
  end
end

post '/webhook/inventory' do
  body_str = request.body.read
  received_sig = request.env['HTTP_X_JUMPSELLER_HMAC_SHA256']

  unless valid_signature?(body_str, received_sig)
    halt 401, 'Invalid signature'
  end

  payload = JSON.parse(body_str)
  product = payload['product']

  unless product && product['id']
    halt 400, 'Missing product data'
  end

  sku   = product['id'].to_s
  stock = product['stock'].to_i

  begin
    WalmartClient.new.update_inventory(sku, stock)
    log("SKU #{sku} → #{stock} units (webhook)")
    status 200
  rescue => e
    log("ERROR SKU #{sku}: #{e.message}")
    halt 500, 'Internal error'
  end
end

get '/health' do
  'OK'
end
```

- [ ] **Step 4: Create config.ru**

```ruby
# config.ru
require_relative 'app'
run Sinatra::Application
```

- [ ] **Step 5: Run tests**

Run: `bundle exec rspec spec/app_spec.rb`
Expected: `2 examples, 0 failures`

- [ ] **Step 6: Run full test suite**

Run: `bundle exec rspec`
Expected: all examples pass, 0 failures

- [ ] **Step 7: Commit**

```bash
git add app.rb config.ru spec/app_spec.rb
git commit -m "feat: Sinatra webhook receiver with HMAC signature validation"
```

---

## Task 9: GitHub Actions cron

**Files:**
- Create: `.github/workflows/daily_sync.yml`

- [ ] **Step 1: Create workflow file**

```yaml
# .github/workflows/daily_sync.yml
name: Daily Sync

on:
  schedule:
    - cron: '0 6 * * *'   # 06:00 UTC = 03:00 Chile (UTC-3)
  workflow_dispatch:        # allow manual trigger from GitHub UI

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Sync inventory
        env:
          JUMPSELLER_LOGIN: ${{ secrets.JUMPSELLER_LOGIN }}
          JUMPSELLER_AUTH_TOKEN: ${{ secrets.JUMPSELLER_AUTH_TOKEN }}
          WALMART_CLIENT_ID: ${{ secrets.WALMART_CLIENT_ID }}
          WALMART_CLIENT_SECRET: ${{ secrets.WALMART_CLIENT_SECRET }}
          WALMART_ENV: ${{ secrets.WALMART_ENV }}
          WALMART_DEFAULT_CATEGORY: ${{ secrets.WALMART_DEFAULT_CATEGORY }}
          JUMPSELLER_PAYMENT_METHOD_ID: ${{ secrets.JUMPSELLER_PAYMENT_METHOD_ID }}
        run: bundle exec rake sync_inventory

      - name: Sync orders
        env:
          JUMPSELLER_LOGIN: ${{ secrets.JUMPSELLER_LOGIN }}
          JUMPSELLER_AUTH_TOKEN: ${{ secrets.JUMPSELLER_AUTH_TOKEN }}
          WALMART_CLIENT_ID: ${{ secrets.WALMART_CLIENT_ID }}
          WALMART_CLIENT_SECRET: ${{ secrets.WALMART_CLIENT_SECRET }}
          WALMART_ENV: ${{ secrets.WALMART_ENV }}
          JUMPSELLER_PAYMENT_METHOD_ID: ${{ secrets.JUMPSELLER_PAYMENT_METHOD_ID }}
        run: bundle exec rake sync_orders
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/daily_sync.yml
git commit -m "ci: GitHub Actions cron for daily inventory and order sync"
```

---

## Task 10: Deploy to Render.com

**Files:**
- Create: `render.yaml`

- [ ] **Step 1: Create render.yaml**

```yaml
# render.yaml
services:
  - type: web
    name: jumpseller-walmart-webhook
    env: ruby
    buildCommand: bundle install
    startCommand: bundle exec rackup config.ru -p $PORT -o 0.0.0.0
    envVars:
      - key: JUMPSELLER_LOGIN
        sync: false
      - key: JUMPSELLER_AUTH_TOKEN
        sync: false
      - key: JUMPSELLER_WEBHOOK_SECRET
        sync: false
      - key: WALMART_CLIENT_ID
        sync: false
      - key: WALMART_CLIENT_SECRET
        sync: false
      - key: WALMART_ENV
        value: sandbox
      - key: WALMART_DEFAULT_CATEGORY
        value: "Decoración de Hogar, Cocina y Otros"
      - key: JUMPSELLER_PAYMENT_METHOD_ID
        value: walmart
```

- [ ] **Step 2: Commit**

```bash
git add render.yaml
git commit -m "chore: Render.com deployment config"
```

---

## Task 11: Register webhook in Jumpseller and smoke test

**This task is manual.**

- [ ] **Step 1: Start local server with ngrok**

```bash
# Terminal 1
bundle exec rackup config.ru -p 4567

# Terminal 2
ngrok http 4567
```

Copy the ngrok HTTPS URL (e.g. `https://abc123.ngrok.io`).

- [ ] **Step 2: Register webhook in Jumpseller**

In Jumpseller admin → Settings → Webhooks → Add webhook:
- Event: `product.updated`
- URL: `https://abc123.ngrok.io/webhook/inventory`
- Secret: value of your `JUMPSELLER_WEBHOOK_SECRET`

- [ ] **Step 3: Test by updating a product's stock in Jumpseller**

Update any product's stock in Jumpseller admin. Watch terminal 1 for:
```
[2026-03-26 10:00:00] [webhook] SKU 42 → 5 units (webhook)
```

- [ ] **Step 4: Run publish_products to load products into Walmart sandbox**

```bash
bundle exec rake publish_products
```

Watch for feed IDs and PROCESSED status.

- [ ] **Step 5: Check status**

```bash
bundle exec rake status
```

---

## Task 12: Deploy to Render and configure GitHub secrets

**This task is manual.**

- [ ] **Step 1: Push repo to GitHub**

```bash
git remote add origin https://github.com/YOUR_USERNAME/jumpseller-walmart-sync.git
git push -u origin main
```

- [ ] **Step 2: Create Render web service**

Go to render.com → New → Web Service → connect your GitHub repo. Render will detect `render.yaml`. Set all `sync: false` env vars in the Render dashboard.

- [ ] **Step 3: Update Jumpseller webhook URL**

Replace ngrok URL with the Render URL (e.g. `https://jumpseller-walmart-webhook.onrender.com/webhook/inventory`).

- [ ] **Step 4: Add GitHub Secrets for cron**

In GitHub repo → Settings → Secrets and variables → Actions → add:
- `JUMPSELLER_LOGIN`
- `JUMPSELLER_AUTH_TOKEN`
- `WALMART_CLIENT_ID`
- `WALMART_CLIENT_SECRET`
- `WALMART_ENV` = `sandbox`
- `WALMART_DEFAULT_CATEGORY`
- `JUMPSELLER_PAYMENT_METHOD_ID`

- [ ] **Step 5: Trigger workflow manually to verify**

In GitHub → Actions → Daily Sync → Run workflow. Check logs confirm `sync_inventory` and `sync_orders` complete successfully.

---

## Notes

- **Inventory = 0 in sandbox:** The integration sends actual Jumpseller stock to Walmart. For sandbox testing, Walmart may unpublish items with stock > 0. If that happens, temporarily override in `sync_inventory` to always send 0.
- **Jumpseller payment method:** Create a payment method named "walmart" in Jumpseller Settings → Payment Methods → Custom. Use its ID in `JUMPSELLER_PAYMENT_METHOD_ID`.
- **Walmart inventory delay:** After creating items, inventory updates may fail for up to 10 minutes. If `sync_inventory` logs errors right after `publish_products`, wait 10 minutes and retry.
- **First sync_orders run:** Without a `.last_order_id` file, the task fetches orders from the last 24 hours. Commit the `.last_order_id` file if you need to persist the cursor between GitHub Actions runs (or store it as an artifact).
