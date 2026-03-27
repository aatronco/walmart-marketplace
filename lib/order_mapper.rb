# lib/order_mapper.rb

class OrderMapper
  def self.to_jumpseller(walmart_order)
    lines = walmart_order.dig('orderLines', 'orderLine')
    lines = [lines] unless lines.is_a?(Array)

    {
      'status'                 => 'paid',
      'payment_method_id'      => ENV.fetch('JUMPSELLER_PAYMENT_METHOD_ID', 'walmart'),
      'products'               => lines.map { |line|
        {
          'id'  => line.dig('item', 'sku').to_i,
          'qty' => line.dig('orderLineQuantity', 'amount').to_i
        }
      },
      'additional_information' => "Walmart Order: #{walmart_order['purchaseOrderId']}"
    }
  end
end
