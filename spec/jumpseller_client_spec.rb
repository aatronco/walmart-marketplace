# spec/jumpseller_client_spec.rb
require 'spec_helper'
require_relative '../lib/jumpseller_client'

RSpec.describe JumpsellerClient do
  let(:client) { JumpsellerClient.new }
  let(:base)   { 'https://api.jumpseller.com/v1' }
  let(:auth)   { { login: 'test_login', authtoken: 'test_token' } }

  describe '#products' do
    it 'returns products for a given page' do
      response_body = [
        { 'product' => { 'id' => 1, 'name' => 'Product 1', 'price' => 5000, 'stock' => 10 } }
      ].to_json
      stub_request(:get, "#{base}/products.json")
        .with(query: hash_including('login' => 'test_login', 'authtoken' => 'test_token', 'page' => '1', 'limit' => '100'))
        .to_return(status: 200, body: response_body,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.products(page: 1)
      expect(result.first['product']['name']).to eq('Product 1')
    end
  end

  describe '#all_products' do
    it 'paginates until a page with fewer than 100 results is returned' do
      page1 = Array.new(100) { |i| { 'product' => { 'id' => i, 'name' => "P#{i}" } } }.to_json
      page2 = [{ 'product' => { 'id' => 100, 'name' => 'P100' } }].to_json

      stub_request(:get, "#{base}/products.json")
        .with(query: hash_including('page' => '1'))
        .to_return(status: 200, body: page1, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "#{base}/products.json")
        .with(query: hash_including('page' => '2'))
        .to_return(status: 200, body: page2, headers: { 'Content-Type' => 'application/json' })

      result = client.all_products
      expect(result.length).to eq(101)
    end
  end

  describe '#create_order' do
    it 'posts order payload to Jumpseller' do
      order_data = { 'status' => 'paid', 'products' => [{ 'id' => 1, 'qty' => 2 }] }
      stub_request(:post, "#{base}/orders.json")
        .to_return(status: 201, body: { 'order' => { 'id' => 999 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.create_order(order_data)
      expect(result['order']['id']).to eq(999)
    end
  end
end
