-- Local SQLite version of 23_repair_ticket_line_list.sql
-- Source: Supabase SQL/23_cloud_repair_ticket_line_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS repair_ticket_line_list (


  -- 客户端生成 UUIDv7
  repair_ticket_line_id text PRIMARY KEY,

  -- 所属工单
  repair_ticket_id text NOT NULL REFERENCES repair_ticket_list(repair_ticket_id),

  -- 门店（冗余，方便离线同步按门店筛选）
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- 关联母表商品（可选，手动录入项目时为 NULL）
  unique_id integer REFERENCES mother_inventory_list(unique_id),

  -- 项目名称（快照 / 手动录入）
  item_name text NOT NULL,

  -- 数量
  qty integer NOT NULL DEFAULT 1 CHECK (qty > 0),

  -- 成本与售价，允许后续补填
  unit_cost numeric,
  unit_price numeric,

  -- 备注
  note text,

  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at text,
  synced_at text
);
