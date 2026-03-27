# spec/order_mapper_spec.rb
require 'spec_helper'
require_relative '../lib/order_mapper'

RSpec.describe OrderMapper do
  let(:walmart_order) do
    {
      'purchaseOrderId' => 'WM-ORDER-001',
      'customerOrderId' => 'CUST-001',
      'orderLines' => {
        'orderLine' => [
          {
            'item' => { 'sku' => '42', 'productName' => 'TEST - Camiseta Roja' },
            'orderLineQuantity' => { 'unitOfMeasurement' => 'EACH', 'amount' => '2' }
          }
        ]
      }
    }
  end

  describe '.to_jumpseller' do
    subject(:result) { OrderMapper.to_jumpseller(walmart_order) }

    it 'sets status to paid' do
      expect(result['status']).to eq('paid')
    end

    it 'sets payment method from env var' do
      ENV['JUMPSELLER_PAYMENT_METHOD_ID'] = 'walmart'
      expect(result['payment_method_id']).to eq('walmart')
    end

    it 'maps order lines to products with id and qty' do
      expect(result['products']).to eq([{ 'id' => 42, 'qty' => 2 }])
    end

    it 'includes Walmart order ID in additional_information' do
      expect(result['additional_information']).to include('WM-ORDER-001')
    end
  end

  describe 'with single order line (not array)' do
    it 'handles a single orderLine object (not wrapped in array)' do
      single_line_order = walmart_order.merge(
        'orderLines' => {
          'orderLine' => {
            'item' => { 'sku' => '7', 'productName' => 'TEST - Otro' },
            'orderLineQuantity' => { 'unitOfMeasurement' => 'EACH', 'amount' => '1' }
          }
        }
      )
      result = OrderMapper.to_jumpseller(single_line_order)
      expect(result['products']).to eq([{ 'id' => 7, 'qty' => 1 }])
    end
  end
end
