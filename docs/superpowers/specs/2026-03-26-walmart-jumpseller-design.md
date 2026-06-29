# Walmart Chile ↔ Jumpseller Integration — Design Spec

**Date:** 2026-03-26
**Status:** Approved

---

## Objetivo

Integración bidireccional entre Jumpseller (fuente de verdad) y Walmart Marketplace Chile (sandbox → producción).

- Jumpseller → Walmart: publicación de productos + sincronización de inventario
- Walmart → Jumpseller: creación de órdenes

---

## Stack

| Componente | Tecnología |
|---|---|
| Lenguaje | Ruby |
| Tareas programadas | Rake tasks |
| Webhook receiver | Sinatra |
| Deploy webhook server | Render.com (free tier) |
| Cron diario | GitHub Actions |
| Dev local webhooks | ngrok |
| Estado mínimo | Archivo `.last_order_id` |
| Credenciales | Variables de entorno |

---

## Estructura del proyecto

```
jumpseller-walmart-sync/
├── lib/
│   ├── jumpseller_client.rb   # wrapper API Jumpseller
│   ├── walmart_client.rb      # wrapper API Walmart Chile (OAuth2, WM_MARKET: cl)
│   ├── product_mapper.rb      # Jumpseller product → Walmart spec 4.46
│   └── order_mapper.rb        # Walmart order → Jumpseller order
├── app.rb                     # Sinatra: recibe webhooks de Jumpseller
├── Rakefile                   # tareas: publish_products, sync_inventory, sync_orders, status
├── .last_order_id             # último purchaseOrderId de Walmart procesado
├── Gemfile
├── .env.example
└── .github/
    └── workflows/
        └── daily_sync.yml     # cron 06:00 UTC (03:00 Chile)
```

---

## Variables de entorno

```
JUMPSELLER_LOGIN               # login de la cuenta Jumpseller
JUMPSELLER_AUTH_TOKEN          # auth token de la API Jumpseller
WALMART_CLIENT_ID              # Client ID del Developer Portal Walmart
WALMART_CLIENT_SECRET          # Client Secret del Developer Portal Walmart
WALMART_ENV=sandbox            # "sandbox" o "production"
JUMPSELLER_WEBHOOK_SECRET      # secret para validar firma de webhooks
```

---

## Flujos

### 1. Publicación de productos (Jumpseller → Walmart)

**Trigger:** `rake publish_products` (manual, una vez o cuando hay productos nuevos)

**Pasos:**
1. `GET /products` Jumpseller (paginado, todos los productos activos)
2. `product_mapper.rb` transforma cada producto al spec 4.46:
   - `sku` = ID del producto en Jumpseller
   - GTIN = `"TEST" + sku` (evita GTINs reales)
   - Precio en CLP, mínimo forzado a 1400
   - Inventario forzado a 0 (requisito sandbox Walmart)
   - Nombre con prefijo `"TEST - "` (evita compras accidentales)
   - Todos los atributos en español
   - Header `WM_MARKET: cl` en todos los requests
3. `POST /feeds` a Walmart con `FeedType: MP_ITEM_INTL` (spec 4.46)
4. Polling al feed hasta confirmación de procesamiento

**Idempotente:** sí. Si el SKU ya existe, Walmart actualiza en vez de duplicar.

---

### 2. Sincronización de inventario tiempo real (webhook)

**Trigger:** Jumpseller detecta cambio de stock → POST a Sinatra

**Pasos:**
1. Sinatra recibe `POST /webhook/inventory`
2. Valida firma HMAC del webhook con `JUMPSELLER_WEBHOOK_SECRET` → 401 si inválida
3. `walmart_client.rb` actualiza inventario via Walmart Inventory API
4. Responde 200

---

### 3. Consolidación de inventario diaria (fallback)

**Trigger:** GitHub Actions cron `0 6 * * *` → `rake sync_inventory`

