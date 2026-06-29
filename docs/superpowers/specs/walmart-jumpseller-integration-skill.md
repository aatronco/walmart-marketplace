# Skill: Walmart Chile × Jumpseller Integration

**Last updated:** 2026-06-28  
**Status:** Live in production (6/7 test products published)

This skill captures everything learned integrating Jumpseller with Walmart Chile Marketplace, including API quirks, field formats from spec 4.46, known errors and fixes, and business context.

---

## Contacts at Walmart Chile

| Name | Email | Role |
|---|---|---|
| Kevin Gallardo Toro | Kevin.Gallardo0@walmart.com | PM Senior – API e Integradores |
| Beatriz Herrera | Beatriz.Herrera1@walmart.com | Business Developer Marketplace |
| George Abou Chanab | George.Abou.Chanab@walmart.com | API & Integradores analyst (technical) |
| APIs team inbox | apis_marketplace_cl@wal-mart.com | Always CC this on all technical emails |

---

## Portals & Documentation

- **Seller Center:** https://seller.walmart.com/home
- **Developer Portal / API credentials:** https://developer.walmart.com/login
- **Knowledge base (Chile):** https://marketplacelearn.walmart.com/cl
- **Global API reference (must use after July 31, 2026):** https://developer.walmart.com/global-marketplace/reference

---

## Environment URLs

| Env | Base URL |
|---|---|
| Production | `https://marketplace.walmartapis.com` |
| Sandbox | `https://sandbox.walmartapis.com` |

**Warning:** Sandbox token exchange works but Chile feed endpoints (`/v3/feeds`) return UNAUTHORIZED even with valid credentials. Test against production from the start.

**Deadline:** Local/Chile API versions deprecate **July 31, 2026**. All calls must use Global APIs with `WM_GLOBAL_VERSION: 3.1`.

---

## Authentication

### Step 1 — Token Exchange

```
POST /v3/token
Authorization: Basic Base64(clientId:clientSecret)
Content-Type: application/x-www-form-urlencoded
WM_MARKET: cl
WM_SVC.NAME: Walmart Marketplace
WM_QOS.CORRELATION_ID: <uuid>
WM_CONSUMER.CHANNEL.TYPE: Jumpseller

Body: grant_type=client_credentials
```

Response: `{ "access_token": "...", "token_type": "Bearer", "expires_in": 900 }`

Token TTL is **900 seconds (15 min)**. Refresh 60s before expiry.

### Step 2 — Data API Calls

**CRITICAL:** Do NOT use `Authorization: Bearer <token>`. Walmart Chile uses a custom header:

```
WM_SEC.ACCESS_TOKEN: <access_token>     ← replaces Authorization: Bearer
WM_MARKET: cl
WM_GLOBAL_VERSION: 3.1                 ← required for all Global API calls
WM_SVC.NAME: Walmart Marketplace
WM_QOS.CORRELATION_ID: <uuid>          ← fresh UUID per request
WM_CONSUMER.CHANNEL.TYPE: Jumpseller
Accept: application/json
Content-Type: application/json
```

Using `Authorization: Bearer` returns `UNAUTHORIZED.GMP_GATEWAY_API`. This error is misleading — it's not a token issue, it's the wrong header name.

---

## Product Publishing — Feed Flow

### Feed Submission

```
POST /v3/feeds?feedType=MP_ITEM_INTL
```

Feed payload structure (spec version 4.46):

```json
{
  "MPItemFeedHeader": {
    "sellingChannel": "marketplace",
    "processMode": "REPLACE",
    "subset": "EXTERNAL",
    "locale": "es",
    "version": "4.46",
    "mart": "WALMART_CHILE"
  },
  "MPItem": [ ...items... ]
}
```

Each item has two sections: `Orderable` (pricing, logistics, identifiers) and `Visible` (category-specific display attributes).

### Poll Feed Status

```
GET /v3/feeds/{feedId}?includeDetails=true
```

`feedStatus` values: `INPROGRESS` → `PROCESSED` or `ERROR`.
`itemIngestionStatus` per item: `SUCCESS` or `DATA_ERROR`.

---

## Orderable Section — Required Fields

