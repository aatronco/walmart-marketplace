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

  # Looks up a customer by email; creates them if not found.
  # address hash keys: :name, :surname, :address, :city, :region, :country, :municipality
  # Returns the Jumpseller customer ID (integer).
  def find_or_create_customer(email, first_name, last_name, phone, address: {})
    results  = get('/customers.json', email: email, limit: 1)
    existing = Array(results).first

    if existing
      c = existing.is_a?(Hash) && existing['customer'] ? existing['customer'] : existing
      customer_id = c['id']
      # Add shipping address if the customer has none
      if address.any? && Array(c['shipping_addresses']).empty?
        put("/customers/#{customer_id}.json", {
          customer: { shipping_address: build_js_address(first_name, last_name, address) }
        })
      end
      return customer_id
    end

    payload = {
      customer: {
        email:    email,
        fullname: "#{first_name} #{last_name}".strip,
        phone:    phone.to_s,
        status:   'approved'
      }
    }
    payload[:customer][:shipping_address] = build_js_address(first_name, last_name, address) if address.any?

    result = post('/customers.json', payload)
    c = result.is_a?(Hash) && result['customer'] ? result['customer'] : result
    c['id']
  end

  private

  def build_js_address(first_name, last_name, addr)
    {
      name:         first_name.to_s,
      surname:      last_name.to_s,
      address:      addr[:address].to_s,
      city:         addr[:city].to_s,
      region:       addr[:region].to_s,
      country:      addr[:country] || 'CL',
      municipality: addr[:municipality] || addr[:city].to_s
    }
  end

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
