-- Local SQLite version of 14_store_inventory_adjustment_list.sql
-- Source: Supabase SQL/14_cloud_store_inventory_adjustment_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_inventory_adjustment_list (


  -- Auto-increment primary key, starting from 1
  -- 全局自增主键，从 1 开始
  adjustment_id integer PRIMARY KEY AUTOINCREMENT,

  -- Store where this adjustment was performed, FK to store_list
  -- 执行盘点的门店，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Employee who performed this adjustment, FK to user_list
  -- 执行盘点的员工，外键指向 user_list
  user_id integer NOT NULL REFERENCES user_list(user_id),

  -- Total cost impact of this adjustment (sum of all line item cost deltas)
  -- Calculated by the client and passed in; the DB does NOT auto-aggregate
  -- 本次盘点造成的总成本变动（所有明细行的成本差额汇总）
  -- 由客户端计算后传入，数据库不做自动汇总
  cost_delta numeric NOT NULL DEFAULT 0,

  -- Reason / description for this adjustment (e.g., "Monthly stocktake", "Damage write-off")
  -- 盘点备注/原因说明（如"月度盘点"、"损坏报废"）
  description text DEFAULT NULL,

  -- Creation timestamp (server time, since this is an online-only operation)
  -- 创建时间（服务端时间，因为此操作仅在联网时进行）
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP
);
