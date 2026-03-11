-- Local SQLite version of 10_batch_list.sql
-- Source: Supabase SQL/10_cloud_batch_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS batch_list (


  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Batch number, auto-increments per store starting from 1 (assigned by trigger)
  -- 批次编号，同一门店内从 1 开始自动递增（由触发器分配）
  batch_id integer NOT NULL,

  -- Whether this batch is currently open (true = open, false = closed)
  -- 批次是否处于开启状态（true = 开启，false = 已关闭）
  is_open integer NOT NULL DEFAULT 1,

  -- Timestamp when the batch was opened
  -- 批次开启时间
  opened_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Timestamp when the batch was closed; must be NULL while open
  -- 批次关闭时间；开启状态下应为 NULL
  closed_at text DEFAULT NULL,

  -- Employee who opened this batch, FK to user_list
  -- 开启批次的员工，外键指向 user_list
  opened_by_user_id integer REFERENCES user_list(user_id),

  -- Employee who closed this batch, FK to user_list
  -- 关闭批次的员工，外键指向 user_list
  closed_by_user_id integer REFERENCES user_list(user_id),

  -- Optional notes / comments about this batch
  -- 备注（可选）
  note text DEFAULT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Composite PK: (store_id, batch_id) uniquely identifies a batch
  -- 联合主键：(store_id, batch_id) 唯一标识一个批次
  CONSTRAINT batch_list_pkey PRIMARY KEY (store_id, batch_id),

  -- CHECK: batch_id must be a positive integer (>= 1)
  -- 约束：batch_id 应为正整数（>= 1）
  CONSTRAINT chk_batch_list_batch_id_positive CHECK (batch_id > 0),

  -- CHECK: open/close consistency — if open, closed_at must be NULL; if closed, closed_at must be set
  -- 约束：开关状态一致性 — 开启时 closed_at 应为空，关闭时应有值
  CONSTRAINT chk_batch_list_open_close_consistency CHECK (
    (is_open = true  AND closed_at IS NULL)
    OR
    (is_open = false AND closed_at IS NOT NULL)
  )
);
