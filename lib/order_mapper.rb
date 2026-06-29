# lib/order_mapper.rb
#
# Converts a Walmart Chile order into a Jumpseller order payload.
# Preserves all available buyer info for statistics and support.

class OrderMapper
  def self.to_jumpseller(walmart_order)
    lines      = Array(walmart_order.dig('orderLines', 'orderLine'))
    ship_info  = walmart_order['shippingInfo'] || {}
    address    = ship_info['postalAddress'] || {}

    full_name  = address['name'].to_s.strip
    first_name, *rest = full_name.split(' ')
    last_name  = rest.join(' ')

    # Walmart doesn't always expose buyer email — use a deterministic placeholder
    # so Jumpseller can still create the customer record.
    email = ship_info['email'].to_s.strip
    email = "walmart+#{walmart_order['purchaseOrderId']}@noreply.walmart.cl" if email.empty?

    {
      'status'          => 'paid',
      'send_email'      => false,   # don't email buyer from Jumpseller — Walmart handles that
      'additional_information' => order_notes(walmart_order),
      'payment_method_name'    => 'Walmart',
      'customer' => {
        'email'      => email,
        'name'       => first_name.to_s,
        'last_name'  => last_name.to_s,
        'phone'      => ship_info['phone'].to_s
      },
      'shipping_address' => {
        'name'       => full_name,
        'address'    => [address['address1'], address['address2']].compact.reject(&:empty?).join(', '),
        'city'       => address['city'].to_s,
        'region'     => address['state'].to_s,
        'country'    => 'CL',
        'postal_code'=> address['postalCode'].to_s,
        'phone'      => ship_info['phone'].to_s
      },
      'products' => lines.map { |line| line_to_product(line) }
    }
  end

  private

  def self.line_to_product(line)
    qty     = line.dig('orderLineQuantity', 'amount').to_i
    sku     = line.dig('item', 'sku').to_s
    name    = line.dig('item', 'productName').to_s

    # Pull unit price from the "PRODUCT" charge if present
    charges = Array(line.dig('charges', 'charge'))
    product_charge = charges.find { |c| c['chargeType'] == 'PRODUCT' } || charges.first
    unit_price = product_charge&.dig('chargeAmount', 'amount').to_f

    {
      'id'    => sku.to_i,
      'qty'   => qty,
      'price' => unit_price,   # for statistics — Jumpseller may override with catalog price
      'name'  => name          # informational
    }
  end

  def self.order_notes(walmart_order)
    [
      "Venta Walmart Marketplace",
      "Walmart Order ID : #{walmart_order['purchaseOrderId']}",
      "Customer Order ID: #{walmart_order['customerOrderId']}",
      "Fecha orden      : #{walmart_order['orderDate']}",
      "Entrega estimada : #{walmart_order.dig('shippingInfo', 'estimatedDeliveryDate')}",
      "Método envío     : #{walmart_order.dig('shippingInfo', 'methodCode')}"
    ].join("\n")
  end
end
