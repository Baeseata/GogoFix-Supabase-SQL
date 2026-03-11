-- Local SQLite version of 17_store_transfer_list.sql
-- Source: Supabase SQL/17_cloud_store_transfer_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_transfer_list (


  -- Auto-increment primary key, starting from 1
  -- 全局自增主键，从 1 开始
  store_transfer_id integer PRIMARY KEY AUTOINCREMENT,

  -- Source store (sender), FK to store_list
  -- 调出门店（发货方），外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Target store (receiver), FK to store_list
  -- 调入门店（收货方），外键指向 store_list
  target_store_id text NOT NULL REFERENCES store_list(store_id),

  -- Employee who created the transfer, FK to user_list
  -- 创建调拨单的员工，外键指向 user_list
  created_by_user_id integer NOT NULL REFERENCES user_list(user_id),

  -- Employee who confirmed receipt; NULL = not yet confirmed (still in transit)
  -- 确认收货的员工；NULL 表示尚未确认（仍在途中）
  confirmed_by_user_id integer DEFAULT NULL REFERENCES user_list(user_id),

  -- Timestamp when receipt was confirmed; NULL = not yet confirmed
  -- confirmed_at and confirmed_by_user_id must both be NULL or both be set (see CHECK below)
  -- 确认收货的时间；NULL 表示尚未确认
  -- confirmed_at 和 confirmed_by_user_id 应同时为空或同时有值（见下方 CHECK）
  confirmed_at text DEFAULT NULL,

  -- Total cost of all items in this transfer (calculated by client)
  -- 调拨总成本（客户端计算后传入）
  cost_total numeric NOT NULL DEFAULT 0,

  -- Total retail value of all items in this transfer (calculated by client)
  -- 调拨总零售价值（客户端计算后传入）
  price_total numeric NOT NULL DEFAULT 0,

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- CHECK: cannot transfer to yourself (source and target must be different stores)
  -- 约束：不能自己调给自己（发货方和收货方必须是不同门店）
  CONSTRAINT chk_store_transfer_list_not_self
    CHECK (store_id != target_store_id),

  -- CHECK: confirmation consistency — confirmed_by_user_id and confirmed_at must both be NULL or both be set
  -- 约束：确认状态一致性 — confirmed_by_user_id 和 confirmed_at 应同时为空或同时有值
  CONSTRAINT chk_store_transfer_list_confirm_consistency
    CHECK (
      (confirmed_by_user_id IS NULL AND confirmed_at IS NULL)
      OR
      (confirmed_by_user_id IS NOT NULL AND confirmed_at IS NOT NULL)
    )
);
