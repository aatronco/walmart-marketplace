#!/usr/bin/env ruby
# Quick smoke test: fetch 1 product from Jumpseller → publish to Walmart → poll feed status
require 'dotenv'
Dotenv.overload
require_relative '../lib/jumpseller_client'
require_relative '../lib/walmart_client'
require_relative '../lib/product_mapper'

def log(msg) = puts("[#{Time.now.strftime('%H:%M:%S')}] #{msg}")

log "ENV: WALMART_ENV=#{ENV['WALMART_ENV']}  JUMPSELLER_LOGIN=#{ENV['JUMPSELLER_LOGIN'][0, 8]}..."

# 1. Fetch all products from Jumpseller
log "Fetching products from Jumpseller..."
js       = JumpsellerClient.new
raw      = js.all_products
all      = raw.map { |p| p.is_a?(Hash) && p['product'] ? p['product'] : p }
products = all.select { |p| p['price'].to_f > 0 && p['status'] != 'disabled' }

log "Found #{all.size} total, #{products.size} publishable (price > 0, not disabled)"
products.each { |p| log "  • #{p['name']} — $#{p['price'].to_i} — cat: #{ProductMapper.walmart_category(p)}" }

if products.empty?
  puts "No publishable products. Aborting."
  exit 1
end

# 2. Map to Walmart format
payload = ProductMapper.feed_payload(products)
log "Mapped #{payload['MPItem'].size} items (mart=#{payload.dig('MPItemFeedHeader', 'mart')})"

# 3. Publish to Walmart
log "Publishing to Walmart (#{ENV['WALMART_ENV']})..."
walmart  = WalmartClient.new
response = walmart.create_items_feed(payload)
log "Response: #{response.inspect}"

feed_id = response['feedId']
unless feed_id
  puts "ERROR: No feedId in response. Full response: #{response.inspect}"
  exit 1
end
log "Feed submitted! feedId=#{feed_id}"

# 4. Poll feed status (up to 2 minutes)
log "Polling feed status..."
40.times do |i|
  sleep 3
  status_resp = walmart.get_feed_status(feed_id)
  status      = status_resp['feedStatus'] || status_resp.dig('feedStatus')
  log "  [#{i + 1}] feedStatus=#{status}  #{status_resp.inspect[0, 200]}"
  if %w[PROCESSED ERROR].include?(status.to_s.upcase)
    log "Feed finished with status: #{status}"
    # Print item errors if any
    items = status_resp.dig('itemsReceived') || status_resp.dig('feedSummary', 'itemsReceived')
    log "  Items received: #{items}  failed: #{status_resp.dig('feedSummary', 'itemsFailed') || status_resp['itemsFailed']}"
    break
  end
end

log "Done."
