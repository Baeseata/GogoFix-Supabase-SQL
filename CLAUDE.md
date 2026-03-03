# GogoFix POS System

## Project Overview
GogoFix is a multi-store POS (Point of Sale) system designed for phone repair shops that also sell phones, phone accessories, and miscellaneous products (speakers, lights, etc.).

- **Business**: 3 retail stores currently, selling phones/accessories, repair services, and misc products. May expand to more stores or commercialize the system for other businesses in the distant future (not a current priority).
- **Client**: WPF (C#) Windows desktop application (primary). A web companion (for tasks like photo capture, stocktaking, etc.) is planned for the future.
- **Backend**: Supabase (PostgreSQL) as cloud database + local SQLite for offline capability. The system must remain fully operational even when internet or Supabase is unavailable — no business downtime allowed.
- **Stage**: Database schema design phase — actively restructuring and rewriting all SQL schema files.
- **UI Language**: French and English
- **Code Language**: Comments in English and Chinese; SQL and code in English

## Architecture Overview

### Offline-First Design
The WPF client operates offline-first with local SQLite as the primary data store. Key UUIDs (transaction_id, customer_id, line_id, etc.) are generated client-side using UUID v7. Data syncs to Supabase when online. The `synced_at` field tracks sync status (NULL = not yet synced). The system must guarantee zero downtime — if Supabase is unreachable, all business operations continue via local SQLite.

### Table Async Requirement (Offline Snapshot + Deferred Cloud Sync)
Definition used in this repo:
- **Async required = YES**: when POS is offline, this table must still support high-frequency essential operations via local SQLite snapshot; all writes are synchronized to Supabase after reconnection.
- **Async required = NO**: this table does not need offline high-frequency write support and can remain cloud-first.

Sorted by SQL filename:

**YES (async required)**
- `07_customer_list_20260302.sql`
- `12_transaction_list_20260302.sql`
- `13_transaction_line_list_20260302.sql`
- `16_serialized_event_list_20260302.sql`
- `22_repair_ticket_list_20260302.sql`
- `23_repair_ticket_line_list_20260302.sql`

**NO (async not required)**
- `01_store_list_20260302.sql`
- `02_user_rights_templates_20260302.sql`
- `03_user_list_20260302.sql`
- `04_store_user_rights_20260302.sql`
- `05_supplier_list_20260302.sql`
- `06_mother_inventory_list_20260302.sql`
- `08_store_inventory_list_20260302.sql`
- `09_store_serialized_list_20260302.sql`
- `10_batch_list_20260302.sql`
- `11_shift_list_20260302.sql`
- `14_store_inventory_adjustment_list_20260302.sql`
- `15_store_inventory_adjustment_line_list_20260302.sql`
- `17_store_transfer_list_20260302.sql`
- `18_store_transfer_line_list_20260302.sql`
- `19_store_item_history_list_20260302.sql`
- `20_purchase_order_list_20260302.sql`
- `21_purchase_order_line_list_20260302.sql`

### Multi-Store Model
All data is scoped by `store_id` (text, e.g., "decarie", "marcel"). Stores share a global product catalog (`mother_inventory_list`) but maintain independent inventory, transactions, and users.

## Database Schema (17 SQL files in `Supabase SQL/`)

### Core ENUM Types
| Enum | Values | Purpose |
|------|--------|---------|
| `inventory_mode` | service, untracked, tracked, serialized | How a product tracks inventory |
| `valuation_method` | average, rate, fixed | How product cost is calculated |
| `stock_bucket` | empty, very_few, few, normal, too_much | Fuzzy stock level for untracked items |
| `serialized_status` | in_stock, in_transit, sold, repair, lost, wasted, void | Lifecycle state of a serialized unit |
| `transaction_type` | exchange, serialized, repair, sale, refund, payment | Transaction classification |
| `serialized_event_type` | purchase, sell, return, mark_as_sold, mark_as_lost, mark_as_wasted, store_transferred, transferred_accepted, repair_out, repair_in, delete, revive, serial_edit | Serialized item event log types |
| `repair_status` | pending, completed, paid, cancelled | Repair ticket lifecycle |

### Tables Overview

#### 1. Product Catalog (Global)
- **`mother_inventory_list`** (file 1): Global product catalog. Each product has `item_id` (100000-999999) + `variant_id` (auto-assigned per item_id starting from 0). `unique_id` is the true PK (auto-increment from 0). Contains item_name, category_path[], item_upc[], device_compatibility[], inventory_mode, valuation_method, default_cost, default_price, supplier_id.

#### 2. Store Inventory
- **`store_inventory_list`** (file 2): Per-store inventory for service/tracked/untracked items. PK = (store_id, unique_id). `qty_on_hand` for tracked, `stock_bucket` for untracked (mutually exclusive). Cost/price inherited from mother table on INSERT.
- **`store_serialized_list`** (file 3): Per-unit inventory for serialized items (e.g., phones with IMEI). Each row = one physical unit. `serial` is globally unique (even after deletion). Has `status` lifecycle, `attribute` (jsonb for color/capacity/etc).

#### 3. People
- **`store_list`** (file 6): Store master table. Contains tax_rates (jsonb), contact info, logo path.
- **`user_list`** (file 7): Employee accounts with self-managed password hashing (bcrypt/argon2). Not using Supabase Auth.
- **`user_rights_templates`** (file 5): Permission templates (can_view_report, can_edit_settings, can_edit_invoice, can_manage_user, can_adjust_inventory, is_true_user).
- **`store_user_rights`** (file 7): Links user + store + template. PK = (user_id, store_id).
- **`customer_list`** (file 4): Customer records with UUID v7 PK (client-generated). Phone number unique among active customers. Has `balance_total` (updated via RPC).

#### 4. Transactions
- **`transaction_list`** (file 8): Transaction headers. UUID v7 PK (client-generated). Includes human-readable `display_no` (`{store_code}{device_no}S-{YYMMDD}-{NNN}`) for receipts while UUID remains the PK. Links to store, customer, user, shift. Has payment breakdown (cash, credit, debit, balance) with CHECK constraints ensuring amount_total = sum of payments, profit_total = amount - tax - cost.
- **`transaction_line_list`** (file 10): Transaction line items. UUID v7 PK. Links to unique_id and optionally unit_id (for serialized). CHECK constraints validate line_total_before_tax, line_total, line_profit calculations.

#### 5. Batch & Shift
- **`batch_list`** (file 9): Business day batches per store. batch_id auto-increments per store. Only one open batch per store at a time.
- **`shift_list`** (file 9): Employee shifts within batches. shift_id auto-increments per store (global, not per batch). One open shift per device. Tracks opening/closing cash.

#### 6. Inventory Operations
- **`store_inventory_adjustment_list`** + **`_line_list`** (file 11): Inventory adjustments for tracked/untracked items (not serialized, not service). Records qty_delta or stock_bucket changes.
- **`serialized_event_list`** (file 12): Complete lifecycle audit log for serialized items. Immutable-like (INSERT only by design). Records every status change with event_type.
- **`store_transfer_list`** + **`_line_list`** (file 13): Inter-store inventory transfers. Supports tracked/untracked/serialized items. Requires confirmation by receiving store.
- **`store_item_history_list`** (file 14): Aggregated inventory change history from all sources. Immutable (triggers block UPDATE/DELETE). Uses text types for flexible qty_snapshot across all inventory modes.

#### 7. Supply Chain
- **`supplier_list`** (file 15): Supplier master table. Replaces the old text-based `supplier` column in mother_inventory_list with `supplier_id` FK.
- **`purchase_order_list`** + **`_line_list`** (file 16): Purchase orders from suppliers. purchase_order_id auto-increments per store. Supports serialized items (qty=1 with unit_id+serial).

#### 8. Repair
- **`repair_ticket_list`** + **`_line_list`** (file 17): Repair work orders. UUID v7 PK. Header includes human-readable `display_no` (`{store_code}{device_no}R-{YYMMDD}-{NNN}`) while UUID remains the PK. Records customer device info, technician assignment, repair status lifecycle. transaction_list has `repair_ticket_id` FK for linking completed repairs to payment transactions.

### Key Design Patterns
1. **Soft Delete**: All major tables use `deleted_at` (NULL = active). Partial unique indexes exclude deleted rows.
2. **Auto-increment per scope**: `variant_id` per item_id, `batch_id`/`shift_id`/`purchase_order_id` per store_id, using `pg_advisory_xact_lock` to prevent race conditions.
3. **Mode enforcement triggers**: INSERT/UPDATE triggers validate data consistency based on `inventory_mode` (service/tracked/untracked/serialized have different required fields).
4. **Immutable audit logs**: `serialized_event_list` and `store_item_history_list` block UPDATE/DELETE via triggers.
5. **Client-side calculation with DB validation**: Totals computed by WPF client, validated by CHECK constraints on INSERT.
6. **`updated_at` auto-refresh**: All mutable tables use `set_updated_at()` trigger.

### Table Relationships (Simplified)
```
store_list
  +-- store_inventory_list (store_id)
  +-- store_serialized_list (store_id)
  +-- batch_list (store_id)
  |     +-- shift_list (store_id, batch_id)
  +-- transaction_list (store_id)
  |     +-- transaction_line_list (transaction_id)
  +-- store_transfer_list (store_id -> target_store_id)
  +-- purchase_order_list (store_id)
  +-- store_user_rights (store_id)
  +-- repair_ticket_list (store_id)

mother_inventory_list (unique_id)
  +-- store_inventory_list (unique_id)
  +-- store_serialized_list (unique_id)
  +-- transaction_line_list (unique_id)
  +-- store_transfer_line_list (unique_id)
  +-- purchase_order_line_list (unique_id)

customer_list (customer_id)
  +-- transaction_list (customer_id)
  +-- repair_ticket_list (customer_id)

user_list (user_id)
  +-- store_user_rights (user_id)
  +-- transaction_list (user_id)
  +-- batch_list (opened_by/closed_by)
  +-- shift_list (user_id)

supplier_list (supplier_id)
  +-- mother_inventory_list (supplier_id)
  +-- purchase_order_list (supplier_id)
```

## File Structure (23 .sql files, one table per file)
```
GogoFix/
  CLAUDE.md
  archive/
    sql_1/                # 原始 17 个 RTF 建表文件（2026-03-02 重构前的备份）
  Supabase SQL/
    01_store_list_20260302.sql                            # store_list
    02_user_rights_templates_20260302.sql                 # user_rights_templates
    03_user_list_20260302.sql                             # user_list + set_updated_at() 共享函数
    04_store_user_rights_20260302.sql                     # store_user_rights
    05_supplier_list_20260302.sql                         # supplier_list
    06_mother_inventory_list_20260302.sql                 # mother_inventory_list + inventory_mode / valuation_method ENUMs
    07_customer_list_20260302.sql                         # customer_list
    08_store_inventory_list_20260302.sql                  # store_inventory_list + stock_bucket ENUM
    09_store_serialized_list_20260302.sql                 # store_serialized_list + serialized_status ENUM + block_mode_change
    10_batch_list_20260302.sql                            # batch_list
    11_shift_list_20260302.sql                            # shift_list
    12_transaction_list_20260302.sql                      # transaction_list + transaction_type ENUM
    13_transaction_line_list_20260302.sql                 # transaction_line_list
    14_store_inventory_adjustment_list_20260302.sql       # adjustment_list
    15_store_inventory_adjustment_line_list_20260302.sql  # adjustment_line_list
    16_serialized_event_list_20260302.sql                 # serialized_event_list + serialized_event_type ENUM
    17_store_transfer_list_20260302.sql                   # store_transfer_list
    18_store_transfer_line_list_20260302.sql              # store_transfer_line_list
    19_store_item_history_list_20260302.sql               # store_item_history_list (immutable)
    20_purchase_order_list_20260302.sql                   # purchase_order_list
    21_purchase_order_line_list_20260302.sql              # purchase_order_line_list
    22_repair_ticket_list_20260302.sql                    # repair_ticket_list + repair_status ENUM + transaction_list 补丁
    23_repair_ticket_line_list_20260302.sql               # repair_ticket_line_list
```

## Notes for Claude
- **SQL files are now stored as `.sql` plain text files** (migrated from RTF). Open with Sublime Text or any text editor.
- The database uses `public` schema exclusively.
- `inventory_mode` is the central concept that drives most trigger logic and data validation.
- Files may contain "补丁" (patches) that ALTER existing tables created in earlier files - read files in order.
- All ID auto-increments start from 0 (except batch_id and shift_id which start from 1).
- The system does NOT use Supabase Auth; authentication is self-managed via user_list.
- Table relationships diagram has known minor inaccuracies — will be corrected as schema is finalized.
- The SQL schema files are actively being restructured and rewritten. File list and content will evolve.
