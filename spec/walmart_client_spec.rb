# spec/walmart_client_spec.rb
require 'spec_helper'
require_relative '../lib/walmart_client'

RSpec.describe WalmartClient do
  let(:client) { WalmartClient.new }
  let(:token_url) { 'https://marketplace.walmartapis.com/v3/token' }

  def stub_token
    stub_request(:post, token_url)
      .to_return(
        status: 200,
        body: { access_token: 'test_token_123', expires_in: 900 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '#token (via authenticated request)' do
    it 'fetches an OAuth2 token using Basic auth' do
      stub_token
      stub_request(:get, /marketplace\.walmartapis\.com\/v3\/orders/)
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      client.get_orders
      expect(WebMock).to have_requested(:post, token_url)
        .with(body: 'grant_type=client_credentials')
    end

    it 'reuses the token when not expired' do
      stub_token
      stub_request(:get, /marketplace\.walmartapis\.com\/v3\/orders/)
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
        .times(2)

      client.get_orders
      client.get_orders
      expect(WebMock).to have_requested(:post, token_url).once
    end
  end

  describe '#update_inventory' do
    it 'sends PUT with sku and quantity' do
      stub_token
      sku = 'SKU-42'
      stub_request(:put, "https://marketplace.walmartapis.com/v3/inventory?sku=SKU-42")
        .with(body: hash_including('sku' => sku, 'quantity' => { 'amount' => 5, 'unit' => 'EACH' }))
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      result = client.update_inventory(sku, 5)
      expect(result).to eq({})
    end
  end

  describe '#get_orders' do
    it 'fetches orders with Created status' do
      stub_token
      orders_response = { 'list' => { 'elements' => { 'order' => [] } } }
      stub_request(:get, /marketplace\.walmartapis\.com\/v3\/orders/)
        .with(query: hash_including('status' => 'Created'))
        .to_return(status: 200, body: orders_response.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.get_orders
      expect(result).to eq(orders_response)
    end
  end

  describe '#acknowledge_order' do
    it 'posts to the acknowledge endpoint' do
      stub_token
      stub_request(:post, 'https://marketplace.walmartapis.com/v3/orders/PO-123/acknowledge')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      result = client.acknowledge_order('PO-123')
      expect(result).to eq({})
    end
  end
end
