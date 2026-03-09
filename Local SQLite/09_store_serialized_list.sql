-- Local SQLite version of 09_store_serialized_list.sql
-- Source: Supabase SQL/09_store_serialized_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_serialized_list (


  -- Auto-increment PK for each physical unit; starting from 1
  -- 每件实物的自增主键，从 1 开始
  unit_id integer PRIMARY KEY AUTOINCREMENT,

  -- Store ID, FK to store_list (the store currently holding this unit)
  -- 门店 ID，外键指向 store_list（当前持有该单件的门店）
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Globally unique serial number (e.g., IMEI, SN); NEVER reused even after void/soft-delete
  -- 全局唯一序列号（如 IMEI、SN）；即使作废/软删除后仍永久占位，不可复用
  serial text NOT NULL,

  -- Product reference, FK to mother_inventory_list (must be inventory_mode = 'serialized')
  -- 商品引用，外键指向 mother_inventory_list（必须是 inventory_mode = 'serialized'）
  unique_id int NOT NULL REFERENCES mother_inventory_list(unique_id),

  -- Extra attributes for this unit as free-form JSONB (e.g., color, capacity, condition)
  -- Example: {"color": "Space Black", "capacity": "256GB", "condition": "A+"}
  -- 单件额外属性，自由格式 JSONB（如颜色、容量、成色等）
  -- 例如：{"color": "Space Black", "capacity": "256GB", "condition": "A+"}
  attribute text DEFAULT NULL,

  -- Unit cost; on INSERT, if NULL, auto-inherited from mother table default_cost
  -- 单件成本；INSERT 时若为空，自动从母表 default_cost 继承；之后独立更新
  cost numeric DEFAULT NULL,

  -- Unit retail price; on INSERT, if NULL, auto-inherited from mother table default_price
  -- 单件零售价；INSERT 时若为空，自动从母表 default_price 继承；之后独立更新
  price numeric DEFAULT NULL,

  -- Minimum suggested price for sales staff; advisory only
  -- 前台最低报价指导价，仅供参考
  last_price numeric DEFAULT NULL,

  -- Current lifecycle status of this unit (see serialized_status ENUM above)
  -- 单件当前业务状态（参见上方 serialized_status 枚举）
  status text NOT NULL DEFAULT 'in_stock' CHECK (status IN ('in_stock','in_transit','sold','repair','lost','wasted','void')),

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Soft delete timestamp; NULL = active, non-NULL = deleted
  -- Note: even after soft delete, the serial is still reserved (global unique constraint has no WHERE filter)
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已删除
  -- 注意：软删除后 serial 仍占位，不可复用（全局唯一约束不带 WHERE 条件）
  deleted_at text DEFAULT NULL
);
