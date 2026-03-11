-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- Offline policy: opening a new shift must be done online; offline shift opening is not allowed.
-- 离线策略：开新 shift 必须在线进行；离线状态不允许开 shift。
-- =============================================
-- File 11 · shift_list — Employee shift table
-- 文件 11 · shift_list — 班次表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (store_id FK)
--   03_user_list  (user_id FK)
--   10_batch_list (store_id, batch_id composite FK)
-- Dependents / 被依赖:
--   12_transaction_list (store_id, batch_id, shift_id composite FK)
-- Shared components created here / 本文件创建的共享组件:
--   Function public.assign_shift_id_per_store() — this table only
-- =============================================
-- Each shift belongs to a batch. shift_id is global per store (NOT reset per batch).
-- Only one open shift per device at a time.
-- No soft delete: shifts are permanent historical records.
-- ─────────────────────────────────────────────
-- 每个班次归属于某个 batch。shift_id 在门店内全局递增（不随 batch 重置）。
-- 同一设备同一时间只能有一个 open shift。
-- 不支持软删除：班次是永久历史记录。
-- =============================================

-- =============================================
-- Function: assign_shift_id_per_store()
-- 函数：assign_shift_id_per_store()
-- =============================================
-- Auto-assigns shift_id per store, starting from 1 and incrementing globally (not per batch).
-- Uses advisory lock (namespace 1003) to prevent race conditions.
-- ─────────────────────────────────────────────
-- 按门店自动分配 shift_id，从 1 开始全局递增（不按 batch 重置）。
-- 使用咨询锁（命名空间 1003）防止并发冲突。
-- Advisory lock 1003: see allocation table in 06_mother_inventory_list
-- 咨询锁 1003：分配总表见 06_mother_inventory_list
-- =============================================
CREATE OR REPLACE FUNCTION public.assign_shift_id_per_store()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Variable legend / 变量说明:
  --   next_sid = next shift_id to assign for this store / 本门店下要分配的下一个 shift_id
  next_sid int;
BEGIN
  -- Guard: store_id and batch_id must not be null
  -- 防御性检查：store_id 和 batch_id 不能为空
  IF NEW.store_id IS NULL OR NEW.batch_id IS NULL THEN
    RAISE EXCEPTION 'store_id and batch_id cannot be null';
  END IF;

  -- Advisory lock namespace 1003, keyed by store_id
  -- 咨询锁命名空间 1003，按 store_id 锁定
  PERFORM pg_advisory_xact_lock(1003, hashtext(NEW.store_id));

  SELECT COALESCE(MAX(shift_id), 0) + 1
    INTO next_sid
  FROM public.shift_list
  WHERE store_id = NEW.store_id;

  NEW.shift_id := next_sid;
  RETURN NEW;
END;
$$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.shift_list (

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
  user_id integer REFERENCES public.user_list(user_id),

  -- Device ID used for this shift (e.g., a specific POS terminal)
  -- 本班次使用的设备 ID（如某台 POS 终端）
  device_id text DEFAULT NULL,

  -- Whether this shift is currently open (true = open, false = closed)
  -- 班次是否处于开启状态（true = 开启，false = 已关闭）
  is_open boolean NOT NULL DEFAULT true,

  -- Timestamp when the shift was opened
  -- 班次开启时间
  opened_at timestamptz NOT NULL DEFAULT now(),

  -- Timestamp when the shift was closed; must be NULL while open
  -- 班次关闭时间；开启状态下应为 NULL
  closed_at timestamptz DEFAULT NULL,

  -- Starting cash in the drawer when the shift opened
  -- 开班时的现金底数
  opening_cash numeric(10,2) NOT NULL DEFAULT 0,

  -- Actual cash counted when the shift closed; may be NULL while still open
  -- 关班时的现金实点数；开班状态下允许为 NULL
  closing_cash numeric(10,2) DEFAULT NULL,

  -- Optional notes / comments about this shift
  -- 备注（可选）
  note text DEFAULT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

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
    REFERENCES public.batch_list (store_id, batch_id)
);

-- =============================================
-- Trigger: auto-assign shift_id on INSERT
-- 触发器：INSERT 时自动分配 shift_id
-- =============================================
DROP TRIGGER IF EXISTS trg_shift_list_assign_id ON public.shift_list;
CREATE TRIGGER trg_shift_list_assign_id
BEFORE INSERT ON public.shift_list
FOR EACH ROW
EXECUTE FUNCTION public.assign_shift_id_per_store();

-- =============================================
-- Partial unique index: only one open shift per device at a time (within a store)
-- Records with device_id IS NULL are excluded (allows shifts without a device)
-- ─────────────────────────────────────────────
-- 部分唯一索引：同一设备同一时间只能有一个 open shift（门店内）
-- device_id IS NULL 的记录不参与（允许无设备的班次）
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_shift_list_one_open_per_device
  ON public.shift_list (store_id, device_id)
  WHERE is_open = true AND device_id IS NOT NULL;

-- =============================================
-- Indexes / 索引
-- =============================================

-- Look up recent shifts for a store (ordered by open time descending)
-- 查询某门店的最近班次（按开启时间倒序）
CREATE INDEX IF NOT EXISTS idx_shift_list_store_opened_at
  ON public.shift_list (store_id, opened_at DESC);

-- Look up shifts within a specific batch
-- 查询某个 batch 下的班次
CREATE INDEX IF NOT EXISTS idx_shift_list_batch_opened_at
  ON public.shift_list (store_id, batch_id, opened_at DESC);

-- =============================================
-- Trigger: auto-refresh updated_at (reuses set_updated_at() from file 03)
-- 触发器：自动刷新 updated_at（复用 03_user_list 中的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_shift_list_updated_at ON public.shift_list;
CREATE TRIGGER trg_shift_list_updated_at
BEFORE UPDATE ON public.shift_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