**Pasos:**
1. `GET /products` Jumpseller (todos los productos con su stock actual)
2. Para cada producto, actualiza inventario en Walmart
3. Loggea diferencias encontradas

---

### 4. Órdenes Walmart → Jumpseller

**Trigger:** GitHub Actions cron `0 6 * * *` → `rake sync_orders`

**Pasos:**
1. Lee último `purchaseOrderId` desde `.last_order_id` (si no existe, toma últimas 24h)
2. `GET /orders` Walmart filtrando status `Created` desde el último ID
3. `order_mapper.rb` transforma cada orden:
   - `payment_method: "walmart"`
   - `status: paid`
   - Productos y cantidades de la orden Walmart
4. `POST /orders` a Jumpseller
5. Acknowledge de la orden en Walmart
6. Guarda último `purchaseOrderId` en `.last_order_id`

---

## Manejo de errores

| Situación | Comportamiento |
|---|---|
| Token Walmart expirado | `walmart_client.rb` renueva automáticamente (expira cada 15 min) |
| Error de API transitorio | 3 reintentos con backoff exponencial: 1s, 2s, 4s |
| Inventory update falla post-publicación | Reintento hasta 10 minutos después (delay conocido de Walmart Chile) |
| Webhook con firma inválida | Respuesta 401, no se procesa |
| `.last_order_id` no existe | Toma órdenes de las últimas 24h |
| Orden ya procesada | No se duplica (`.last_order_id` actúa como cursor) |

---

## Logging

- Salida a stdout (capturado por Render y GitHub Actions)
- Formato: `[2026-03-26 03:00:01] [sync_inventory] SKU 123 → updated 5 units`
- Errores incluyen el cuerpo completo de respuesta de la API

---

## Rake tasks

| Task | Descripción |
|---|---|
| `rake publish_products` | Publica todos los productos Jumpseller en Walmart |
| `rake sync_inventory` | Reconcilia inventario completo (Jumpseller → Walmart) |
| `rake sync_orders` | Procesa órdenes nuevas Walmart → Jumpseller |
| `rake status` | Muestra estado de últimos feeds y último order procesado |

---

## Deploy

### Render.com (webhook server)
- Web service gratuito con `rackup` (Rack/Sinatra)
- Variables de entorno en dashboard de Render
- URL pública se registra en Jumpseller como webhook endpoint
- Se duerme tras 15 min de inactividad — primer webhook del día puede tardar ~30s

### GitHub Actions (cron diario)
```yaml
schedule: "0 6 * * *"   # 03:00 hora Chile
steps:
  - rake sync_inventory
  - rake sync_orders
```
- Secrets de GitHub almacenan las variables de entorno
- Logs visibles en tab Actions del repositorio

### Desarrollo local
```bash
ngrok http 4567          # expone Sinatra para recibir webhooks de Jumpseller
rake publish_products    # prueba inicial
```

---

## Consideraciones especiales Walmart Chile

- Header obligatorio en todos los requests: `WM_MARKET: cl`
- Header recomendado: `WM_CONSUMER.CHANNEL.TYPE: jumpseller` (identifica la integración)
- API completamente diferente a Walmart US/MX/CA
- Spec de items: versión 4.46 (`MP_ITEM_INTL`)
- Precios mínimos: 1400 CLP
- Inventario siempre en 0 durante pruebas en sandbox
- Atributos en español (nombres, descripciones, colores, etc.)
- No usar GTINs reales en sandbox

---

## Asunciones

- Jumpseller permite configurar webhooks para cambios de stock/inventario en el producto
- El formato del webhook de Jumpseller incluye SKU y cantidad disponible
- Las órdenes de Walmart Chile se obtienen via polling (no hay webhooks de órdenes en Walmart Chile)

---

## Fuera de scope (MVP)

- Sincronización de precios (se puede agregar como extensión de `sync_inventory`)
- Manejo de variantes de productos
- Labels de envío (solo aplica a CBT sellers)
- Cancelación de órdenes
- Base de datos (se agrega si el volumen lo requiere)
