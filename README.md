# Jumpseller × Walmart Chile Integration

Syncs products, inventory, and orders between a Jumpseller store and Walmart Chile Marketplace.

## How it works — the big picture

The integration runs as a web server with a dashboard. **Sync is triggered manually by pressing a button** — there is no background process running on its own. Each time the seller clicks **Sync** in the dashboard, the integration:

1. Checks Walmart for new orders and imports them into Jumpseller as paid orders
2. Reads current stock from Jumpseller and updates inventory on Walmart

This means the seller (or an automated scheduler) must press the button — or call the sync endpoint — regularly to keep both platforms in sync. For production use, we recommend scheduling an automatic call every 15 minutes (see [Production deploy](#production-deploy-rendercom)).

---

## What it does

| Feature | Description |
|---------|-------------|
| **Product publishing** | Sends the Jumpseller catalog to Walmart in GTIN format |
| **Inventory sync** | Reads stock from Jumpseller and updates Walmart on each sync |
| **Order sync** | Imports new Walmart orders into Jumpseller as paid orders on each sync |
| **Web dashboard** | Control panel with a **Sync** button, inventory status, and real-time logs |

---

## Requirements

- Ruby 3.x
- Bundler (`gem install bundler`)
- Active Jumpseller account with API access
- Walmart Chile Marketplace seller account with API Keys

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/aatronco/walmart-marketplace.git
cd walmart-marketplace
bundle install
```

### 2. Configure credentials

Copy the example file and fill in the real credentials:

```bash
cp .env.example .env
```

Edit `.env`:

```env
# Jumpseller credentials (Settings → API)
JUMPSELLER_LOGIN=your_login
JUMPSELLER_AUTH_TOKEN=your_auth_token

# Webhook secret (generate with the command below)
JUMPSELLER_WEBHOOK_SECRET=...

# Dashboard password (optional — leave unset for no password prompt)
DASHBOARD_PASSWORD=a_secure_password

# Walmart Chile credentials (Seller Center → Settings → API Keys)
WALMART_CLIENT_ID=your_client_id
WALMART_CLIENT_SECRET=your_client_secret
WALMART_ENV=production
```

To generate a `JUMPSELLER_WEBHOOK_SECRET`:
```bash
ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"
```

> ⚠️ The `.env` file must never be committed to Git. It is already listed in `.gitignore`.

---

## Usage

### Web dashboard (recommended)

Start the server:

```bash
bundle exec rackup config.ru -p 4567
```

Open `http://localhost:4567` in your browser. If `DASHBOARD_PASSWORD` is set, you will be prompted for a username and password — the username can be anything, the password is the value of `DASHBOARD_PASSWORD`. If it is not set, the dashboard opens directly with no password prompt (recommended only for local use — always set a password on a public deployment).

From the dashboard you can:
- View current inventory (Jumpseller vs Walmart, with safety buffer)
- Click **Sync** to import new Walmart orders and update inventory
- Monitor the activity log in real time

### Command-line scripts

**Publish products to Walmart** (first time, or when new products are added):
```bash
bundle exec rake publish_products
```

**Sync orders manually:**
```bash
ruby scripts/sync_orders.rb
```

**Sync inventory manually:**
```bash
bundle exec rake sync_inventory
```

---

## How order sync works

1. Fetches Walmart orders from the last 7 days with status `Created`
2. Skips orders already processed (tracked in `data/processed_orders.json`)
3. For each new order:
   - Looks up or creates the customer in Jumpseller by email
   - Creates the order in Jumpseller with status `Paid` and payment method `Walmart`
   - Marks the order as `Acknowledged` in Walmart
   - Saves the order ID to `processed_orders.json` to prevent duplicates
4. Syncs updated inventory back to Walmart

Orders created in Jumpseller include the following in the **Notes for the Shipping Company** field:
```
Venta Walmart Marketplace
Walmart Order ID : P111546914
Customer Order ID: 7462668002125
Fecha orden      : 2026-06-30 23:28
Entrega estimada : 2026-07-04 06:00
Método envío     : STANDARD
```

---

## Inventory safety buffer

To prevent overselling across multiple channels, the stock sent to Walmart is intentionally lower than the real Jumpseller stock. Two independent parameters control this:

**`STOCK_BUFFER`** is the minimum switch. If Jumpseller stock is at or below this number, Walmart sees **0** — regardless of anything else. This protects your last units from being sold on Walmart while you may still need them for other channels or pending orders.

**`STOCK_DIVISOR`** is the exposure fraction. Once stock is above the buffer, Walmart sees `floor(stock / STOCK_DIVISOR)`. This means you never expose your full inventory — even with 100 units, Walmart only sees 20. It acts as a speed limiter: the higher the divisor, the smaller the fraction Walmart sees.

They work in sequence:

```
if jumpseller_stock > STOCK_BUFFER
  walmart_stock = floor(jumpseller_stock / STOCK_DIVISOR)
else
  walmart_stock = 0
```

Default values (both `5`):

| Jumpseller stock | Passes buffer? | Walmart sees |
|------------------|----------------|--------------|
| 3 | No (3 ≤ 5) | **0** |
| 5 | No (5 ≤ 5) | **0** |
| 6 | Yes → 6/5 | **1** |
| 10 | Yes → 10/5 | **2** |
| 25 | Yes → 25/5 | **5** |
| 100 | Yes → 100/5 | **20** |

To adjust, add to `.env`:

```env
STOCK_BUFFER=5    # units kept off Walmart at minimum (safety floor)
STOCK_DIVISOR=5   # fraction exposed: Walmart sees 1 out of every 5 units
```

Raise `STOCK_BUFFER` if you want to reserve more units before Walmart shows any availability. Raise `STOCK_DIVISOR` if you want Walmart to see a smaller proportion of your stock.

---

## Production deploy (Render.com)

The repository includes a ready-to-use `render.yaml`. To deploy:

1. Connect the repository on [render.com](https://render.com)
2. Set the environment variables in the Render dashboard (same as your `.env`)
3. Deploys happen automatically on every push to `main`

For automatic order sync, set up a cron job on Render or an external scheduler to call `POST /sync` every 15 minutes:

```bash
curl -X POST https://your-app.onrender.com/sync \
  -u ":your_dashboard_password"
```

---

## Project structure

```
├── app.rb                   # Web server (dashboard + webhook)
├── config.ru                # Rack/Puma entry point
├── Rakefile                 # Tasks: publish_products, sync_inventory
├── lib/
│   ├── walmart_client.rb    # Walmart Chile API client
│   ├── jumpseller_client.rb # Jumpseller API client
│   ├── product_mapper.rb    # Converts Jumpseller products → Walmart format
│   └── order_mapper.rb      # Converts Walmart orders → Jumpseller format
├── scripts/
│   └── sync_orders.rb       # Order sync script
├── views/
│   └── dashboard.erb        # Dashboard HTML view
├── data/
│   └── processed_orders.json # Record of already-synced orders
├── .env.example             # Configuration template
└── render.yaml              # Render.com deploy configuration
```

---

## Troubleshooting

**Dashboard does not accept my password**
→ Check that `DASHBOARD_PASSWORD` in `.env` matches what you are entering. The username field can be anything. To disable the password entirely (local use only), remove `DASHBOARD_PASSWORD` from `.env`.

**"No new orders" when syncing but orders exist in Walmart**
→ Orders must be in `Created` status on Walmart. If they were already acknowledged by another means, they will not appear.

**Error creating order in Jumpseller**
→ Check the dashboard logs. The most common causes are: product out of stock, invalid customer email, or incorrect Jumpseller credentials.

**An order appears duplicated**
→ Check `data/processed_orders.json`. If the order has a non-null `js_order_id`, it was already processed and will not be repeated. If `js_order_id` is `null`, the previous attempt failed and will be retried on the next sync.
