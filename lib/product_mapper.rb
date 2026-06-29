# lib/product_mapper.rb

class ProductMapper
  MIN_PRICE_CLP    = 1400
  DEFAULT_CATEGORY = 'Decoración de Hogar, Cocina y Otros'.freeze

  # Longest-prefix match: Google Product Taxonomy → Walmart Chile category (Spanish name used as Visible key)
  # Keys ordered longest→shortest so first match wins on prefix scan
  GOOGLE_TO_WALMART = {
    # Food & Beverages
    'Food, Beverages & Tobacco > Beverages > Alcoholic Beverages' => 'Bebidas alcohólicas',
    'Food, Beverages & Tobacco'                                    => 'Alimentación y bebestibles',

    # Electronics
    'Electronics > Communications > Telephony'                     => 'Telefonía',
    'Electronics > Computers'                                      => 'Computadores',
    'Electronics > Video > Televisions'                            => 'Televisores y monitores',
    'Electronics > Video > Projectors'                             => 'Proyectores de vídeo',
    'Electronics > Video'                                          => 'Televisores y monitores',
    'Electronics > Audio'                                          => 'Equipos de audio, sonido y grabación',
    'Electronics > Print, Copy, Scan & Fax'                       => 'Impresoras, scanners y fax (no toner)',
    'Electronics > Video Games'                                    => 'Video juegos',
    'Electronics > Software'                                       => 'Software y aplicaciones',
    'Electronics > Electronics Accessories'                        => 'Accesorios Electrónicos',
    'Electronics > Networking'                                     => 'Accesorios Electrónicos',
    'Electronics'                                                  => 'Otros Electrónica',

    # Cameras
    'Cameras & Optics > Cameras'                                   => 'Cámaras y lentes',
    'Cameras & Optics > Camera & Optics Accessories'               => 'Accesorios fotografía',
    'Cameras & Optics > Optics'                                    => 'Telescopios y otros',
    'Cameras & Optics'                                             => 'Cámaras y lentes',

    # Apparel
    'Apparel & Accessories > Shoes'                                => 'Calzado',
    'Apparel & Accessories > Jewelry'                              => 'Joyería',
    'Apparel & Accessories > Watches'                              => 'Relojes',
    'Apparel & Accessories > Handbags, Wallets & Cases'            => 'Bolsos y mochilas',
    'Apparel & Accessories > Costumes & Accessories'               => 'Disfraces',
    'Apparel & Accessories'                                        => 'Vestuario',

    # Home & Garden
    'Home & Garden > Bedding'                                      => 'Ropa de cama',
    'Home & Garden > Lawn & Garden'                                => 'Jardín y terraza',
    'Home & Garden > Household Supplies'                           => 'Limpieza y productos químicos domésticos e industriales',
    'Home & Garden > Storage & Organization'                       => 'Almacenamiento y bodega',
    'Home & Garden > Barbecue & Grilling'                          => 'Parrillas y cocina al aire libre',
    'Home & Garden > Heating, Ventilation & Air Conditioning'      => 'Plomería y HVAC',
    'Home & Garden > Outdoor Power Equipment'                      => 'Herramientas',
    'Home & Garden > Tools'                                        => 'Herramientas',
    'Home & Garden > Fire Safety'                                  => 'Seguridad y emergencia',
    'Home & Garden > Security'                                     => 'Seguridad y emergencia',
    'Home & Garden'                                                => 'Decoración de Hogar, Cocina y Otros',

    # Hardware & Tools
    'Hardware > Building Materials'                                => 'Artículos para la construcción',
    'Hardware > Plumbing'                                          => 'Plomería y HVAC',
    'Hardware > Electrical'                                        => 'Electricidad',
    'Hardware'                                                     => 'Ferretería',

    # Health & Beauty
    'Health & Beauty > Personal Care'                              => 'Cuidado personal',
    'Health & Beauty > Pharmacy'                                   => 'Farmacia y suplementos',
    'Health & Beauty > Medical Supplies & Equipment'               => 'Primeros auxilios',
    'Health & Beauty > Fitness & Nutrition'                        => 'Farmacia y suplementos',
    'Health & Beauty'                                              => 'Belleza y salud',

    # Baby
    'Baby & Toddler > Baby Transport'                              => 'Transporte bebé',
    'Baby & Toddler > Baby Clothing'                               => 'Vestuario bebé',
    'Baby & Toddler > Diapering'                                   => 'Cuidado, pañales para bebés y otros',
    'Baby & Toddler > Baby Food'                                   => 'Alimentación bebé',
    'Baby & Toddler > Nursing & Feeding'                           => 'Alimentación bebé',
    'Baby & Toddler > Baby Furniture'                              => 'Muebles bebés',
    'Baby & Toddler'                                               => 'Juguetes y recreación bebé',

    # Pets
    'Animals & Pet Supplies > Pet Supplies > Pet Food'             => 'Comida para mascotas',
    'Animals & Pet Supplies'                                       => 'Accesorios para mascotas',

    # Sports
    'Sporting Goods > Cycling'                                     => 'Ciclismo',
    'Sporting Goods > Outdoor Recreation > Boating & Water Sports' => 'Equipos náuticos',
    'Sporting Goods'                                               => 'Deportes y Otros Recreación',

    # Toys & Games
    'Toys & Games > Video Games'                                   => 'Video juegos',
    'Toys & Games'                                                 => 'Juguetes',

    # Media
    'Media > DVDs & Videos'                                        => 'Películas',
    'Media > Music & Sound Recordings'                             => 'Música',
    'Media'                                                        => 'Libros y revistas',

    # Misc
    'Arts & Entertainment > Music'                                 => 'Música',
    'Arts & Entertainment > Hobbies & Creative Arts'               => 'Arte y manualidades',
    'Arts & Entertainment'                                         => 'Libros y revistas',
    'Musical Instruments'                                          => 'Instrumentos musicales',
    'Office Supplies'                                              => 'Oficina',
    'Luggage & Bags'                                               => 'Maletas y accesorios',
    'Furniture > Baby & Toddler Furniture'                         => 'Muebles bebés',
    'Furniture'                                                    => 'Muebles',
    'Vehicles & Parts > Vehicle Parts & Accessories'               => 'Partes y accesorios automóvil',
    'Vehicles & Parts'                                             => 'Automóvil otros',

    # ── Spanish Google Category variants (Jumpseller CL uses es-419 labels) ──
    'Alimentación, bebida y tabaco > Bebidas > Bebidas alcohólicas' => 'Bebidas alcohólicas',
    'Alimentación, bebida y tabaco'                                  => 'Alimentación y bebestibles',

    'Electrónica > Comunicaciones > Telefonía'                       => 'Telefonía',
    'Electrónica > Computadoras'                                     => 'Computadores',
    'Electrónica > Video > Televisores'                              => 'Televisores y monitores',
    'Electrónica > Video > Proyectores'                              => 'Proyectores de vídeo',
    'Electrónica > Video'                                            => 'Televisores y monitores',
    'Electrónica > Audio'                                            => 'Equipos de audio, sonido y grabación',
    'Electrónica > Impresión, copia, escaneo y fax'                  => 'Impresoras, scanners y fax (no toner)',
    'Electrónica > Videojuegos'                                      => 'Video juegos',
    'Electrónica > Software'                                         => 'Software y aplicaciones',
    'Electrónica > Accesorios electrónicos'                          => 'Accesorios Electrónicos',
    'Electrónica > Redes'                                            => 'Accesorios Electrónicos',
    'Electrónica'                                                    => 'Otros Electrónica',

    'Cámaras y óptica > Cámaras'                                     => 'Cámaras y lentes',
    'Cámaras y óptica > Accesorios de cámara y óptica'               => 'Accesorios fotografía',
    'Cámaras y óptica > Óptica'                                      => 'Telescopios y otros',
    'Cámaras y óptica'                                               => 'Cámaras y lentes',

    'Ropa y accesorios > Calzado'                                    => 'Calzado',
    'Ropa y accesorios > Joyería'                                    => 'Joyería',
    'Ropa y accesorios > Relojes'                                    => 'Relojes',
    'Ropa y accesorios > Bolsos, billeteras y estuches'              => 'Bolsos y mochilas',
    'Ropa y accesorios > Disfraces y accesorios'                     => 'Disfraces',
    'Ropa y accesorios'                                              => 'Vestuario',

    'Hogar y jardín > Ropa de cama'                                  => 'Ropa de cama',
    'Hogar y jardín > Jardín y terraza'                              => 'Jardín y terraza',
    'Hogar y jardín > Artículos de limpieza del hogar'               => 'Limpieza y productos químicos domésticos e industriales',
    'Hogar y jardín > Almacenamiento y organización'                 => 'Almacenamiento y bodega',
    'Hogar y jardín > Parrillas y cocina al aire libre'              => 'Parrillas y cocina al aire libre',
    'Hogar y jardín > Calefacción, ventilación y aire acondicionado' => 'Plomería y HVAC',
    'Hogar y jardín > Seguridad contra incendios'                    => 'Seguridad y emergencia',
    'Hogar y jardín > Seguridad'                                     => 'Seguridad y emergencia',
    'Hogar y jardín > Herramientas'                                  => 'Herramientas',
    'Hogar y jardín'                                                 => 'Decoración de Hogar, Cocina y Otros',

    'Ferretería > Materiales de construcción'                        => 'Artículos para la construcción',
    'Ferretería > Plomería'                                          => 'Plomería y HVAC',
    'Ferretería > Electricidad'                                      => 'Electricidad',
    'Ferretería'                                                     => 'Ferretería',

    'Salud y belleza > Cuidado personal'                             => 'Cuidado personal',
    'Salud y belleza > Farmacia'                                     => 'Farmacia y suplementos',
    'Salud y belleza > Equipos e insumos médicos'                    => 'Primeros auxilios',
    'Salud y belleza > Fitness y nutrición'                          => 'Farmacia y suplementos',
    'Salud y belleza'                                                => 'Belleza y salud',

    'Bebés y niños pequeños > Transporte para bebés'                 => 'Transporte bebé',
    'Bebés y niños pequeños > Ropa de bebé'                          => 'Vestuario bebé',
    'Bebés y niños pequeños > Pañales'                               => 'Cuidado, pañales para bebés y otros',
    'Bebés y niños pequeños > Alimentación de bebés'                 => 'Alimentación bebé',
    'Bebés y niños pequeños > Muebles para bebés'                    => 'Muebles bebés',
    'Bebés y niños pequeños'                                         => 'Juguetes y recreación bebé',

    'Animales y mascotas > Suministros para mascotas > Comida'       => 'Comida para mascotas',
    'Animales y mascotas'                                            => 'Accesorios para mascotas',

    'Artículos deportivos > Ciclismo'                                => 'Ciclismo',
    'Artículos deportivos'                                           => 'Deportes y Otros Recreación',

    'Juguetes y juegos > Videojuegos'                                => 'Video juegos',
    'Juguetes y juegos'                                              => 'Juguetes',

    'Medios de comunicación > DVD y videos'                          => 'Películas',
    'Medios de comunicación > Música y grabaciones de sonido'        => 'Música',
    'Medios de comunicación'                                         => 'Libros y revistas',

    'Arte y entretenimiento > Música'                                => 'Música',
    'Arte y entretenimiento > Manualidades y aficiones'              => 'Arte y manualidades',
    'Arte y entretenimiento'                                         => 'Libros y revistas',

    'Instrumentos musicales'                                         => 'Instrumentos musicales',
    'Artículos de oficina'                                           => 'Oficina',
    'Equipaje y bolsas'                                              => 'Maletas y accesorios',
    'Muebles > Muebles para bebés y niños pequeños'                  => 'Muebles bebés',
    'Muebles'                                                        => 'Muebles',
    'Vehículos y repuestos > Repuestos y accesorios para vehículos'  => 'Partes y accesorios automóvil',
    'Vehículos y repuestos'                                          => 'Automóvil otros',
  }.freeze

  def self.walmart_category(product)
    google_text = product['google_product_category_text'].to_s.strip
    return DEFAULT_CATEGORY if google_text.empty?

    parts = google_text.split(' > ')
    parts.length.downto(1) do |n|
      prefix = parts.first(n).join(' > ')
      return GOOGLE_TO_WALMART[prefix] if GOOGLE_TO_WALMART.key?(prefix)
    end
    DEFAULT_CATEGORY
  end

  def self.to_walmart(product)
    sku         = product['id'].to_s
    price       = [product['price'].to_f.round, MIN_PRICE_CLP].max
    brand       = (product['brand'].to_s.strip.empty? ? nil : product['brand']) || 'Sin marca'
    description = strip_html(product['description'] || product['name'] || '')[0, 500]
    image_url   = product.dig('images', 0, 'url') || ''
    extra_imgs  = (product['images'] || [])[1..].map { |i| i['url'] }.compact
    category    = walmart_category(product)

    # Use real EAN/barcode if available, otherwise derive a fake GTIN from SKU
    gtin_type = product['barcode'].to_s.strip.empty? ? 'GTIN' : 'EAN'
    gtin_val  = product['barcode'].to_s.strip.empty? ? fake_gtin(sku) : product['barcode'].to_s.strip

    # Physical dimensions from Jumpseller (cm), defaulting to 10cm cube
    height = product['height']&.to_f&.positive? ? product['height'].to_f : 10.0
    width  = product['width']&.to_f&.positive?  ? product['width'].to_f  : 10.0
    depth  = product['length']&.to_f&.positive? ? product['length'].to_f : 10.0

    # productSecondaryImageURL is required (minItems: 1) — fall back to main image
    secondary_imgs = extra_imgs.empty? ? [image_url] : extra_imgs

    {
      'Orderable' => {
        'sku'                      => sku,
        'productIdentifiers'       => { 'productIdType' => gtin_type, 'productId' => gtin_val },
        'productName'              => "TEST - #{product['name']}",
        'brand'                    => brand,
        'manufacturer'             => brand,
        'price'                    => price,
        'pricePerUnit'             => { 'pricePerUnitQuantity' => 1, 'pricePerUnitUom' => 'un' },
        'condition'                => 'Nuevo',
        'countryOfOriginAssembly'  => ['CL - Chile'],
        'ShippingWeight'           => product['weight']&.to_f&.positive? ? product['weight'].to_f : 0.5,
        'shippingDimensionsHeight' => { 'measure' => height, 'unit' => 'cm' },
        'ShippingDimensionsWidth'  => { 'measure' => width,  'unit' => 'cm' },
        'ShippingDimensionsDepth'  => { 'measure' => depth,  'unit' => 'cm' },
        'mainImageUrl'             => image_url,
        'productSecondaryImageURL' => secondary_imgs,
        'shortDescription'         => description,
        'keyFeatures'              => [description[0, 80]].reject(&:empty?),
        'sellerWarranty'           => 'Garantía de fábrica',
        'sellerWarrantyCondition'  => 'Nuevo',
        'sellerWarrantyPeriod'     => 12,
        'warrantyText'             => 'Garantía de 12 meses',
        'multipackQuantity'        => 1,
        'ProductIdUpdate'          => 'Sí'
      },
      'Visible' => {
        category => visible_fields(category, product)
      }
    }
  end

  FOOD_CATEGORIES = [
    'Alimentación y bebestibles',
    'Bebidas alcohólicas',
    'Comida para mascotas',
    'Alimentación bebé'
  ].freeze

  # Categories that require assembled dimensions + color + material in Visible
  DIMENSION_CATEGORIES = [
    'Decoración de Hogar, Cocina y Otros',
    'Equipos de audio, sonido y grabación',
    'Televisores y monitores',
    'Computadores',
    'Accesorios Electrónicos',
    'Muebles',
    'Ropa de cama'
  ].freeze

  def self.visible_fields(category, product = {})
    height = product['height']&.to_f&.positive? ? product['height'].to_f : 10.0
    width  = product['width']&.to_f&.positive?  ? product['width'].to_f  : 10.0
    depth  = product['length']&.to_f&.positive? ? product['length'].to_f : 10.0
    weight = product['weight']&.to_f&.positive? ? product['weight'].to_f : 0.5

    if FOOD_CATEGORIES.any? { |fc| category.include?(fc) }
      { 'shelfLife' => { 'measure' => 180, 'unit' => 'días' } }
    elsif DIMENSION_CATEGORIES.any? { |dc| category.include?(dc) }
      base = {
        'assembledProductHeight' => { 'measure' => height, 'unit' => 'cm' },
        'assembledProductWidth'  => { 'measure' => width,  'unit' => 'cm' },
        'assembledProductLength' => { 'measure' => depth,  'unit' => 'cm' },
        'assembledProductWeight' => { 'measure' => weight, 'unit' => 'kg' },
        'color'                  => ['Negro'],
        'material'               => ['Plástico'],
        'modelNumber'            => product['id'].to_s
      }
      base['hasIntegratedSpeakers'] = 'No' if category.include?('audio')
      base['isAssemblyRequired']    = 'No' unless category.include?('audio')
      base
    else
      {}
    end
  end

  def self.feed_payload(products)
    {
      'MPItemFeedHeader' => {
        'sellingChannel' => 'marketplace',
        'processMode'    => 'REPLACE',
        'subset'         => 'EXTERNAL',
        'locale'         => 'es',
        'version'        => '4.46',
        'mart'           => 'WALMART_CHILE'
      },
      'MPItem' => products.map { |p| to_walmart(p) }
    }
  end

  # Stock safety buffer: never expose real inventory to Walmart.
  # Requires ≥ STOCK_BUFFER units in Jumpseller before showing any stock.
  # Exposes floor(qty / STOCK_DIVISOR) — so 10 units → 2, 6 units → 1, ≤5 → 0.
  STOCK_BUFFER  = 5
  STOCK_DIVISOR = 5

  def self.walmart_stock(jumpseller_qty)
    qty = jumpseller_qty.to_i
    return 0 if qty <= STOCK_BUFFER
    qty / STOCK_DIVISOR
  end

  def self.fake_gtin(sku)
    # Prefix 02 = GS1 internal-use range, safe for products without a registered barcode.
    # Guaranteed not to collide with any real product in Walmart's global catalog.
    numeric = sku.gsub(/\D/, '').rjust(11, '0')[-11, 11]
    base13  = "02#{numeric}"
    total   = base13.chars.each_with_index.sum { |d, i| d.to_i * (i.even? ? 3 : 1) }
    check   = (10 - total % 10) % 10
    base13 + check.to_s
  end

  def self.strip_html(str)
    str.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  end
end
