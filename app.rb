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
  body_str     = request.body.read
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
