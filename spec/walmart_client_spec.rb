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
end
