# spec/app_spec.rb
require 'spec_helper'
require 'rack/test'
require 'openssl'
require_relative '../app'

RSpec.describe 'Webhook App' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  let(:secret)  { ENV['JUMPSELLER_WEBHOOK_SECRET'] }
  let(:payload) { { product: { id: 42, stock: 7 } }.to_json }

  def signature_for(body)
    OpenSSL::HMAC.hexdigest('SHA256', secret, body)
  end

  describe 'POST /webhook/inventory' do
    context 'with valid signature' do
      it 'returns 200 and triggers inventory update' do
        stub_request(:post, 'https://marketplace.walmartapis.com/v3/token')
          .to_return(status: 200,
                     body: { access_token: 'tok', expires_in: 900 }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
        stub_request(:put, 'https://marketplace.walmartapis.com/v3/inventory?sku=42')
          .to_return(status: 200, body: '{}',
                     headers: { 'Content-Type' => 'application/json' })

        post '/webhook/inventory',
             payload,
             'CONTENT_TYPE'                   => 'application/json',
             'HTTP_X_JUMPSELLER_HMAC_SHA256'  => signature_for(payload)

        expect(last_response.status).to eq(200)
      end
    end

    context 'with invalid signature' do
      it 'returns 401' do
        post '/webhook/inventory',
             payload,
             'CONTENT_TYPE'                   => 'application/json',
             'HTTP_X_JUMPSELLER_HMAC_SHA256'  => 'invalidsignature'

        expect(last_response.status).to eq(401)
      end
    end
  end

  describe 'GET /health' do
    it 'returns 200 OK' do
      get '/health'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('OK')
    end
  end
end
