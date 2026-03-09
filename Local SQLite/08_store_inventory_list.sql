-- Local SQLite version of 08_store_inventory_list.sql
-- Source: Supabase SQL/08_store_inventory_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_inventory_list (


  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Product reference, FK to mother_inventory_list (NOT item_id, but the true PK unique_id)
  -- 商品引用，外键指向 mother_inventory_list（不是 item_id，而是真正的主键 unique_id）
  unique_id int NOT NULL REFERENCES mother_inventory_list(unique_id),

  -- Exact stock quantity; used ONLY for tracked mode
  -- May be negative: business allows selling below zero to avoid blocking sales due to count errors
  -- Must be NULL for service / untracked modes
  -- 精确库存数量；仅 tracked 模式使用
  -- 允许负数：业务上为避免因库存计数偏差阻碍销售，允许先销售后修正
  -- service / untracked 模式应为 NULL
  qty_on_hand int DEFAULT NULL,

  -- Fuzzy stock level; used ONLY for untracked mode
  -- Must be NULL for service / tracked modes
  -- 模糊库存档位；仅 untracked 模式使用
  -- service / tracked 模式应为 NULL
  stock_bucket text DEFAULT NULL CHECK (stock_bucket IN ('empty','very_few','few','normal','too_much')),

  -- Store-specific cost per unit
  -- On INSERT, if NULL, auto-inherited from mother table default_cost; afterwards updated independently
  -- 门店的实际单位成本
  -- INSERT 时若为空，自动从母表 default_cost 继承；之后独立更新，不随母表变化
  cost numeric DEFAULT NULL,

  -- Store-specific retail price per unit
  -- On INSERT, if NULL, auto-inherited from mother table default_price; afterwards updated independently
  -- 门店的当前零售单价
  -- INSERT 时若为空，自动从母表 default_price 继承；之后独立更新
  price numeric DEFAULT NULL,

  -- Minimum suggested price for sales staff; advisory only, not enforced
  -- 前台最低报价指导价：销售人员可参考作为报价下限，不做强制限制
  last_price numeric DEFAULT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Soft delete timestamp; NULL = active, non-NULL = product removed from this store
  -- Note: before soft-deleting, ensure the mother table inventory_mode hasn't changed incompatibly.
  -- To change mode, soft-delete all store rows first, then modify the mother table.
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示该门店已下架本商品
  -- 注意：软删除前应确保母表 inventory_mode 未发生不兼容的变更。
  -- 若需变更 mode，应先将所有门店的该商品行软删除，再修改母表。
  deleted_at text DEFAULT NULL,

  -- Composite PK: one row per product per store (including soft-deleted rows)
  -- 联合主键：同一门店内，同一 SKU 只能有一行（含软删除行）
  CONSTRAINT store_inventory_list_pkey PRIMARY KEY (store_id, unique_id),

  -- Mutual exclusion: qty_on_hand and stock_bucket cannot both be non-NULL
  -- (DB-level safety net; the trigger also validates this per inventory_mode)
  -- 互斥约束：qty_on_hand 和 stock_bucket 不能同时有值
  -- （数据库层面兜底；触发器也会按 inventory_mode 进行明确校验）
  CONSTRAINT chk_store_inventory_list_qty_bucket_mutex
    CHECK (NOT (qty_on_hand IS NOT NULL AND stock_bucket IS NOT NULL))
);
