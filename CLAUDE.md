# GogoFix POS System

## Project Overview
GogoFix is a multi-store POS (Point of Sale) system designed for phone repair shops that also sell phones, phone accessories, and miscellaneous products (speakers, lights, etc.).

- **Business**: 3 retail stores currently, selling phones/accessories, repair services, and misc products. May expand to more stores or commercialize the system for other businesses in the distant future (not a current priority).
- **Client**: WPF (C#) Windows desktop application (primary). A web companion (for tasks like photo capture, stocktaking, etc.) is planned for the future.
- **Backend**: Supabase (PostgreSQL) as cloud database + local SQLite for offline capability. The system must remain fully operational even when internet or Supabase is unavailable — no business downtime allowed.
- **Stage**: Phase 0 complete (Core foundation library built). Phase 1 DataOps UI next.
- **WPF Repo**: https://github.com/Baeseata/GogoFix (master branch, .NET 10)
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
- `07_cloud_customer_list.sql`
- `12_cloud_transaction_list.sql`
- `13_cloud_transaction_line_list.sql`
- `16_cloud_serialized_event_list.sql`
- `22_cloud_repair_ticket_list.sql`
- `23_cloud_repair_ticket_line_list.sql`

**NO (async not required)**
- `01_cloud_store_list.sql`
- `02_cloud_user_rights_templates.sql`
- `03_cloud_user_list.sql`
- `04_cloud_store_user_rights.sql`
- `05_cloud_supplier_list.sql`
- `06_cloud_mother_inventory_list.sql`
- `08_cloud_store_inventory_list.sql`
- `09_cloud_store_serialized_list.sql`
- `10_cloud_batch_list.sql`
- `11_cloud_shift_list.sql`
- `14_cloud_store_inventory_adjustment_list.sql`
- `15_cloud_store_inventory_adjustment_line_list.sql`
- `17_cloud_store_transfer_list.sql`
- `18_cloud_store_transfer_line_list.sql`
- `19_cloud_store_item_history_list.sql`
- `20_cloud_purchase_order_list.sql`
- `21_cloud_purchase_order_line_list.sql`
- `24_cloud_store_demand_list.sql`
- `25_cloud_device_list.sql`
- `26_cloud_sync_changes.sql`
- `28_cloud_historical_transaction_line.sql`

### Multi-Store Model
All data is scoped by `store_id` (text, e.g., "decarie", "marcel"). Stores share a global product catalog (`mother_inventory_list`) but maintain independent inventory, transactions, and users.

## Database Schema (26 SQL files in `Supabase SQL/`)

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
| `demand_status` | pending, processing, rejected, done | Store demand review workflow |
| `device_environment` | dev, register, amir, tech | Device runtime mode / client channel |
| `sync_event_type` | transaction_committed, inventory_adjustment_committed, purchase_order_received, store_transfer_committed, store_transfer_received, repair_ticket_committed, customer_updated, supplier_updated, misc_updated | Business sync event classification |

### Tables Overview

#### 1. Product Catalog (Global)
- **`mother_inventory_list`** (file 1): Global product catalog. Each product has `item_id` (100000-999999) + `variant_id` (auto-assigned per item_id starting from 0). `unique_id` is the true PK (auto-increment from 0). Contains item_name, category_path[], item_upc[], device_compatibility[], inventory_mode, valuation_method, default_cost, default_price, supplier_id. `item_name` is unique among active rows (plus client-side duplicate-name check is recommended during creation).

#### 2. Store Inventory
- **`store_inventory_list`** (file 2): Per-store inventory for service/tracked/untracked items. PK = (store_id, unique_id). `qty_on_hand` for tracked, `stock_bucket` for untracked (mutually exclusive). Cost/price inherited from mother table on INSERT.
- **`store_serialized_list`** (file 3): Per-unit inventory for serialized items (e.g., phones with IMEI). Each row = one physical unit. `serial` is globally unique (even after deletion). Has `status` lifecycle, `attribute` (jsonb for color/capacity/etc).

#### 3. People
- **`store_list`** (file 6): Store master table. Contains tax_rates (jsonb), contact info, logo path, receipt/repair policy texts, website/postcode, QR-print fields (`store_qr`, `store_qr_note_before`, `store_qr_note_after`), and `is_active` (whether the store is operationally active).
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

#### 9. Store Demands
- **`store_demand_list`** (file 24): Shared quick-capture demand log for all staff. Composite PK `(store_id, demand_id)` where `demand_id` auto-increments per store starting at 0. Includes `tag`, `status` (`pending/processing/rejected/done`), plain-text `content`, creator/reviewer fields, manager note, and soft delete.

#### 10. Device Registry
- **`device_list`** (file 25): POS terminal registry table. Stores per-device metadata (`device_id`, `terminal_no`, `device_name`, app version, last heartbeat), runtime environment (`dev/register/amir/tech`), active flag, and soft delete. `terminal_no` is unique per store among active rows.

#### 11. Sync Event Log
- **`sync_changes`** (file 26): Cloud sync event log (append-only).

#### 12. Historical Data
- **`historical_transaction_line`** (file 28): Legacy POS transaction line data imported from CellSmart/CellPoint. Scoped by `store_id` FK. Auto-increment `row_id` PK. Dedup via UNIQUE on `(store_id, source_id, transaction_time, product_name)`. Includes `source_pos` to track origin system. Does NOT participate in sync engine. One completed business action writes one event row with idempotent `event_id`, optional `correlation_id`, `event_type`, `entity_ids[]`, store scope fields, and `payload_json`. Client must write business data and `sync_changes` in the same DB transaction (all succeed or all rollback).

### Key Design Patterns
1. **Soft Delete**: All major tables use `deleted_at` (NULL = active). Partial unique indexes exclude deleted rows.
2. **Auto-increment per scope**: `variant_id` per item_id, `batch_id`/`shift_id`/`purchase_order_id` per store_id, using `pg_advisory_xact_lock` to prevent race conditions.
3. **Mode enforcement triggers**: INSERT/UPDATE triggers validate data consistency based on `inventory_mode` (service/tracked/untracked/serialized have different required fields).
4. **Immutable audit logs**: `serialized_event_list`, `store_item_history_list`, and `sync_changes` block UPDATE/DELETE via triggers.
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
  +-- store_demand_list (store_id)
  +-- device_list (store_id)
  +-- sync_changes (source_store_id / target_store_id)
  +-- historical_transaction_line (store_id)

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
  +-- store_demand_list (created_by/reviewed_by)

supplier_list (supplier_id)
  +-- mother_inventory_list (supplier_id)
  +-- purchase_order_list (supplier_id)
```

## File Structure (26 .sql files, one table per file)
```
GogoFix/
  CLAUDE.md
  archive/
    sql_1/                # 原始 17 个 RTF 建表文件（2026-03-02 重构前的备份）
  Supabase SQL/
    01_cloud_store_list.sql                            # store_list
    02_cloud_user_rights_templates.sql                 # user_rights_templates
    03_cloud_user_list.sql                             # user_list + set_updated_at() 共享函数
    04_cloud_store_user_rights.sql                     # store_user_rights
    05_cloud_supplier_list.sql                         # supplier_list
    06_cloud_mother_inventory_list.sql                 # mother_inventory_list + inventory_mode / valuation_method ENUMs
    07_cloud_customer_list.sql                         # customer_list
    08_cloud_store_inventory_list.sql                  # store_inventory_list + stock_bucket ENUM
    09_cloud_store_serialized_list.sql                 # store_serialized_list + serialized_status ENUM + block_mode_change
    10_cloud_batch_list.sql                            # batch_list
    11_cloud_shift_list.sql                            # shift_list
    12_cloud_transaction_list.sql                      # transaction_list + transaction_type ENUM
    13_cloud_transaction_line_list.sql                 # transaction_line_list
    14_cloud_store_inventory_adjustment_list.sql       # adjustment_list
    15_cloud_store_inventory_adjustment_line_list.sql  # adjustment_line_list
    16_cloud_serialized_event_list.sql                 # serialized_event_list + serialized_event_type ENUM
    17_cloud_store_transfer_list.sql                   # store_transfer_list
    18_cloud_store_transfer_line_list.sql              # store_transfer_line_list
    19_cloud_store_item_history_list.sql               # store_item_history_list (immutable)
    20_cloud_purchase_order_list.sql                   # purchase_order_list
    21_cloud_purchase_order_line_list.sql              # purchase_order_line_list
    22_cloud_repair_ticket_list.sql                    # repair_ticket_list + repair_status ENUM + transaction_list 补丁
    23_cloud_repair_ticket_line_list.sql               # repair_ticket_line_list
    24_cloud_store_demand_list.sql                    # store_demand_list + demand_status ENUM
    25_cloud_device_list.sql                          # device_list + device_environment ENUM
    26_cloud_sync_changes.sql                         # sync_changes + sync_event_type ENUM
    28_cloud_historical_transaction_line.sql           # historical_transaction_line (legacy POS import)
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


## Local SQLite Schema

A new folder `Local SQLite/` is provided alongside `Supabase SQL/`.

- `Local SQLite/01_local_*.sql` to `Local SQLite/25_local_*.sql`: local executable SQLite DDL for the 25 business tables.
- `Local SQLite/26_local_sync_outbox.sql`: local outbound sync queue (`pending/acted/error` status state machine).
- `Local SQLite/27_local_sync_inbox.sql`: local inbound dedupe/apply log by `event_id`.
- `Local SQLite/28_local_historical_transaction_line.sql`: legacy POS historical transaction line data (CellSmart/CellPoint imports).

Design notes:
- PostgreSQL-specific types (`uuid`, `jsonb`, `timestamptz`, arrays, enum types) are mapped into SQLite-compatible definitions while preserving business semantics with `CHECK` constraints where needed.
- `PRAGMA foreign_keys = ON;` is included in each local SQL file.

## SQL Coding Convention (Repository)

This section documents the practical conventions currently used across `Supabase SQL/` and `Local SQLite/`.

- **File naming/order**: one table per file, prefixed with ordered number (`01_...sql` to `27_...sql`) to preserve dependency/read order.
- **Header comments**: SQLite files should start with source mapping comments (e.g., `Local SQLite version of ...` and source/intent reference).
- **Comment language**: keep SQL identifiers in English; write schema comments in **English + Chinese** pair style (English line followed by Chinese line).
- **Column comments in DDL**: for each business-relevant column, add a short bilingual comment block immediately above the column definition.
- **Constraint comments**: CHECK/PK/UNIQUE/INDEX definitions should include concise bilingual comments describing rule intent.
- **Soft-delete semantics**: use `deleted_at` with `NULL = active` where soft delete applies.
- **Timestamps**: prefer `created_at` / `updated_at` with clear behavior comments; for SQLite defaults, use `CURRENT_TIMESTAMP`.
- **JSON fields in SQLite**: store as `text` and validate with `CHECK (json_valid(...))` whenever JSON payload correctness matters.
- **ID/style consistency**: snake_case identifiers, explicit `NOT NULL` / `DEFAULT` declarations, and readable multi-line constraints/indexes.
- **Compatibility-first SQL**: keep local SQLite DDL executable in SQLite (avoid PostgreSQL-only syntax in `Local SQLite/` files).

## Confirmed Technical Decisions & Collaboration Constraints (Do Not Re-argue)

This section consolidates confirmed decisions from the project owner. Future architecture/design/code suggestions in this repo should treat these as fixed defaults unless explicitly overridden by a new request.

### 1) Desktop host is fixed: WPF + .NET
- Main desktop runtime must be **WPF + .NET** on Windows.
- Do **not** proactively re-recommend Electron, Tauri, pure web desktop shell, or MAUI as the main desktop host.
- Focus rationale: long-running Windows stability, local SQLite direct access, printer/scanner/cash-drawer/camera integration, local file I/O, background sync worker robustness.

### 2) UI reuse direction: WPF host + Blazor/Razor-first reusable business UI
- Prefer this split by default:
  - **WPF/.NET**: native shell, device integration, local services.
  - **Blazor Hybrid / Razor components**: reusable business pages/forms/lists.
- Future web admin backend should reuse as much business UI/model logic as practical.
- If a feature must remain pure WPF, explain concrete technical reasons.

### 3) Data architecture defaults
- **Local DB (per store client)**: SQLite snapshot/main operational store for offline sales, inventory/repair history, serial lookup, and millisecond-level search.
- **Center DB**: PostgreSQL (can be deployed on a Windows host machine in main store), syncing with branch-store clients.
- Do not shift high-frequency core queries to remote API-only mode.
- Do not place SQLite DB on network shared disk as primary runtime strategy.

### 4) Attachment/photo policy
- Large files (repair photos etc.) are not primary DB blobs.
- Physical files live on main-store host disk; DB stores metadata/path/hash/relations.
- Offline workflow: local file landing first, then deferred sync/upload.

### 5) Sync architecture defaults (critical)
- Offline-first is mandatory: sales/repair/counting/inventory operations must continue while disconnected.
- Use **event/change-set driven incremental sync**, not whole-table mirror overwrite.
- Use **Outbox / Inbox / Checkpoint** model with idempotency.
- Sync source-of-truth ordering must not rely on client local timestamps.
- Inventory sync should be movement/event based (sell/purchase/adjust/transfer/scrap/repair allocate-release), not just latest qty overwrite.

### 6) Inventory model requirement
- Always separate:
  - **Precise serialized inventory** (IMEI/serial unique items).
  - **Non-precise bulk inventory** (accessories/consumables).
- Do not force both categories into one identical deduction model.

### 7) Windows local capability priority
- Must be designed with first-class support for:
  - receipt printer / label printer
  - scanner
  - cash drawer
  - camera & image upload
  - local file read/write
  - local DB maintenance
  - background sync service
  - stable install/update workflow
- Keep hardware-facing logic in WPF/.NET native layer; web UI layer focuses on presentation and workflows.

### 8) Mobile collaboration mode
- No standalone mobile app is planned.
- Default workflow:
  - employee logs in on Windows POS,
  - POS generates QR,
  - phone browser scans and opens permission-scoped web workspace.
- Mobile browser pages handle lightweight tasks (counting/photo upload/assisted input) and should share backend with future web admin.

### 9) Expected future assistance output style
When proposing next steps, prioritize implementable artifacts over abstract discussion:
- concrete table design (SQLite + PostgreSQL)
- module boundaries
- sync table design (outbox/inbox/checkpoint/attachments)
- inventory movement model
- repair-ticket + attachment model
- WPF + Blazor Hybrid boundary and responsibilities
- Windows printing abstraction interfaces
- QR login token/link flow
- phased MVP implementation order

## Historical Transaction Data Migration Pipeline

### Background
All 3 stores previously used **CellSmart POS**. As of late 2025, Decarie and Marcel have switched to **CellPoint POS**; Parcex will follow soon. Eventually all stores will migrate to GogoFix POS. This creates a need to consolidate historical transaction line data from multiple POS systems into one unified format.

### 3-Level Data Pipeline
```
Level 1: Raw Export        →  Level 2: Standardized CSV    →  Level 3: Database
(CellSmart / CellPoint       (unified format, locally         (local SQLite +
 native export format)         stored, human-readable)          cloud Supabase)
```
- **Level 1 → Level 2 (Rinse & Merge)**: DataOps Import/Export → "Rinse & Merge" tab. User selects store (decarie/marcel/parcex), POS source (CellSmart/CellPoint), raw CSV, and optional target CSV. Parses raw format, fixes date bugs (e.g. "20" prefix), normalizes columns, deduplicates, and outputs standardized Level 2 CSV. Supports skip/replace on duplicates, and replace-file/create-new output modes. File naming is automatic: `{store}_{YYYYMMDD}_{YYYYMMDD}.csv`.
- **Level 2 → Level 3 (Sync to DB)**: DataOps Import/Export → "Sync to DB" tab. User selects Level 2 CSV, store, POS source. Validates all data first (fail-fast on any bad row), then batch-inserts into `historical_transaction_line` in local SQLite. Supports skip/replace on duplicates. Cloud DB sync button is stubbed (Supabase not yet connected).
- **Level 2 files are kept** as local archive — CSV is human-readable and serves as a backup/audit trail.

### Standard CSV Format (Level 2)
**File naming**: `{store}_{YYYYMMDD}_{YYYYMMDD}.csv` (store name + start date + end date)
**Location**: `C:\Users\jerry\source\repos\rawdata\`

**13 columns, consistent across all stores:**
```
ID, Time, Customer, Phone Number, Product Name, Invoice Type, IMIE Number, Rep Name, Unit Price, Discount, Quantity, Tax Amount, Ext Amount
```

**Time format**: `M-D-YY h:mm AM/PM` (e.g., `12-31-25 5:19 PM`)
**Currency fields**: prefixed with `$` (e.g., `$239.17`)

### Current CSV Files
| File | Store | Rows | Date Range |
|------|-------|------|------------|
| `decarie_20170410_20251231.csv` | Decarie | 263,296 | 2017-04-10 → 2025-12-31 |
| `parcex_20180328_20260131.csv` | Parcex | 70,692 | 2018-03-28 → 2026-01-31 |
| `marcel_20250709_20251209.csv` | Marcel | 1,260 | 2025-07-09 → 2025-12-09 |

### Known Data Quality Issues (Resolved)
- **Decarie**: 829 rows had corrupted dates — `20` prefix turned `12-DD-25` into `2012-DD-25` (YYYY-MM-DD format with 24h time). Fixed by stripping `20` prefix and converting 24h → 12h time.
- **Parcex**: Original time format was `YYYYMMDD HH.mm` (e.g., `20260131 18.41`). Converted to standard `M-D-YY h:mm AM/PM` format.
- **Parcex**: Column was named `Time_normalized` instead of `Time`. Renamed to match standard.
- **Decarie**: Column names used short lowercase (`#`, `time`, `name`, etc.). Renamed to match standard verbose names.
- **Marcel**: Had duplicate `Phone Number` column (raw + formatted). Dropped the formatted duplicate.
- **All files**: IMEI numbers verified — no scientific notation corruption found.

### Level 3 Database Table ✅
- [x] `historical_transaction_line` table created (file 28, local SQLite + Supabase)
- [x] `store_id` FK to `store_list` (values: "decarie", "marcel", "parcex")
- [x] `source_pos` column tracks origin system ("cellsmart", "cellpoint", "gogofix")
- [x] Dedup via UNIQUE constraint on `(store_id, source_id, transaction_time, product_name)`
- [x] `row_id` auto-increment surrogate PK (source IDs not unique across stores)
- [x] DataOps Rinse & Merge: raw CSV → Level 2 CSV (CellSmart + CellPoint parsers, date fixing, dedup)
- [x] DataOps Sync to Local DB: Level 2 CSV → `historical_transaction_line` (validation, batch insert, dedup)
- [ ] DataOps Sync to Cloud DB: waiting on Supabase connection setup
- [ ] DataOps / POS query UI for historical data browsing

### Raw Data Samples (Level 1 formats)
Located in `C:\Users\jerry\source\repos\rawdata\`:
- `rptTransactions-parcex.csv` — **CellSmart** export format sample (3 header rows, spacer columns)
- `xrTransactionHistory-marcel.csv` — **CellPoint** export format sample (4 header rows, different column names, has Cost/Profit columns)

---

## Development TODO / Roadmap

Target: usable DataOps by ~mid April 2026, POS MVP trial in-store by ~May 2026.

Runtime: .NET 10, WPF desktop, Visual Studio.
Current status: **Phase 0 COMPLETE** (2026-03-12). GogoFix.Core foundation library fully built, 27 entity models, Dapper data access, SQLite schema initializer, Serilog logging — all verified working.

**Key technical decisions:**
- **ORM**: raw SQL schema creation (execute .sql files) + Dapper for query/mapping. NOT using EF Core.
- **NuGet packages (Core)**: `Microsoft.Data.Sqlite`, `Dapper`, `Supabase` (supabase-csharp), `Serilog` + `Serilog.Sinks.File`, `System.Text.Json`
- **NuGet packages (DataOps)**: `CommunityToolkit.Mvvm` (MVVM helpers), `ICSharpCode.AvalonEdit` (SQL editor syntax highlighting)

---

### Phase 0: GogoFix.Core — Foundation Layer ✅ COMPLETE (2026-03-12)
> Core is the shared library that both DataOps and POS depend on.
> Commit: `c375b5b` on https://github.com/Baeseata/GogoFix

#### 0.1 Project setup & NuGet ✅
- [x] GogoFix.Core NuGet packages: `Dapper`, `Microsoft.Data.Sqlite`, `Serilog` + `Serilog.Sinks.File` + `Serilog.Sinks.Console`
- [x] Removed all EF Core packages from GogoFix.csproj, deleted `LocalDatabase/` and `Migrations/` folders
- [x] Both GogoFix and GogoFix.DataOps reference GogoFix.Core
- Note: `Supabase` (supabase-csharp) and `BCrypt.Net-Next` deferred to when cloud sync / auth is needed

#### 0.2 Configuration system ✅
- [x] `AppSettings.cs` — root config with `LocalDatabaseSettings`, `LoggingSettings`, `StoreId`, `DeviceId`
- [x] `ConfigurationLoader.cs` — loads `appsettings.json` from app base directory via `System.Text.Json`
- [x] Each app has its own `appsettings.json` (CopyToOutputDirectory: PreserveNewest)
- Simplified from original plan: single `AppSettings` class instead of separate config files per concern. Supabase config section will be added when needed.

#### 0.3 SQLite data access layer ✅
- [x] `SqliteConnectionFactory.cs` — creates connections with `PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;`
- [x] `SchemaInitializer.cs` — executes embedded SQL resource (`LocalSchema.sql`, 1818 lines, all 27 tables)
- [x] `EnsureDatabaseCreated()` — creates DB directory + file + runs schema on first launch
- [x] Database path: `%LocalAppData%/GogoFix/local.db`
- Implementation note: schema SQL is embedded as assembly resource (not read from filesystem). All 27 CREATE TABLE IF NOT EXISTS statements are concatenated into one file for idempotent execution.

#### 0.4 Supabase data access layer — DEFERRED
> Deferred to Phase 1 / Phase 2. Phase 0 focuses entirely on local SQLite foundation.

#### 0.5 Data models & enums ✅
- [x] **Enums** (`GogoFix.Core/Enums/Enums.cs`): InventoryMode, ValuationMethod, SerializedStatus, SerializedEventType, TransactionType, SyncStatus, DemandStatus, DeviceEnvironment, TransferStatus, AdjustmentType
- [x] **Entity classes** (`GogoFix.Core/Entities/`, 27 files — one per table): Store, UserRightsTemplate, User, StoreUserRights, Supplier, MotherInventoryItem, Customer, StoreInventoryItem, StoreSerializedItem, Batch, Shift, Transaction, TransactionLine, InventoryAdjustment, InventoryAdjustmentLine, SerializedEvent, StoreTransfer, StoreTransferLine, StoreItemHistory, PurchaseOrder, PurchaseOrderLine, RepairTicket, RepairTicketLine, StoreDemand, Device, SyncOutbox, SyncInbox
- [x] **Dapper snake_case mapping**: `DefaultTypeMap.MatchNamesWithUnderscores = true` (auto maps `created_at` → `CreatedAt`)
- [x] **Enum type handlers** (`EnumTypeHandlers.cs`): PascalCase C# enum ↔ snake_case DB string (e.g., `InStock` ↔ `"in_stock"`)
- [x] `[Table("table_name")]` and `[Key]` custom attributes for repository pattern
- Implementation note: timestamps stored as `string` in entities (matching SQLite TEXT storage). JSON columns also `string` — parsing done at service layer.

#### 0.6 Sync engine (Outbox/Inbox) — DEFERRED
> Deferred to Phase 1 DataOps sync monitor. Phase 0 provides the entity models (`SyncOutbox`, `SyncInbox`) and the DB tables. Actual sync logic (sender/poller/applier/background service) will be built when Supabase integration begins.

#### 0.7 Logging ✅
- [x] `LoggerSetup.cs` — Serilog init with file sink (`gogofix-{Date}.log`, rolling daily, 30-day retention) + console sink
- [x] Log directory: `%LocalAppData%/GogoFix/Logs/`
- [x] Minimum level configurable via `appsettings.json`

#### 0.8 Bootstrapper & App Wiring ✅ (added during implementation)
- [x] `CoreBootstrapper.cs` — single `Initialize()` call: load config → setup logging → configure Dapper → register enum handlers → create DB
- [x] `CoreServices.cs` — holds `AppSettings` + `SqliteConnectionFactory` + `ILogger`
- [x] `BaseRepository.cs` — generic CRUD via Dapper reflection (InsertAsync, UpdateAsync, GetByIdAsync, GetAllAsync, SoftDeleteAsync, QueryAsync, ExecuteAsync)
- [x] `NamingHelper.cs` — PascalCase → snake_case converter for dynamic SQL generation
- [x] Both `GogoFix/App.xaml.cs` and `GogoFix.DataOps/App.xaml.cs` call `CoreBootstrapper.Initialize()` on startup

#### GogoFix.Core Actual File Tree (as built)
```
GogoFix.Core/
├── GogoFix.Core.csproj
├── CoreBootstrapper.cs              # one-call init entry point
├── CoreServices.cs                  # service bag (settings + DB factory + logger)
├── Attributes/
│   └── TableAttribute.cs            # [Table] + [Key] attributes
├── Configuration/
│   ├── AppSettings.cs               # config POCO
│   └── ConfigurationLoader.cs       # JSON loader
├── Database/
│   ├── DapperConfig.cs              # MatchNamesWithUnderscores
│   ├── EnumTypeHandlers.cs          # enum ↔ snake_case string
│   ├── SchemaInitializer.cs         # executes embedded SQL
│   ├── SqliteConnectionFactory.cs   # connection + WAL + FK pragmas
│   └── Schema/
│       └── LocalSchema.sql          # 27 tables (embedded resource, 1818 lines)
├── Entities/                        # 27 entity classes
│   ├── Store.cs               ├── Customer.cs
│   ├── UserRightsTemplate.cs  ├── StoreInventoryItem.cs
│   ├── User.cs                ├── StoreSerializedItem.cs
│   ├── StoreUserRights.cs     ├── Batch.cs
│   ├── Supplier.cs            ├── Shift.cs
│   ├── MotherInventoryItem.cs ├── Transaction.cs
│   ├── TransactionLine.cs     ├── InventoryAdjustment.cs
│   ├── InventoryAdjustmentLine.cs  ├── SerializedEvent.cs
│   ├── StoreTransfer.cs       ├── StoreTransferLine.cs
│   ├── StoreItemHistory.cs    ├── PurchaseOrder.cs
│   ├── PurchaseOrderLine.cs   ├── RepairTicket.cs
│   ├── RepairTicketLine.cs    ├── StoreDemand.cs
│   ├── Device.cs              ├── SyncOutbox.cs
│   └── SyncInbox.cs
├── Enums/
│   └── Enums.cs                     # all business enums
├── Helpers/
│   └── NamingHelper.cs              # PascalCase → snake_case
├── Logging/
│   └── LoggerSetup.cs               # Serilog init
└── Repositories/
    └── BaseRepository.cs            # generic CRUD via Dapper
```


---

### Phase 1: GogoFix.DataOps — DB Management Tool (Detailed)
> WPF desktop app for database management, data browsing, import/export, sync testing, and SQL querying.
> Architecture: MVVM with CommunityToolkit.Mvvm, single-window with tab-based layout.

#### 1.0 App shell & navigation
> Files: `GogoFix.DataOps/`

- [ ] **MainWindow.xaml** — left sidebar nav + right content area (tab or page switching)
  - Sidebar buttons: DB Management, Data Browser, Import/Export, Sync Monitor, Query Console
  - Status bar: SQLite path, connection status (local/cloud), sync status
- [ ] **App.xaml.cs** — startup: load config, init SQLite connection, init Serilog, init Supabase client
- [ ] MVVM setup: `ViewModels/` folder, base `ObservableObject` from CommunityToolkit
- [ ] NuGet: add `CommunityToolkit.Mvvm`, `ICSharpCode.AvalonEdit` to DataOps.csproj

#### 1.1 Database creation & schema management
> Files: `GogoFix.DataOps/Views/DbManagementPage.xaml` + `ViewModels/DbManagementViewModel.cs`

- [ ] **SQLite panel:**
  - "Select DB File" button — file picker to choose/create .db file path
  - "Create / Rebuild DB" button → calls `SqliteSchemaInitializer.InitializeAsync()`, shows progress (27 files, progress bar)
  - "Drop All Tables" button (with ⚠ confirmation dialog)
  - Display: current DB path, schema version, table count, file size
  - Table list with row counts
- [ ] **Supabase panel:**
  - Connection config inputs (URL, anon key, service key) — save to appsettings.json
  - "Test Connection" button → `SupabaseClientManager.IsConnected()`
  - "View Cloud Schema" → list tables via Supabase, show table names + row counts
  - "Execute SQL File" → pick a `Supabase SQL/*.sql` file, push to Supabase (via raw SQL execution)
  - "Execute All SQL Files" → batch execute all 26 files in order, progress bar

#### 1.2 Data browser & CRUD
> Files: `GogoFix.DataOps/Views/DataBrowserPage.xaml` + `ViewModels/DataBrowserViewModel.cs`

- [ ] **Left panel: table list**
  - TreeView: "Local SQLite" and "Supabase Cloud" as root nodes, tables as children
  - Click table → load data in right panel
  - Show row count badge per table
- [ ] **Right panel: data grid**
  - `DataGrid` with auto-generated columns from query result
  - Pagination controls (page size selector: 50/100/500, prev/next)
  - Column header click → sort ASC/DESC
  - Filter row: text input per column → WHERE LIKE filter
- [ ] **CRUD operations:**
  - "Add Row" button → empty row in grid, fill in values, click Save
  - Double-click cell → inline edit, click Save to commit UPDATE
  - "Delete Row" button → soft delete (set deleted_at) with confirmation
  - "Hard Delete" option (for testing/cleanup) with double confirmation
- [ ] **JSON field handling:**
  - Detect columns containing JSON (by name convention: `*_json`, `attribute`, `payload_json`, or `CHECK json_valid` columns)
  - Click JSON cell → popup JSON editor with syntax highlighting + validation
  - Format/minify toggle

#### 1.3 Historical data migration (CellSmart/CellPoint → GogoFix)
> Files: `GogoFix.DataOps/Views/ImportExportPage.xaml` (integrated into Import/Export page)
> See also: "Historical Transaction Data Migration Pipeline" section above

- [x] Create `historical_transaction_line` table in LocalSchema.sql + Supabase SQL (file 28)
- [ ] CSV import wizard: select store → select CSV file → preview → import into `historical_transaction_line`
- [ ] Validation: date range, duplicate detection (by store + ID + time), column format checks
- [ ] Historical data browser: query/filter/search past transactions by store, date range, customer, product
- [ ] Future: raw data converter tool (Level 1 → Level 2 automation for CellPoint exports)

#### 1.4 Import / Export (general)
> Files: `GogoFix.DataOps/Views/ImportExportPage.xaml` + `ViewModels/ImportExportViewModel.cs`

- [ ] **CSV Export:**
  - Select source: table name or custom SQL query
  - Select target: file save dialog (.csv)
  - Options: delimiter (comma/tab/semicolon), include headers, encoding (UTF-8/UTF-8 BOM)
  - Progress bar for large exports
- [ ] **CSV Import:**
  - Select source CSV file
  - Select target SQLite table
  - Column mapping UI: auto-match by header name, manual override dropdown
  - Preview first 10 rows before import
  - Options: skip errors / abort on error, batch size
  - Import progress + result summary (inserted, skipped, errors)
- [ ] **JSON Export/Import:**
  - Export: table → JSON array file (one file per table or all tables in one)
  - Import: JSON file → table (same mapping UI as CSV)
- [ ] **Test data seeding:**
  - "Seed Store" button → insert sample data for one store:
    - 3 stores (decarie, marcel, store3)
    - 5 users with different permission templates
    - 50 products across categories (phones, accessories, services, misc)
    - 10 suppliers
    - 20 customers
    - Sample serialized items (10 phones with IMEI)
  - Uses realistic French/English data (Montreal-area addresses, common phone brands)

#### 1.5 Sync testing & debugging
> Files: `GogoFix.DataOps/Views/SyncMonitorPage.xaml` + `ViewModels/SyncMonitorViewModel.cs`

- [ ] **Outbox panel:**
  - DataGrid: list sync_outbox rows (event_id, event_type, status, created_at, last_error)
  - Filter by status (pending/acted/error)
  - "Push All Pending" button → manually trigger `SyncOutboxSender.ProcessPendingAsync()`
  - "Retry Errors" button → reset error rows to pending, re-push
  - "View Payload" → JSON popup for selected row
- [ ] **Inbox panel:**
  - DataGrid: list sync_inbox rows (event_id, change_id, event_type, applied_at)
  - "Pull from Cloud" button → manually trigger `SyncInboxPoller.PollAsync()`
  - "Apply Pending" button → apply un-applied inbox items
  - Current checkpoint display (last change_id processed)
- [ ] **Sync status:**
  - Live indicator: Online/Offline/Syncing/Error
  - Last sync timestamp
  - Pending outbox count, unapplied inbox count
  - "Start Auto-Sync" / "Stop Auto-Sync" toggle (starts `SyncBackgroundService`)

#### 1.6 Data migration & cleanup utilities
> Files: `GogoFix.DataOps/Views/MigrationPage.xaml` + `ViewModels/MigrationViewModel.cs`

- [ ] **FK integrity check:**
  - Scan all foreign key relationships, report orphaned rows
  - Option to delete orphaned rows or list them for manual review
- [ ] **Store data clone:**
  - Select source store_id → clone all store-scoped data with new store_id
  - Useful for creating test environments
- [ ] **Bulk operations:**
  - "Clear All Data" (truncate all tables, keep schema) with confirmation
  - "Reset Sync State" (clear outbox + inbox + checkpoint)
  - "Recount Row Totals" (recalculate cached counts if any)

#### 1.7 Query console
> Files: `GogoFix.DataOps/Views/QueryConsolePage.xaml` + `ViewModels/QueryConsoleViewModel.cs`

- [ ] **SQL editor:**
  - AvalonEdit-based editor with SQL syntax highlighting
  - Target selector: "Local SQLite" or "Supabase Cloud" dropdown
  - "Execute" button (or Ctrl+Enter) → run query
  - "Execute Selected" → run highlighted portion only
- [ ] **Results panel:**
  - DataGrid for SELECT results (same as Data Browser grid)
  - Text output for non-SELECT (rows affected, execution time)
  - Error display with line number highlighting
- [ ] **Query management:**
  - Query history (last 50 queries, stored in appsettings.json or separate file)
  - "Save Query" → name + SQL, stored locally
  - "Load Query" → pick from saved list
  - Preset queries dropdown: common useful queries (e.g., "active products by store", "recent transactions", "sync status summary")

---

### Phase 2: GogoFix POS — MVP Core
> Minimum viable POS for in-store trial: open shift → sell → print receipt → close shift.

- [ ] **2.1 Login & session**
  - User login screen (local SQLite auth, offline-capable)
  - Store selection (multi-store user support)
  - Device registration (device_list)
- [ ] **2.2 Shift management**
  - Open batch / open shift (with opening cash amount)
  - Close shift (closing cash, cash variance calculation)
  - Close batch (end of day)
  - Shift summary report
- [ ] **2.3 Product lookup**
  - Search by item_name, UPC barcode, category
  - Scanner input support (barcode gun → search field)
  - Product detail view (price, cost, stock level, variants)
  - Serialized item lookup by serial/IMEI
- [ ] **2.4 Sales transaction flow**
  - Add items to cart (tracked, untracked, serialized, service)
  - Quantity adjustment, line discount, line removal
  - Customer attach (search/create customer)
  - Payment screen (cash, credit, debit, balance — split payment)
  - Transaction total / tax / profit auto-calculation (with CHECK constraint validation)
  - Commit transaction → write transaction_list + transaction_line_list + inventory deduction
  - Generate display_no (human-readable receipt number)
- [ ] **2.5 Receipt printing**
  - Receipt template (store header, items, totals, tax breakdown, footer)
  - ESC/POS thermal printer integration
  - Cash drawer open command on cash payment
  - Reprint receipt from transaction history
- [ ] **2.6 Basic inventory view (read-only in MVP)**
  - Store inventory list (stock levels per item)
  - Low stock alerts
  - Serialized item list with status

---

### Phase 3: POS — Extended Features
> After MVP is stable in-store, add remaining business modules.

- [ ] **3.1 Inventory adjustment**
  - Manual stock count / adjustment (tracked + untracked)
  - Adjustment reason / notes
  - store_inventory_adjustment_list + line_list records
- [ ] **3.2 Serialized item lifecycle**
  - Full serialized_event_list tracking (purchase, sell, return, transfer, lost, etc.)
  - Status change UI with event logging
  - Serial number edit with audit trail
- [ ] **3.3 Purchase orders**
  - Create PO to supplier
  - Receive PO → update inventory (tracked qty, serialized units)
  - PO line matching (ordered vs received)
- [ ] **3.4 Inter-store transfers**
  - Create transfer request (source store)
  - Confirm receipt (target store)
  - Transfer line items (tracked/untracked/serialized)
- [ ] **3.5 Repair ticket system**
  - Create repair ticket (customer device info, issue description)
  - Assign technician
  - Status lifecycle (pending → completed → paid → cancelled)
  - Link repair completion to payment transaction
  - Repair-specific receipt / work order print
- [ ] **3.6 Customer management**
  - Customer CRUD (name, phone, email, notes)
  - Customer balance tracking
  - Transaction history per customer
- [ ] **3.7 Refund & exchange**
  - Refund flow (full/partial, back to original payment method or balance)
  - Exchange flow (return old + sell new in one transaction)
  - Related transaction linking (related_transaction_id)
- [ ] **3.8 Reports & analytics**
  - Daily sales summary (by shift, by batch)
  - Sales by category / product
  - Inventory valuation report
  - Profit margin analysis
  - Cash flow reconciliation

---

### Phase 4: Multi-Store Sync & Deployment
> Make the system reliably work across 3 stores.

- [ ] **4.1 Sync hardening**
  - Full Outbox→Cloud→Inbox round-trip testing across 2+ stores
  - Network failure recovery testing
  - Conflict resolution for concurrent edits (customer, inventory)
  - Sync status indicator in POS UI (online/offline/syncing/error)
- [ ] **4.2 Deployment**
  - Installer / update mechanism (ClickOnce or MSIX)
  - Per-store SQLite DB provisioning
  - Supabase project setup guide
  - Config file per store/device
- [ ] **4.3 User & permission management**
  - User CRUD (admin function)
  - Rights template assignment per store
  - Permission enforcement in POS UI (hide/disable based on rights)

---

### Phase 5: Future / Post-Launch
> Not in current scope, but documented for planning.

- [ ] **5.1 Mobile web companion**
  - QR code login from POS
  - Photo capture for repair tickets
  - Stocktaking assistance (scan + count)
- [ ] **5.2 Web admin dashboard**
  - Cross-store reports
  - Remote inventory management
  - Shared Blazor/Razor components with POS
- [ ] **5.3 B2B web portal**
  - Product catalog for wholesale buyers
  - Online ordering
- [ ] **5.4 Store demand system**
  - Staff demand submission
  - Manager review workflow
- [ ] **5.5 Advanced features**
  - Label printing (barcode/price tags)
  - Customer loyalty / points system
  - Multi-language UI switching (FR/EN)
