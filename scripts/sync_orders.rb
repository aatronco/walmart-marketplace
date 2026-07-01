#!/usr/bin/env ruby
# Polls Walmart for new orders and creates them in Jumpseller.
# Tracks processed order IDs in data/processed_orders.json to avoid duplicates.
# Run on a cron (e.g. every 15 min) or via the dashboard sync button.

require 'dotenv'
Dotenv.overload
require 'json'
require 'fileutils'
require_relative '../lib/walmart_client'
require_relative '../lib/jumpseller_client'
require_relative '../lib/order_mapper'

PROCESSED_FILE = File.expand_path('../data/processed_orders.json', __dir__)

def log(msg) = puts("[#{Time.now.strftime('%H:%M:%S')}] #{msg}")

def load_processed
  return {} unless File.exist?(PROCESSED_FILE)
  JSON.parse(File.read(PROCESSED_FILE))
rescue JSON::ParserError
  {}
end

def save_processed(processed)
  FileUtils.mkdir_p(File.dirname(PROCESSED_FILE))
  File.write(PROCESSED_FILE, JSON.pretty_generate(processed))
end

walmart    = WalmartClient.new
jumpseller = JumpsellerClient.new
processed  = load_processed

log 'Checking Walmart for new orders...'

# Fetch last 7 days; filter client-side for Created status because Walmart's
# status query param is unreliable (sometimes returns 0 even with live orders).
since     = (Time.now - 7 * 86_400).strftime('%Y-%m-%dT%H:%M:%SZ')
response  = walmart.get_orders(status: nil, created_start_date: since)
all_orders = Array(response.dig('list', 'elements', 'order'))
orders = all_orders.select do |o|
  Array(o.dig('orderLines', 'orderLine')).any? do |l|
    Array(l.dig('orderLineStatuses', 'orderLineStatus')).any? { |s| s['status'] == 'Created' }
  end
end

log "Found #{orders.size} Created order(s) from Walmart (#{all_orders.size} total fetched)"

new_count = 0
orders.each do |order|
  order_id = order['purchaseOrderId']

  # Skip only if previously processed AND successfully created in Jumpseller.
  # If js_order_id is nil, the previous attempt failed — retry it.
  if processed[order_id] && processed[order_id]['js_order_id']
    log "  SKIP #{order_id} → JS ##{processed[order_id]['js_order_id']} (ya procesado)"
    next
  end

  log "  NEW  #{order_id} — #{order.dig('shippingInfo', 'postalAddress', 'name')}"

  begin
    # 1. Find or create buyer in Jumpseller (with address so order creation works)
    email           = OrderMapper.email_for(order)
    first, last     = OrderMapper.buyer_name(order)
    ship_info       = order['shippingInfo'] || {}
    phone           = ship_info['phone'].to_s
    addr_raw        = ship_info['postalAddress'] || {}
    js_address      = {
      address:      [addr_raw['address1'], addr_raw['address2']].compact.map(&:strip).reject(&:empty?).join(', '),
      city:         addr_raw['city'].to_s,
      region:       OrderMapper::REGION_CODES[addr_raw['state'].to_s] || '12',
      country:      'CL',
      municipality: addr_raw['city'].to_s
    }
    customer_id     = jumpseller.find_or_create_customer(email, first, last, phone, address: js_address)
    log "       → Cliente JS: ##{customer_id} (#{email})"

    # 2. Create order in Jumpseller
    js_payload  = OrderMapper.to_jumpseller(order, customer_id: customer_id)
    js_response = jumpseller.create_order(js_payload)
    js_order_id = js_response.dig('order', 'id') || js_response['id']

    if js_order_id
      log "       → Orden JS: ##{js_order_id} ✓"
    else
      log "       → ERROR al crear orden JS: #{js_response.inspect}"
    end

    # 3. Acknowledge in Walmart (moves order to Acknowledged, stops duplicate delivery)
    walmart.acknowledge_order(order_id)
    log '       → Walmart: acknowledged ✓'

    # 4. Persist immediately so a mid-loop crash doesn't cause duplicates next run
    processed[order_id] = {
      'processed_at'  => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
      'js_order_id'   => js_order_id,
      'customer_id'   => customer_id,
      'customer_name' => order.dig('shippingInfo', 'postalAddress', 'name')
    }
    save_processed(processed)
    new_count += 1

  rescue => e
    log "       → ERROR procesando #{order_id}: #{e.message}"
  end
end

log "Listo. #{new_count} orden(es) nueva(s) sincronizada(s)."
