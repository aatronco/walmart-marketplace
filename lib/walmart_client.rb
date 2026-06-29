# lib/walmart_client.rb
require 'faraday'
require 'faraday/retry'
require 'json'
require 'base64'
require 'securerandom'

class WalmartClient
  PROD_URL    = 'https://marketplace.walmartapis.com'.freeze
  SANDBOX_URL = 'https://sandbox.walmartapis.com'.freeze

  def self.base_url
    ENV.fetch('WALMART_ENV', 'production') == 'sandbox' ? SANDBOX_URL : PROD_URL
  end

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

  def update_inventory(sku, walmart_qty)
    put("/v3/inventory?sku=#{URI.encode_www_form_component(sku)}",
        { sku: sku, quantity: { amount: walmart_qty, unit: 'EACH' } })
  end

  # Syncs a batch of {sku => jumpseller_qty} pairs using the safety-buffer formula.
  # Returns hash of {sku => walmart_qty_sent}.
  def sync_inventory_batch(sku_to_jumpseller_qty)
    require_relative 'product_mapper'
    results = {}
    sku_to_jumpseller_qty.each do |sku, js_qty|
      walmart_qty = ProductMapper.walmart_stock(js_qty)
      update_inventory(sku.to_s, walmart_qty)
      results[sku] = walmart_qty
    end
    results
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
    conn = Faraday.new(url: WalmartClient.base_url) do |f|
      f.request :url_encoded
    end
    response = conn.post('/v3/token') do |req|
      req.headers['Authorization']        = "Basic #{credentials}"
      req.headers['WM_MARKET']            = 'cl'
      req.headers['WM_SVC.NAME']          = 'Walmart Marketplace'
      req.headers['WM_QOS.CORRELATION_ID'] = SecureRandom.uuid
      req.headers['Accept']               = 'application/json'
      req.body = 'grant_type=client_credentials'
    end
    data = JSON.parse(response.body)
    @token = data['access_token']
    @token_expires_at = Time.now + data['expires_in'].to_i - 60
  end

  def connection
    Faraday.new(url: WalmartClient.base_url) do |f|
      f.request  :json
      f.request  :retry, max: 3, interval: 1, backoff_factor: 2,
                          exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
    end
  end

  def default_headers
    {
      'WM_SEC.ACCESS_TOKEN'            => token,
      'WM_MARKET'                      => 'cl',
      'WM_GLOBAL_VERSION'              => '3.1',
      'WM_SVC.NAME'                    => 'Walmart Marketplace',
      'WM_QOS.CORRELATION_ID'          => SecureRandom.uuid,
      'WM_CONSUMER.CHANNEL.TYPE'       => ENV.fetch('WALMART_CHANNEL_TYPE', 'Jumpseller'),
      'Accept'                         => 'application/json',
      'Content-Type'                   => 'application/json'
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
