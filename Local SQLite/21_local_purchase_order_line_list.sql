-- Local SQLite version of 21_purchase_order_line_list.sql
-- Source: Supabase SQL/21_cloud_purchase_order_line_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS purchase_order_line_list (


  -- 全局自增主键，从 1 开始
  purchase_order_line_id integer PRIMARY KEY AUTOINCREMENT,

  -- 门店 ID（用于复合外键指向主表）
  store_id text NOT NULL,

  -- 所属采购单
  purchase_order_id integer NOT NULL,

  -- 关联母表商品
  unique_id integer NOT NULL REFERENCES mother_inventory_list(unique_id),

  -- 序列号商品关联：serialized 商品应有值，非 serialized 商品应为 NULL
  unit_id integer DEFAULT NULL REFERENCES store_serialized_list(unit_id),

  -- 商品名称快照
  item_name text NOT NULL,

  -- 单位采购成本
  unit_cost numeric NOT NULL DEFAULT 0,

  -- 采购数量：serialized 商品应为 1
  qty integer NOT NULL,

  -- 序列号文本：仅 serialized 商品有值
  serial text DEFAULT NULL,

  -- 备注
  note text DEFAULT NULL,

  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- 软删除时间戳
  deleted_at text DEFAULT NULL,

  -- 复合外键：指向 purchase_order_list(store_id, purchase_order_id)
  CONSTRAINT purchase_order_line_fk_order
    FOREIGN KEY (store_id, purchase_order_id)
    REFERENCES purchase_order_list (store_id, purchase_order_id),

  -- 数量应大于 0
  CONSTRAINT purchase_order_line_qty_positive
    CHECK (qty > 0)
);
