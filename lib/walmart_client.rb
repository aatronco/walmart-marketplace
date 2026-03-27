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
      'WM_CONSUMER.CHANNEL.TYPE'      => ENV.fetch('WALMART_CHANNEL_TYPE', 'jumpseller'),
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
