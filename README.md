# Jumpseller × Walmart Chile Integration

Syncs products, inventory, and orders between a Jumpseller store and Walmart Chile Marketplace.

---

## What it does

| Feature | Description |
|---------|-------------|
| **Product publishing** | Sends the Jumpseller catalog to Walmart in GTIN format |
| **Inventory sync** | Updates stock on Walmart whenever it changes in Jumpseller |
| **Order sync** | Detects new Walmart sales and automatically creates them in Jumpseller as paid orders |
| **Web dashboard** | Control panel with inventory status, real-time logs, and a manual sync button |

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

# Dashboard password
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

Open `http://localhost:4567` in your browser. You will be prompted for a username and password — the username can be anything, the password is the value of `DASHBOARD_PASSWORD`.

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

To prevent overselling, the stock sent to Walmart is calculated as follows:

| Jumpseller stock | Walmart stock |
|------------------|---------------|
| 0–5 units | 0 |
| 6+ units | `floor(stock / 5)` |

Example: 25 units in Jumpseller → 5 units listed on Walmart.

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
→ Check that `DASHBOARD_PASSWORD` in `.env` matches what you are entering. The username field can be anything.

**"No new orders" when syncing but orders exist in Walmart**
→ Orders must be in `Created` status on Walmart. If they were already acknowledged by another means, they will not appear.

**Error creating order in Jumpseller**
→ Check the dashboard logs. The most common causes are: product out of stock, invalid customer email, or incorrect Jumpseller credentials.

**An order appears duplicated**
→ Check `data/processed_orders.json`. If the order has a non-null `js_order_id`, it was already processed and will not be repeated. If `js_order_id` is `null`, the previous attempt failed and will be retried on the next sync.
