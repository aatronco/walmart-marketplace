# spec/product_mapper_spec.rb
require 'spec_helper'
require_relative '../lib/product_mapper'

RSpec.describe ProductMapper do
  let(:jumpseller_product) do
    {
      'id'          => 42,
      'name'        => 'Camiseta Roja',
      'sku'         => 'CAM-001',
      'price'       => 9990.0,
      'stock'       => 15,
      'brand'       => 'MiMarca',
      'description' => 'Una camiseta roja de algodón',
      'weight'      => 0.3,
      'images'      => [{ 'url' => 'https://example.com/img.jpg' }]
    }
  end

  describe '.to_walmart' do
    subject(:result) { ProductMapper.to_walmart(jumpseller_product) }

    it 'prefixes product name with TEST -' do
      expect(result['Orderable']['productName']).to start_with('TEST - ')
    end

    it 'uses Jumpseller product id as SKU' do
      expect(result['Orderable']['sku']).to eq('42')
    end

    it 'sets price in CLP' do
      expect(result['Orderable']['price']['currency']).to eq('CLP')
      expect(result['Orderable']['price']['amount']).to eq(9990)
    end

    it 'enforces minimum price of 1400 CLP' do
      cheap_product = jumpseller_product.merge('price' => 500)
      result = ProductMapper.to_walmart(cheap_product)
      expect(result['Orderable']['price']['amount']).to eq(1400)
    end

    it 'generates a 14-digit fake GTIN from product id' do
      gtin = result['Orderable']['productIdentifiers']['productId']
      expect(gtin.length).to eq(14)
    end

    it 'includes main image URL in Visible section' do
      category = ENV.fetch('WALMART_DEFAULT_CATEGORY', 'Decoración de Hogar, Cocina y Otros')
      expect(result['Visible'][category]['productDescription']['mainImageUrl'])
        .to eq('https://example.com/img.jpg')
    end
  end

  describe '.feed_payload' do
    it 'wraps products in MPItemFeedHeader and MPItem' do
      payload = ProductMapper.feed_payload([jumpseller_product])
      expect(payload['MPItemFeedHeader']['version']).to eq('4.46')
      expect(payload['MPItemFeedHeader']['mart']).to eq('WALMART_CL')
      expect(payload['MPItem'].length).to eq(1)
    end
  end
end
