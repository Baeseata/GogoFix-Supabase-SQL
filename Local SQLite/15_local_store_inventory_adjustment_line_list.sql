-- Local SQLite version of 15_store_inventory_adjustment_line_list.sql
-- Source: Supabase SQL/15_cloud_store_inventory_adjustment_line_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_inventory_adjustment_line_list (


  -- Auto-increment primary key, starting from 1
  -- 全局自增主键，从 1 开始
  line_id integer PRIMARY KEY AUTOINCREMENT,

  -- Store ID (matches header; also part of composite FK to store_inventory_list)
  -- 门店 ID（与主表一致；同时参与 store_inventory_list 复合外键）
  store_id text NOT NULL,

  -- Parent adjustment, FK to store_inventory_adjustment_list
  -- 所属盘点单，外键指向 store_inventory_adjustment_list
  adjustment_id integer NOT NULL REFERENCES store_inventory_adjustment_list(adjustment_id),

  -- Product reference (part of composite FK to store_inventory_list)
  -- 商品引用（与 store_id 一起组成 store_inventory_list 复合外键）
  unique_id integer NOT NULL,

  -- Quantity change for tracked items: new_qty − old_qty
  -- May be 0 (confirming count is correct), may be negative
  -- Must be NULL for untracked / service items
  -- tracked 商品的数量变动：新数量 − 旧数量
  -- 允许为 0（表示盘点确认数量无误）、允许为负
  -- untracked / service 商品应为 NULL
  qty_delta integer DEFAULT NULL,

  -- Post-adjustment quantity snapshot for tracked items
  -- Recorded by the client at adjustment time for audit purposes
  -- tracked 商品调整后的库存数量快照
  -- 由客户端在调整时记录，方便审计查询
  qty_after integer DEFAULT NULL,

  -- Post-adjustment stock level for untracked items (the new fuzzy level)
  -- untracked 商品调整后的模糊库存档位（新档位值）
  stock_bucket_after text DEFAULT NULL,

  -- Cost per unit snapshot at adjustment time (read from store_inventory_list.cost)
  -- 调整时的单位成本快照（从 store_inventory_list.cost 读取）
  cost_per_unit numeric DEFAULT NULL,

  -- Composite FK to store_inventory_list (store_id, unique_id)
  -- 复合外键指向 store_inventory_list (store_id, unique_id)
  CONSTRAINT fk_adjustment_line_list_store_inventory_list
    FOREIGN KEY (store_id, unique_id)
    REFERENCES store_inventory_list (store_id, unique_id),

  -- Mutual exclusion: qty_delta and stock_bucket_after cannot both be non-NULL
  -- 互斥约束：qty_delta 和 stock_bucket_after 不能同时有值
  CONSTRAINT chk_adjustment_line_list_qty_bucket_mutex
    CHECK (NOT (qty_delta IS NOT NULL AND stock_bucket_after IS NOT NULL))
);
