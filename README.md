# Integración Jumpseller × Walmart Chile

Sincroniza productos, inventario y órdenes entre una tienda Jumpseller y Walmart Chile Marketplace.

---

## Qué hace

| Función | Descripción |
|---------|-------------|
| **Publicación de productos** | Envía el catálogo de Jumpseller a Walmart en formato GTIN |
| **Sincronización de inventario** | Actualiza el stock en Walmart cada vez que cambia en Jumpseller |
| **Sincronización de órdenes** | Detecta ventas nuevas en Walmart y las crea automáticamente en Jumpseller como órdenes "Pagadas" |
| **Dashboard web** | Panel de control con estado del inventario, logs en tiempo real y botón de sincronización manual |

---

## Requisitos

- Ruby 3.x
- Bundler (`gem install bundler`)
- Cuenta activa en Jumpseller con acceso a API
- Cuenta de vendedor en Walmart Chile Marketplace con API Keys

---

## Instalación

### 1. Clonar el repositorio

```bash
git clone https://github.com/aatronco/walmart-marketplace.git
cd walmart-marketplace
bundle install
```

### 2. Configurar credenciales

Copiar el archivo de ejemplo y completar con las credenciales reales:

```bash
cp .env.example .env
```

Editar `.env`:

```env
# Credenciales Jumpseller (Configuración → API)
JUMPSELLER_LOGIN=tu_login
JUMPSELLER_AUTH_TOKEN=tu_auth_token

# Secret para el webhook (generar con el comando de abajo)
JUMPSELLER_WEBHOOK_SECRET=...

# Contraseña del dashboard web
DASHBOARD_PASSWORD=una_contraseña_segura

# Credenciales Walmart Chile (Seller Center → Configuración → API Keys)
WALMART_CLIENT_ID=tu_client_id
WALMART_CLIENT_SECRET=tu_client_secret
WALMART_ENV=production
```

Para generar el `JUMPSELLER_WEBHOOK_SECRET`:
```bash
ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"
```

> ⚠️ El archivo `.env` nunca debe subirse a Git. Ya está incluido en `.gitignore`.

---

## Uso

### Dashboard web (recomendado)

Inicia el servidor:

```bash
bundle exec rackup config.ru -p 4567
```

Abre `http://localhost:4567` en el navegador. Pedirá usuario y contraseña — el usuario puede ser cualquier cosa, la contraseña es la del `DASHBOARD_PASSWORD`.

Desde el dashboard se puede:
- Ver el inventario actual (Jumpseller vs Walmart, con margen de seguridad)
- Hacer clic en **Sincronizar** para importar órdenes nuevas de Walmart y actualizar el inventario
- Ver el log de actividad en tiempo real

### Scripts por línea de comandos

**Publicar productos a Walmart** (primera vez o cuando se agregan productos nuevos):
```bash
bundle exec rake publish_products
```

**Sincronizar órdenes manualmente:**
```bash
ruby scripts/sync_orders.rb
```

**Sincronizar inventario manualmente:**
```bash
bundle exec rake sync_inventory
```

---

## Cómo funciona la sincronización de órdenes

1. Consulta Walmart por órdenes de los últimos 7 días en estado `Created`
2. Filtra las que ya fueron procesadas (guardadas en `data/processed_orders.json`)
3. Por cada orden nueva:
   - Busca o crea el cliente en Jumpseller por email
   - Crea la orden en Jumpseller con estado `Paid` y método de pago `Walmart`
   - Marca la orden como `Acknowledged` en Walmart
   - Guarda el ID en `processed_orders.json` para evitar duplicados
4. Sincroniza el inventario actualizado hacia Walmart

Las órdenes creadas en Jumpseller incluyen en el campo "Notas para la empresa de envío":
```
Venta Walmart Marketplace
Walmart Order ID : P111546914
Customer Order ID: 7462668002125
Fecha orden      : 2026-06-30 23:28
Entrega estimada : 2026-07-04 06:00
Método envío     : STANDARD
```

---

## Inventario y margen de seguridad

Para evitar sobreventa, el stock que se envía a Walmart se calcula así:

| Stock en Jumpseller | Stock enviado a Walmart |
|---------------------|------------------------|
| 0–5 unidades | 0 |
| 6+ unidades | `floor(stock / 5)` |

Ejemplo: 25 unidades en Jumpseller → 5 unidades en Walmart.

---

## Deploy en producción (Render.com)

El repositorio incluye `render.yaml` con la configuración lista. Para desplegar:

1. Conectar el repositorio en [render.com](https://render.com)
2. Configurar las variables de entorno en el panel de Render (las mismas del `.env`)
3. El deploy es automático con cada push a `main`

Para la sincronización automática de órdenes, configurar un cron job en Render o un servicio externo que llame `POST /sync` cada 15 minutos:

```bash
curl -X POST https://tu-app.onrender.com/sync \
  -u ":tu_dashboard_password"
```

---

## Estructura del proyecto

```
├── app.rb                  # Servidor web (dashboard + webhook)
├── config.ru               # Entry point Rack/Puma
├── Rakefile                # Tareas: publish_products, sync_inventory
├── lib/
│   ├── walmart_client.rb   # Cliente API Walmart Chile
│   ├── jumpseller_client.rb # Cliente API Jumpseller
│   ├── product_mapper.rb   # Convierte productos JS → formato Walmart
│   └── order_mapper.rb     # Convierte órdenes Walmart → formato JS
├── scripts/
│   └── sync_orders.rb      # Script de sincronización de órdenes
├── views/
│   └── dashboard.erb       # Vista HTML del dashboard
├── data/
│   └── processed_orders.json # Registro de órdenes ya sincronizadas
├── .env.example            # Plantilla de configuración
└── render.yaml             # Configuración de deploy en Render.com
```

---

## Solución de problemas

**El dashboard pide contraseña pero no acepta la mía**
→ Verificar que `DASHBOARD_PASSWORD` en `.env` coincide con lo que se ingresa. El usuario puede ser cualquier texto.

**"No new orders" al sincronizar pero hay órdenes en Walmart**
→ Las órdenes deben estar en estado `Created` en Walmart. Si ya fueron `Acknowledged` por otro medio, no aparecerán.

**Error al crear orden en Jumpseller**
→ Revisar los logs del dashboard. Los errores más comunes son: producto sin stock, cliente con email inválido, o credenciales de Jumpseller incorrectas.

**Una orden aparece duplicada**
→ Revisar `data/processed_orders.json`. Si la orden tiene `js_order_id` con valor, ya está procesada y no se repetirá. Si tiene `null`, el intento anterior falló y se reintentará.
