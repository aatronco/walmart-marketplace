require 'sinatra'
require 'json'
require 'openssl'
require 'dotenv'
Dotenv.overload

require_relative 'lib/walmart_client'
require_relative 'lib/jumpseller_client'
require_relative 'lib/product_mapper'
require_relative 'lib/order_mapper'

WEBHOOK_SECRET    = ENV.fetch('JUMPSELLER_WEBHOOK_SECRET')
DASHBOARD_PASSWORD = ENV['DASHBOARD_PASSWORD'].to_s
if DASHBOARD_PASSWORD.empty? && ENV['RACK_ENV'] == 'production'
  raise 'DASHBOARD_PASSWORD must be set in production — an open dashboard exposes /sync publicly'
end

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
  protected!
  erb :dashboard
end

get '/api/products' do
  protected!
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

PROCESSED_FILE = File.expand_path('data/processed_orders.json', __dir__)

def load_processed_orders
  return {} unless File.exist?(PROCESSED_FILE)
  JSON.parse(File.read(PROCESSED_FILE))
rescue JSON::ParserError
  {}
end

def save_processed_orders(processed)
  require 'fileutils'
  FileUtils.mkdir_p(File.dirname(PROCESSED_FILE))
  File.write(PROCESSED_FILE, JSON.pretty_generate(processed))
end

post '/sync' do
  protected!
  content_type :json
  begin
    dashboard_log('Sincronización iniciada')
    js        = JumpsellerClient.new
    wm        = WalmartClient.new
    processed = load_processed_orders
    orders_synced = 0

    # ── 1. Sync orders Walmart → Jumpseller ──────────────────────────────────
    dashboard_log('Buscando órdenes nuevas en Walmart...')
    since    = (Time.now - 7 * 86_400).strftime('%Y-%m-%dT%H:%M:%SZ')
    response = wm.get_orders(status: nil, created_start_date: since)
    all_wm   = Array(response.dig('list', 'elements', 'order'))
    new_orders = all_wm.select do |o|
      Array(o.dig('orderLines', 'orderLine')).any? do |l|
        Array(l.dig('orderLineStatuses', 'orderLineStatus')).any? { |s| s['status'] == 'Created' }
      end
    end
    dashboard_log("#{new_orders.size} orden(es) Walmart en estado Created (#{all_wm.size} total)")

    new_orders.each do |order|
      order_id = order['purchaseOrderId']

      if processed[order_id] && processed[order_id]['js_order_id']
        dashboard_log("SKIP #{order_id} → ya en JS ##{processed[order_id]['js_order_id']}")
        next
      end

      buyer = order.dig('shippingInfo', 'postalAddress', 'name')
      dashboard_log("Procesando #{order_id} — #{buyer}")

      begin
        email       = OrderMapper.email_for(order)
        first, last = OrderMapper.buyer_name(order)
        ship_info2  = order['shippingInfo'] || {}
        phone       = ship_info2['phone'].to_s
        addr_raw2   = ship_info2['postalAddress'] || {}
        js_address  = {
          address:      [addr_raw2['address1'], addr_raw2['address2']].compact.map(&:strip).reject(&:empty?).join(', '),
          city:         addr_raw2['city'].to_s,
          region:       OrderMapper::REGION_CODES[addr_raw2['state'].to_s] || '12',
          country:      'CL',
          municipality: addr_raw2['city'].to_s
        }
        customer_id = js.find_or_create_customer(email, first, last, phone, address: js_address)
        dashboard_log("  Cliente JS: ##{customer_id}")

        js_payload  = OrderMapper.to_jumpseller(order, customer_id: customer_id)
        js_response = js.create_order(js_payload)
        js_order_id = js_response.dig('order', 'id') || js_response['id']

        if js_order_id
          dashboard_log("  Orden JS: ##{js_order_id} ✓", level: :success)
        else
          dashboard_log("  ERROR JS: #{js_response.inspect}", level: :error)
        end

        wm.acknowledge_order(order_id)
        dashboard_log("  Walmart acknowledged ✓")

        processed[order_id] = {
          'processed_at'  => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
          'js_order_id'   => js_order_id,
          'customer_id'   => customer_id,
          'customer_name' => buyer
        }
        save_processed_orders(processed)
        orders_synced += 1
      rescue => e
        dashboard_log("  ERROR #{order_id}: #{e.message}", level: :error)
      end
    end

    # ── 2. Sync inventory Jumpseller → Walmart ────────────────────────────────
    dashboard_log('Sincronizando inventario...')
    products = js.all_products
    sku_to_qty = {}
    products.each do |raw|
      p = raw.is_a?(Hash) && raw['product'] ? raw['product'] : raw
      sku_to_qty[p['id'].to_s] = p['stock'].to_i
    end

    dashboard_log("#{sku_to_qty.size} productos de Jumpseller")
    inv_results = wm.sync_inventory_batch(sku_to_qty)
    $last_sync  = Time.now.strftime('%Y-%m-%d %H:%M:%S')

    inv_results.each do |sku, wm_qty|
      dashboard_log("SKU #{sku}: #{sku_to_qty[sku]} (JS) → #{wm_qty} (WM)")
    end
    dashboard_log("Sync completado ✓ — #{orders_synced} orden(es), #{inv_results.size} SKU(s)", level: :success)

    { ok: true, orders_synced: orders_synced, inventory_synced: inv_results.size,
      last_sync: $last_sync }.to_json
  rescue => e
    dashboard_log("ERROR: #{e.message}", level: :error)
    status 500
    { error: e.message }.to_json
  end
end

get '/api/logs' do
  protected!
  content_type :json
  entries = $log_mutex.synchronize { $dashboard_logs.last(50) }
  { logs: entries, last_sync: $last_sync }.to_json
end

# ── Webhook (existing) ─────────────────────────────────────────────────────────

helpers do
  def protected!
    return if authorized?
    headers['WWW-Authenticate'] = 'Basic realm="Walmart Dashboard"'
    halt 401, 'Acceso no autorizado'
  end

  def authorized?
    return true if DASHBOARD_PASSWORD.empty?
    @auth ||= Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? &&
      Rack::Utils.secure_compare(@auth.credentials[1], DASHBOARD_PASSWORD)
  end

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
