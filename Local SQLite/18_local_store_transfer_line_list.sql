-- Local SQLite version of 18_store_transfer_line_list.sql
-- Source: Supabase SQL/18_cloud_store_transfer_line_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_transfer_line_list (


  -- Auto-increment primary key, starting from 1
  -- 全局自增主键，从 1 开始
  line_id integer PRIMARY KEY AUTOINCREMENT,

  -- Parent transfer, FK to store_transfer_list
  -- 所属调拨单，外键指向 store_transfer_list
  store_transfer_id integer NOT NULL REFERENCES store_transfer_list(store_transfer_id),

  -- Product reference, FK to mother_inventory_list
  -- 商品引用，外键指向 mother_inventory_list
  unique_id integer NOT NULL REFERENCES mother_inventory_list(unique_id),

  -- Serialized unit reference: required for serialized items, must be NULL for non-serialized
  -- Consistency validated by trigger (see below)
  -- 序列号单件引用：serialized 商品必填，非 serialized 商品应为 NULL
  -- 一致性由触发器校验（见下方）
  unit_id integer DEFAULT NULL REFERENCES store_serialized_list(unit_id),

  -- Product name snapshot (denormalized, copied by client at transfer time)
  -- 商品名称快照（冗余字段，由客户端在调拨时复制）
  item_name text NOT NULL,

  -- Cost per unit snapshot at transfer time
  -- 调拨时的单位成本快照
  cost_per_unit numeric NOT NULL DEFAULT 0,

  -- Retail price per unit snapshot at transfer time
  -- 调拨时的单位零售价快照
  price_per_unit numeric NOT NULL DEFAULT 0,

  -- Transfer quantity: must be > 0; serialized items must be 1
  -- 调拨数量：必须大于 0；serialized 商品必须为 1
  qty integer NOT NULL,

  -- Serial number text: only for serialized items (copied from store_serialized_list)
  -- 序列号文本：仅 serialized 商品有值（从 store_serialized_list 复制）
  serial text DEFAULT NULL,

  -- CHECK: quantity must be positive (no zero or negative transfers)
  -- 约束：数量必须为正数（调拨不允许 0 或负数）
  CONSTRAINT chk_store_transfer_line_list_qty_positive
    CHECK (qty > 0)
);
