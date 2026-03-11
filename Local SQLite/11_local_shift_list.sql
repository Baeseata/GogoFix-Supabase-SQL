-- Local SQLite version of 11_shift_list.sql
-- Source: Supabase SQL/11_cloud_shift_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS shift_list (


  -- Store ID (part of composite PK and FK to batch_list)
  -- 门店 ID（联合主键的一部分，同时参与 batch_list 外键）
  store_id text NOT NULL,

  -- Batch number this shift belongs to (FK to batch_list via composite key)
  -- 所属批次编号（通过复合键外键指向 batch_list）
  batch_id integer NOT NULL,

  -- Shift number, globally incremented per store (NOT reset per batch), assigned by trigger
  -- 班次编号，门店内全局递增（不随 batch 重置），由触发器分配
  shift_id integer NOT NULL,

  -- Employee on this shift, FK to user_list
  -- 当班员工，外键指向 user_list
  user_id integer REFERENCES user_list(user_id),

  -- Device ID used for this shift (e.g., a specific POS terminal)
  -- 本班次使用的设备 ID（如某台 POS 终端）
  device_id text DEFAULT NULL,

  -- Whether this shift is currently open (true = open, false = closed)
  -- 班次是否处于开启状态（true = 开启，false = 已关闭）
  is_open integer NOT NULL DEFAULT 1,

  -- Timestamp when the shift was opened
  -- 班次开启时间
  opened_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Timestamp when the shift was closed; must be NULL while open
  -- 班次关闭时间；开启状态下应为 NULL
  closed_at text DEFAULT NULL,

  -- Starting cash in the drawer when the shift opened
  -- 开班时的现金底数
  opening_cash numeric NOT NULL DEFAULT 0,

  -- Actual cash counted when the shift closed; may be NULL while still open
  -- 关班时的现金实点数；开班状态下允许为 NULL
  closing_cash numeric DEFAULT NULL,

  -- Optional notes / comments about this shift
  -- 备注（可选）
  note text DEFAULT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Composite PK: (store_id, batch_id, shift_id)
  -- 三列联合主键
  CONSTRAINT shift_list_pkey PRIMARY KEY (store_id, batch_id, shift_id),

  -- CHECK: shift_id must be a positive integer (>= 1)
  -- 约束：shift_id 应为正整数（>= 1）
  CONSTRAINT chk_shift_list_shift_id_positive CHECK (shift_id > 0),

  -- CHECK: open/close consistency — if open, closed_at must be NULL; if closed, closed_at must be set
  -- 约束：开关状态一致性 — 开启时 closed_at 应为空，关闭时应有值
  CONSTRAINT chk_shift_list_open_close_consistency CHECK (
    (is_open = true  AND closed_at IS NULL)
    OR
    (is_open = false AND closed_at IS NOT NULL)
  ),

  -- Composite FK to batch_list (store_id, batch_id)
  -- 复合外键指向 batch_list (store_id, batch_id)
  CONSTRAINT fk_shift_list_batch_list
    FOREIGN KEY (store_id, batch_id)
    REFERENCES batch_list (store_id, batch_id)
);
