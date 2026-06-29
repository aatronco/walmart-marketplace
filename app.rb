require 'sinatra'
require 'json'
require 'openssl'
require 'dotenv'
Dotenv.overload

require_relative 'lib/walmart_client'
require_relative 'lib/jumpseller_client'
require_relative 'lib/product_mapper'

WEBHOOK_SECRET = ENV.fetch('JUMPSELLER_WEBHOOK_SECRET')

LOG_BUFFER_SIZE = 150
$dashboard_logs = []
$last_sync      = nil
$log_mutex      = Mutex.new

def dashboard_log(msg, level: :info)
  entry = { time: Time.now.strftime('%H:%M:%S'), level: level.to_s, msg: msg }
  $log_mutex.synchronize do
    $dashboard_logs.push(entry)
    $dashboard_logs.shift if $dashboard_logs.size > LOG_BUFFER_SIZE
  end
  puts "[#{entry[:time]}] #{msg}"
  entry
end

# ── Dashboard ──────────────────────────────────────────────────────────────────

get '/' do
  erb :dashboard
end

get '/api/products' do
  content_type :json
  begin
    products = JumpsellerClient.new.all_products.map do |raw|
      p        = raw.is_a?(Hash) && raw['product'] ? raw['product'] : raw
      js_stock = p['stock'].to_i
      {
        id:       p['id'],
        sku:      p['id'].to_s,
        name:     (p['name'] || '(sin nombre)').strip,
        js_stock: js_stock,
        wm_stock: ProductMapper.walmart_stock(js_stock)
      }
    end
    { products: products, fetched_at: Time.now.strftime('%H:%M:%S') }.to_json
  rescue => e
    status 500
    { error: e.message }.to_json
  end
end

post '/sync' do
  content_type :json
  begin
    dashboard_log('Sincronización iniciada')
    js       = JumpsellerClient.new
    wm       = WalmartClient.new
    products = js.all_products

    sku_to_qty = {}
    products.each do |raw|
      p = raw.is_a?(Hash) && raw['product'] ? raw['product'] : raw
      sku_to_qty[p['id'].to_s] = p['stock'].to_i
    end

    dashboard_log("#{sku_to_qty.size} productos obtenidos de Jumpseller")
    results    = wm.sync_inventory_batch(sku_to_qty)
    $last_sync = Time.now.strftime('%Y-%m-%d %H:%M:%S')

    results.each do |sku, wm_qty|
      dashboard_log("SKU #{sku}: #{sku_to_qty[sku]} (JS) → #{wm_qty} (Walmart)")
    end
    dashboard_log('Sync completado ✓', level: :success)

    { ok: true, synced: results.size, last_sync: $last_sync, results: results }.to_json
  rescue => e
    dashboard_log("ERROR: #{e.message}", level: :error)
    status 500
    { error: e.message }.to_json
  end
end

get '/api/logs' do
  content_type :json
  entries = $log_mutex.synchronize { $dashboard_logs.last(50) }
  { logs: entries, last_sync: $last_sync }.to_json
end

# ── Webhook (existing) ─────────────────────────────────────────────────────────

helpers do
  def valid_signature?(body, received_sig)
    expected = OpenSSL::HMAC.hexdigest('SHA256', WEBHOOK_SECRET, body)
    Rack::Utils.secure_compare(expected, received_sig.to_s)
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
    dashboard_log("Webhook: SKU #{sku} → #{stock} units")
    status 200
  rescue => e
    dashboard_log("Webhook ERROR SKU #{sku}: #{e.message}", level: :error)
    halt 500, 'Internal error'
  end
end

get '/health' do
  'OK'
end
