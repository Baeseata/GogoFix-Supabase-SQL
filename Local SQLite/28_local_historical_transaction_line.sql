-- Local SQLite version of 28_historical_transaction_line.sql
-- Source: Supabase SQL/28_cloud_historical_transaction_line.sql
-- Purpose: stores historical transaction line data imported from legacy POS systems (CellSmart / CellPoint)
-- 用途：存储从旧 POS 系统（CellSmart / CellPoint）导入的历史交易明细数据
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS historical_transaction_line (

  -- Auto-increment surrogate primary key (source IDs are not globally unique across stores)
  -- 自增代理主键（源系统 ID 在跨门店场景下不唯一）
  row_id integer PRIMARY KEY AUTOINCREMENT,

  -- Store that owns this historical record, FK to store_list
  -- 该历史记录所属门店，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Original transaction number from the source POS system (not unique per line — multiple lines share one transaction ID)
  -- 源 POS 系统中的原始交易编号（非逐行唯一 — 同一笔交易的多条明细共享同一个 ID）
  source_id integer NOT NULL,

  -- Transaction timestamp in original format: M-D-YY h:mm AM/PM (e.g., "12-31-25 5:19 PM")
  -- 交易时间，保留原始格式：M-D-YY h:mm AM/PM（如 "12-31-25 5:19 PM"）
  transaction_time text NOT NULL,

  -- Customer name or "Walk-In Customer" for anonymous sales
  -- 客户名称，匿名交易为 "Walk-In Customer"
  customer_name text NOT NULL DEFAULT '',

  -- Customer phone number (may be empty for walk-in customers)
  -- 客户电话号码（散客可能为空）
  phone_number text NOT NULL DEFAULT '',

  -- Product or service name as recorded by the source POS
  -- 源 POS 系统中记录的商品或服务名称
  product_name text NOT NULL,

  -- Invoice type label from source POS (e.g., "Sale", "Invoice", "Inventory Adjustment")
  -- 源 POS 系统中的发票类型标签（如 "Sale"、"Invoice"、"Inventory Adjustment"）
  invoice_type text NOT NULL DEFAULT '',

  -- IMEI or serial number (empty for non-serialized items)
  -- IMEI 或序列号（非序列化商品为空）
  imei_number text NOT NULL DEFAULT '',

  -- Cashier / sales representative name
  -- 收银员 / 销售代表名称
  rep_name text NOT NULL DEFAULT '',

  -- Unit selling price (stored as numeric, $ prefix stripped during import)
  -- 单位售价（以数字存储，导入时去除 $ 前缀）
  unit_price numeric NOT NULL DEFAULT 0,

  -- Discount amount for this line
  -- 该行折扣金额
  discount numeric NOT NULL DEFAULT 0,

  -- Quantity sold
  -- 销售数量
  qty integer NOT NULL DEFAULT 0,

  -- Tax amount for this line
  -- 该行税额
  tax_amount numeric NOT NULL DEFAULT 0,

  -- Extended amount (total including tax for this line)
  -- 含税总额（该行的最终金额）
  ext_amount numeric NOT NULL DEFAULT 0,

  -- Source POS system identifier: "cellsmart", "cellpoint", or "gogofix"
  -- 源 POS 系统标识："cellsmart"、"cellpoint" 或 "gogofix"
  source_pos text NOT NULL DEFAULT 'cellsmart',

  -- =============================================
  -- UNIQUE constraint: prevent duplicate imports of the same line
  -- 唯一约束：防止同一条明细被重复导入
  -- =============================================
  -- A line is considered duplicate if store + source transaction ID + time + product name all match
  -- 当 门店 + 源交易号 + 时间 + 商品名称 全部匹配时，视为重复记录
  CONSTRAINT uq_historical_line_dedup
    UNIQUE (store_id, source_id, transaction_time, product_name)
);

-- =============================================
-- Indexes / 索引
-- =============================================

-- Primary query: list historical transactions for a store within a date range
-- 主要查询：列出某门店在某时间范围内的历史交易
CREATE INDEX IF NOT EXISTS idx_historical_line_store_time
  ON historical_transaction_line (store_id, transaction_time);

-- Look up all lines for a specific source transaction
-- 查询某笔源交易的所有明细行
CREATE INDEX IF NOT EXISTS idx_historical_line_source_id
  ON historical_transaction_line (store_id, source_id);

-- Search by customer name
-- 按客户名称搜索
CREATE INDEX IF NOT EXISTS idx_historical_line_customer
  ON historical_transaction_line (store_id, customer_name);

-- Search by product name
-- 按商品名称搜索
CREATE INDEX IF NOT EXISTS idx_historical_line_product
  ON historical_transaction_line (product_name);
