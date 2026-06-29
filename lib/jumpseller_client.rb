# lib/jumpseller_client.rb
require 'faraday'
require 'faraday/retry'
require 'json'
require 'base64'

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

  def update_product(id, attrs)
    put("/products/#{id}.json", { product: attrs })
  end

  def create_order(order_data)
    post('/orders.json', { order: order_data })
  end

  private

  def connection
    Faraday.new(url: BASE_URL) do |f|
      f.request :retry, max: 3, interval: 1, backoff_factor: 2,
                        exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
    end
  end

  def get(path, params = {})
    response = connection.get("#{BASE_URL}#{path}") do |req|
      req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{@login}:#{@authtoken}")}"
      req.headers['Accept'] = 'application/json'
      req.params.merge!(params.transform_keys(&:to_s))
    end
    JSON.parse(response.body)
  end

  def put(path, body)
    response = connection.put("#{BASE_URL}#{path}") do |req|
      req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{@login}:#{@authtoken}")}"
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept']       = 'application/json'
      req.body = body.to_json
    end
    JSON.parse(response.body)
  end

  def post(path, body)
    response = connection.post("#{BASE_URL}#{path}") do |req|
      req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{@login}:#{@authtoken}")}"
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept']       = 'application/json'
      req.body = body.to_json
    end
    JSON.parse(response.body)
  end
end