```json
{
  "sku": "string",
  "productIdentifiers": { "productIdType": "GTIN", "productId": "14-digit-GTIN" },
  "productName": "string",
  "brand": "string",
  "manufacturer": "string",
  "price": 29990,                          // plain number (CLP), NOT {currency, amount}
  "pricePerUnit": { "pricePerUnitQuantity": 1, "pricePerUnitUom": "un" },
  "condition": "Nuevo",
  "countryOfOriginAssembly": ["CL - Chile"],  // full "XX - Country" format, NOT just "CL"
  "ShippingWeight": 0.5,
  "shippingDimensionsHeight": { "measure": 10.0, "unit": "cm" },
  "ShippingDimensionsWidth":  { "measure": 10.0, "unit": "cm" },
  "ShippingDimensionsDepth":  { "measure": 10.0, "unit": "cm" },
  "mainImageUrl": "https://...",
  "productSecondaryImageURL": ["https://..."],  // required, minItems: 1 — fall back to mainImageUrl
  "shortDescription": "string (max 500 chars)",
  "keyFeatures": ["string (max 80 chars)"],
  "sellerWarranty": "Garantía de fábrica",
  "sellerWarrantyCondition": "Nuevo",
  "sellerWarrantyPeriod": 12,
  "warrantyText": "Garantía de 12 meses",
  "multipackQuantity": 1,
  "ProductIdUpdate": "Sí"    // include when resubmitting with a different GTIN
}
```

Do **not** include `startDate` — the format is ambiguous between spec description ("dd-mm-aaaa") and JSON Schema type (`date`), and it's optional.

### GTIN / Product ID

Use real EAN/barcode when available. For products without barcodes, generate a structurally valid GTIN-14 using the GS1 check-digit formula:

```ruby
def self.fake_gtin(sku)
  base13 = sku.gsub(/\D/, '').rjust(13, '0')[-13, 13]
  total  = base13.chars.each_with_index.sum { |d, i| d.to_i * (i.even? ? 3 : 1) }
  check  = (10 - total % 10) % 10
  base13 + check.to_s
end
```

**Important:** Once a GTIN is registered in Walmart for a given SKU, you cannot change it without including `ProductIdUpdate: 'Sí'`. Even then, if the offer is already published, Walmart support may need to clear it. Save the GTIN used at first publish.

---

## Visible Section — Category-Specific Required Fields

The `Visible` section key is the Spanish Walmart category name. Each category has its own required fields — there is no generic `productDescription` sub-object.

### Food categories (`Alimentación y bebestibles`, `Bebidas alcohólicas`, etc.)

```json
{
  "Alimentación y bebestibles": {
    "shelfLife": { "measure": 180, "unit": "días" }
  }
}
```

`shelfLife` is **required** for food. Unit enum: `["días"]` only.

### Electronics / Audio (`Equipos de audio, sonido y grabación`)

```json
{
  "Equipos de audio, sonido y grabación": {
    "assembledProductHeight": { "measure": 10.0, "unit": "cm" },
    "assembledProductWidth":  { "measure": 10.0, "unit": "cm" },
    "assembledProductLength": { "measure": 10.0, "unit": "cm" },
    "assembledProductWeight": { "measure": 0.5,  "unit": "kg" },
    "color":    ["Negro"],
    "material": ["Plástico"],
    "modelNumber": "SKU-or-model-string",
    "hasIntegratedSpeakers": "No"    // enum: ["Sí", "No"]
  }
}
```

### Home & Kitchen (`Decoración de Hogar, Cocina y Otros`)

Same assembled dimensions as above, plus:
```json
{
  "isAssemblyRequired": "No"    // enum: ["Sí", "No"]
}
```
Note: no `hasIntegratedSpeakers` for this category.

---

## Google Product Taxonomy → Walmart Chile Category Mapping

Walmart Chile uses Spanish category names as keys in the `Visible` section. Jumpseller stores the Google Product Taxonomy category as `google_product_category_text` (in es-419 Spanish for CL stores, e.g. `"Alimentación, bebida y tabaco > Bebidas"`).

Mapping strategy: longest-prefix match on ` > `-split segments.

