#!/usr/bin/env ruby
# Polls Walmart for new orders and creates them in Jumpseller.
# Tracks processed order IDs in data/processed_orders.json to avoid duplicates.
# Run on a cron (e.g. every 15 min) or via Rake task.

require 'dotenv'
Dotenv.overload
require 'json'
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

require 'fileutils'

walmart  = WalmartClient.new
jumpseller = JumpsellerClient.new
processed  = load_processed

log "Checking Walmart for new orders..."

# Fetch orders created in last 7 days (Walmart requires a date range)
since = (Time.now - 7 * 86_400).strftime('%Y-%m-%dT%H:%M:%SZ')
response = walmart.get_orders(status: 'Created', created_start_date: since)
orders   = Array(response.dig('list', 'elements', 'order'))

log "Found #{orders.size} Created order(s) from Walmart"

new_count = 0
orders.each do |order|
  order_id = order['purchaseOrderId']

  if processed[order_id]
    log "  SKIP #{order_id} (already processed on #{processed[order_id]['processed_at']})"
    next
  end

  log "  NEW  #{order_id} — #{order.dig('shippingInfo', 'postalAddress', 'name')}"

  # 1. Map and create in Jumpseller
  js_payload = OrderMapper.to_jumpseller(order)
  js_response = jumpseller.create_order(js_payload)
  js_order_id = js_response.dig('order', 'id') || js_response['id']

  log "       → Jumpseller order created: ##{js_order_id}"

  # 2. Acknowledge in Walmart so it moves to Acknowledged status
  walmart.acknowledge_order(order_id)
  log "       → Walmart order acknowledged"

  # 3. Record as processed
  processed[order_id] = {
    'processed_at'  => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'js_order_id'   => js_order_id,
    'customer_name' => order.dig('shippingInfo', 'postalAddress', 'name')
  }
  new_count += 1
end

save_processed(processed)
log "Done. #{new_count} new order(s) synced."
