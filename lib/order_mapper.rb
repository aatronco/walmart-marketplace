# lib/order_mapper.rb
# Converts a Walmart Chile order into a Jumpseller order payload.

class OrderMapper
  # Walmart state names → Jumpseller region codes
  REGION_CODES = {
    'Metropolitana de Santiago'                 => '12',
    'Valparaíso'                                => '3',
    'Biobío'                                    => '7',
    'Bío-Bío'                                   => '7',
    'La Araucanía'                              => '8',
    'Los Lagos'                                 => '10',
    'Maule'                                     => '11',
    "Libertador General Bernardo O'Higgins"     => '6',
    "O'Higgins"                                 => '6',
    'Coquimbo'                                  => '2',
    'Atacama'                                   => '4',
    'Antofagasta'                               => '1',
    'Tarapacá'                                  => '15',
    'Arica y Parinacota'                        => '16',
    'Los Ríos'                                  => '9',
    'Aysén del General Carlos Ibáñez del Campo' => '13',
    'Aysén'                                     => '13',
    'Magallanes y la Antártica Chilena'         => '14',
    'Magallanes'                                => '14',
    'Ñuble'                                     => '17'
  }.freeze

  # Returns the Jumpseller order payload.
  # customer_id must be a valid Jumpseller customer ID (use JumpsellerClient#find_or_create_customer first).
  def self.to_jumpseller(walmart_order, customer_id:)
    lines     = Array(walmart_order.dig('orderLines', 'orderLine'))
    ship_info = walmart_order['shippingInfo'] || {}
    address   = ship_info['postalAddress'] || {}

    full_name         = address['name'].to_s.strip
    first_name, *rest = full_name.split(' ')
    last_name         = rest.join(' ')
    shipping_price    = extract_shipping_price(walmart_order)

    {
      'status'               => 'Paid',
      'send_email'           => false,
      'payment_method_name'  => 'Walmart',
      'shipping_method_name' => 'Walmart Envío',
      'shipping_price'       => shipping_price,
      'shipping_required'    => true,
      'additional_information' => order_notes(walmart_order),
      'customer' => {
        'id' => customer_id,
        'shipping_address' => {
          'name'         => first_name.to_s,
          'surname'      => last_name.to_s,
          'address'      => build_address(address),
          'city'         => address['city'].to_s,
          'region'       => region_code(address['state'].to_s),
          'country'      => 'CL',
          'municipality' => address['city'].to_s
        }
      },
      'products' => lines.map { |line| line_to_product(line) }
    }
  end

  # Extracts the buyer email; falls back to a deterministic placeholder.
  def self.email_for(walmart_order)
    ship_info = walmart_order['shippingInfo'] || {}
    email = walmart_order['customerEmailId'].to_s.strip
    email = ship_info['email'].to_s.strip if email.empty?
    email = "walmart+#{walmart_order['purchaseOrderId']}@noreply.walmart.cl" if email.empty?
    email
  end

  # Returns [first_name, last_name] parsed from the shipping address name.
  def self.buyer_name(walmart_order)
    address = (walmart_order['shippingInfo'] || {})['postalAddress'] || {}
    full    = address['name'].to_s.strip
    first, *rest = full.split(' ')
    [first.to_s, rest.join(' ')]
  end

  private

  def self.extract_shipping_price(walmart_order)
    total = 0.0
    Array(walmart_order.dig('orderLines', 'orderLine')).each do |line|
      Array(line.dig('charges', 'charge')).each do |c|
        total += c.dig('chargeAmount', 'amount').to_f if c['chargeType'] == 'SHIPPING'
      end
    end
    total
  end

  def self.build_address(address)
    [address['address1'], address['address2']]
      .compact.map(&:strip).reject(&:empty?).join(', ')
  end

  def self.region_code(region_name)
    REGION_CODES[region_name] || '12'
  end

  def self.line_to_product(line)
    qty    = line.dig('orderLineQuantity', 'amount').to_i
    sku    = line.dig('item', 'sku').to_s
    charges = Array(line.dig('charges', 'charge'))
    product_charge = charges.find { |c| c['chargeType'] == 'PRODUCT' } || charges.first
    unit_price = product_charge&.dig('chargeAmount', 'amount').to_f
    { 'id' => sku.to_i, 'qty' => qty, 'price' => unit_price }
  end

  def self.order_notes(walmart_order)
    ship_info = walmart_order['shippingInfo'] || {}
    [
      'Venta Walmart Marketplace',
      "Walmart Order ID : #{walmart_order['purchaseOrderId']}",
      "Customer Order ID: #{walmart_order['customerOrderId']}",
      "Fecha orden      : #{fmt_ts(walmart_order['orderDate'])}",
      "Entrega estimada : #{fmt_ts(ship_info['estimatedDeliveryDate'])}",
      "Método envío     : #{ship_info['methodCode']}"
    ].join("\n")
  end

  def self.fmt_ts(ms)
    return '' if ms.nil?
    Time.at(ms.to_i / 1000).strftime('%Y-%m-%d %H:%M')
  end
end