Key mappings:
| Google (ES) | Walmart Chile |
|---|---|
| Alimentación, bebida y tabaco | Alimentación y bebestibles |
| Alimentación, bebida y tabaco > Bebidas > Bebidas alcohólicas | Bebidas alcohólicas |
| Electrónica > Audio | Equipos de audio, sonido y grabación |
| Electrónica > Computadoras | Computadores |
| Hogar y jardín | Decoración de Hogar, Cocina y Otros |
| Salud y belleza | Belleza y salud |
| Ropa y accesorios | Vestuario |

Default fallback: `Decoración de Hogar, Cocina y Otros`

Full mapping is in `lib/product_mapper.rb` → `GOOGLE_TO_WALMART` constant.

---

## Common DATA_ERROR Causes and Fixes

| Error field | Cause | Fix |
|---|---|---|
| `productId` invalid check-digit | Fake GTIN not GS1-valid | Use GS1 weighted-sum formula (above) |
| `productId` already registered with different GTIN | Resubmitting with new GTIN | Add `ProductIdUpdate: 'Sí'` |
| `countryOfOriginAssembly` invalid unit | Used `"CL"` instead of `"CL - Chile"` | Full enum format: `"XX - Country Name"` |
| `shelfLife` required | Food category, field missing | Add to Visible section for food |
| `productDescription` not valid field | Old mapper put data in a generic sub-object | Visible uses category-specific fields directly |
| `productSecondaryImageURL` min 1 | No secondary images | Fall back to main image URL |
| `UNAUTHORIZED.GMP_GATEWAY_API` | Using `Authorization: Bearer` header | Use `WM_SEC.ACCESS_TOKEN` header instead |
| `WM_SVC.NAME set blank or null` | Header missing from token exchange call | Add `WM_SVC.NAME` and `WM_QOS.CORRELATION_ID` to ALL requests including token |

---

## Inventory Strategy (Supermarket Pattern)

Walmart Chile requires inventory kept at 0 for test/sandbox items to prevent appearing on site. For production:

- **Bulk consolidation:** 1–2x/day full sync (Jumpseller is source of truth)
- **Real-time deltas:** Jumpseller webhooks → `PUT /v3/inventory?sku={sku}` on stock changes
- **Payload:** `{ sku, quantity: { amount: N, unit: "EACH" } }`

This mirrors how supermarket POS systems work: periodic full reconciliation + real-time delta pushes.

---

## Order Flow

1. Poll `GET /v3/orders?status=Created` (or receive via webhook)
2. Acknowledge: `POST /v3/orders/{purchaseOrderId}/acknowledge`
3. Create in Jumpseller: `POST /orders.json`
4. Ship: `POST /v3/orders/{purchaseOrderId}/shipping`

---

## Jumpseller API Auth

Use HTTP Basic Auth header — **not** query params (deprecated, returns 403):

```ruby
req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{login}:#{authtoken}")}"
```

`login` = store login key, `authtoken` = API token (both from Jumpseller admin → API).

In `.env`, use `Dotenv.overload` (not `Dotenv.load`) to ensure `.env` values override any stale shell environment variables.

---

## Architecture Vision

Single Jumpseller XML feed → multiple marketplace adapters:
- Walmart Chile (this integration)
- Cencosud
- Ripley

Pattern: Jumpseller as source of truth → feed → adapter per marketplace → category mapping + field transformation → feed submission + polling.

---

## Files in This Repo

| File | Purpose |
|---|---|
| `lib/walmart_client.rb` | API client with token caching, correct headers |
| `lib/jumpseller_client.rb` | Jumpseller API client with Basic Auth |
| `lib/product_mapper.rb` | Jumpseller product → Walmart MP_ITEM_INTL feed |
| `lib/order_mapper.rb` | Walmart order → Jumpseller order |
| `lib/webhook_receiver.rb` | Sinatra app for Jumpseller webhooks (HMAC validation) |
| `scripts/test_publish_one.rb` | Smoke test: fetch products → publish → poll |
| `/tmp/walmart_specs/` | Extracted spec JSONs from `Latest_specs.zip` |
| `Categorias_WalmartChile.xlsx` | Official Walmart Chile category list |
| `Integrations_info_Chile.docx` | Walmart integration guide (EN) |
