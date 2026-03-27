# Rakefile
require 'dotenv/load'
require_relative 'lib/walmart_client'
require_relative 'lib/jumpseller_client'
require_relative 'lib/product_mapper'
require_relative 'lib/order_mapper'

LAST_ORDER_FILE = '.last_order_id'.freeze

def log(task, message)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [#{task}] #{message}"
end

desc 'Publish all Jumpseller products to Walmart Marketplace'
task :publish_products do
  walmart  = WalmartClient.new
  js       = JumpsellerClient.new

  log('publish_products', 'Fetching products from Jumpseller...')
  raw      = js.all_products
  products = raw.map { |p| p.is_a?(Hash) && p['product'] ? p['product'] : p }

  log('publish_products', "Found #{products.size} products. Publishing in batches of 20...")

  products.each_slice(20).with_index(1) do |batch, i|
    payload  = ProductMapper.feed_payload(batch)
    response = walmart.create_items_feed(payload)
    feed_id  = response['feedId']
    log('publish_products', "Batch #{i}: feedId=#{feed_id}")

    # Poll until feed is processed (max 2 minutes)
    30.times do
      sleep 4
      status = walmart.get_feed_status(feed_id)
      processing = status['feedStatus']
      log('publish_products', "  feedId=#{feed_id} status=#{processing}")
      break if %w[PROCESSED ERROR].include?(processing)
    end
  end

  log('publish_products', 'Done.')
end

desc 'Reconcile all Jumpseller inventory into Walmart (daily fallback)'
task :sync_inventory do
  walmart  = WalmartClient.new
  js       = JumpsellerClient.new

  log('sync_inventory', 'Fetching products from Jumpseller...')
  raw      = js.all_products
  products = raw.map { |p| p.is_a?(Hash) && p['product'] ? p['product'] : p }

  products.each do |product|
    sku   = product['id'].to_s
    stock = product['stock'].to_i
    begin
      walmart.update_inventory(sku, stock)
      log('sync_inventory', "SKU #{sku} → #{stock} units")
    rescue => e
      log('sync_inventory', "ERROR SKU #{sku}: #{e.message}")
    end
  end

  log('sync_inventory', 'Done.')
end

desc 'Fetch new Walmart orders and create them in Jumpseller'
task :sync_orders do
  walmart = WalmartClient.new
  js      = JumpsellerClient.new

  last_id = File.exist?(LAST_ORDER_FILE) ? File.read(LAST_ORDER_FILE).strip : nil
  start_date = last_id ? nil : (Time.now - 86400).strftime('%Y-%m-%dT%H:%M:%SZ')

  log('sync_orders', "Fetching orders from Walmart (since: #{start_date || "last id=#{last_id}"})...")

  response = walmart.get_orders(status: 'Created', created_start_date: start_date)
  orders_data = response.dig('list', 'elements', 'order') || []
  orders_data = [orders_data] unless orders_data.is_a?(Array)
  orders_data = orders_data.compact

  if orders_data.empty?
    log('sync_orders', 'No new orders.')
    return
  end

  newest_id = nil
  orders_data.each do |order|
    po_id = order['purchaseOrderId']
    next if last_id && po_id.to_i <= last_id.to_i

    begin
      jumpseller_payload = OrderMapper.to_jumpseller(order)
      js.create_order(jumpseller_payload)
      walmart.acknowledge_order(po_id)
      log('sync_orders', "Order #{po_id} → created in Jumpseller and acknowledged")
      newest_id = po_id if newest_id.nil? || po_id.to_i > newest_id.to_i
    rescue => e
      log('sync_orders', "ERROR order #{po_id}: #{e.message}")
    end
  end

  File.write(LAST_ORDER_FILE, newest_id) if newest_id
  log('sync_orders', 'Done.')
end

desc 'Show integration status'
task :status do
  last_id = File.exist?(LAST_ORDER_FILE) ? File.read(LAST_ORDER_FILE).strip : 'none'
  puts "Last processed Walmart order ID: #{last_id}"
  puts "WALMART_ENV: #{ENV.fetch('WALMART_ENV', 'not set')}"
  puts "JUMPSELLER_LOGIN: #{ENV.fetch('JUMPSELLER_LOGIN', 'not set')}"
end
