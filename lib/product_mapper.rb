# lib/product_mapper.rb

class ProductMapper
  MIN_PRICE_CLP    = 1400
  DEFAULT_CATEGORY = ENV.fetch('WALMART_DEFAULT_CATEGORY', 'Decoración de Hogar, Cocina y Otros')

  def self.to_walmart(product)
    sku   = product['id'].to_s
    price = [product['price'].to_f.round, MIN_PRICE_CLP].max

    {
      'Orderable' => {
        'sku'                => sku,
        'productIdentifiers' => {
          'productIdType' => 'GTIN',
          'productId'     => fake_gtin(sku)
        },
        'productName'              => "TEST - #{product['name']}",
        'brand'                    => product['brand'] || 'Sin marca',
        'price'                    => { 'currency' => 'CLP', 'amount' => price },
        'ShippingWeight'           => product['weight']&.to_f || 0.5,
        'shippingDimensionsHeight' => 10,
        'ShippingDimensionsWidth'  => 10,
        'ShippingDimensionsDepth'  => 10,
        'multipackQuantity'        => 1,
        'startDate'                => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')
      },
      'Visible' => {
        DEFAULT_CATEGORY => {
          'productDescription' => {
            'shortDescription' => (product['description'] || product['name'])[0, 500],
            'mainImageUrl'     => product.dig('images', 0, 'url') || ''
          }
        }
      }
    }
  end

  def self.feed_payload(products)
    {
      'MPItemFeedHeader' => {
        'sellingChannel' => 'marketplace',
        'processMode'    => 'REPLACE',
        'subset'         => 'EXTERNAL',
        'locale'         => 'es',
        'version'        => '4.46',
        'mart'           => 'WALMART_CL'
      },
      'MPItem' => products.map { |p| to_walmart(p) }
    }
  end

  def self.fake_gtin(sku)
    numeric = sku.gsub(/\D/, '').rjust(14, '0')
    numeric[-14, 14] || numeric.rjust(14, '0')
  end
end
