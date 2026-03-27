# spec/spec_helper.rb
require 'webmock/rspec'
require 'dotenv'

Dotenv.load('.env.test')

WebMock.disable_net_connect!(allow_localhost: true)

ENV['JUMPSELLER_LOGIN']           ||= 'test_login'
ENV['JUMPSELLER_AUTH_TOKEN']      ||= 'test_token'
ENV['JUMPSELLER_WEBHOOK_SECRET']  ||= 'test_secret'
ENV['WALMART_CLIENT_ID']          ||= 'test_client_id'
ENV['WALMART_CLIENT_SECRET']      ||= 'test_client_secret'
ENV['WALMART_ENV']                ||= 'sandbox'
