-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 10 · batch_list — Business day batch table
-- 文件 10 · batch_list — 营业批次表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (store_id FK)
--   03_user_list  (opened_by_user_id / closed_by_user_id FK)
-- Dependents / 被依赖:
--   11_shift_list (store_id, batch_id composite FK)
-- Shared components created here / 本文件创建的共享组件:
--   Function public.assign_batch_id_per_store() — this table only
-- =============================================
-- Each store's business day batch record. Only one open batch per store at a time.
-- No soft delete: batches are permanent historical records; once closed, they are kept forever.
-- ─────────────────────────────────────────────
-- 每个门店的营业批次记录。同一门店同一时间只能有一个 open batch。
-- 不支持软删除：批次是永久历史记录，关闭后永久保留。
-- =============================================

-- =============================================
-- Function: assign_batch_id_per_store()
-- 函数：assign_batch_id_per_store()
-- =============================================
-- Auto-assigns batch_id per store, starting from 1 and incrementing.
-- Uses advisory lock (namespace 1002) to prevent race conditions.
-- ─────────────────────────────────────────────
-- 按门店自动分配 batch_id，从 1 开始递增。
-- 使用咨询锁（命名空间 1002）防止并发冲突。
-- Advisory lock 1002: see allocation table in 06_mother_inventory_list
-- 咨询锁 1002：分配总表见 06_mother_inventory_list
-- =============================================
CREATE OR REPLACE FUNCTION public.assign_batch_id_per_store()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Variable legend / 变量说明:
  --   next_bid = next batch_id to assign for this store / 本门店下要分配的下一个 batch_id
  next_bid int;
BEGIN
  -- Guard: store_id must not be null / 防御性检查：store_id 不能为空
  IF NEW.store_id IS NULL THEN
    RAISE EXCEPTION 'store_id cannot be null';
  END IF;

  -- Advisory lock namespace 1002, keyed by store_id
  -- 咨询锁命名空间 1002，按 store_id 锁定
  PERFORM pg_advisory_xact_lock(1002, hashtext(NEW.store_id));

  SELECT COALESCE(MAX(batch_id), 0) + 1
    INTO next_bid
  FROM public.batch_list
  WHERE store_id = NEW.store_id;

  NEW.batch_id := next_bid;
  RETURN NEW;
END;
$$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.batch_list (

  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Batch number, auto-increments per store starting from 1 (assigned by trigger)
  -- 批次编号，同一门店内从 1 开始自动递增（由触发器分配）
  batch_id integer NOT NULL,

  -- Whether this batch is currently open (true = open, false = closed)
  -- 批次是否处于开启状态（true = 开启，false = 已关闭）
  is_open boolean NOT NULL DEFAULT true,

  -- Timestamp when the batch was opened
  -- 批次开启时间
  opened_at timestamptz NOT NULL DEFAULT now(),

  -- Timestamp when the batch was closed; must be NULL while open
  -- 批次关闭时间；开启状态下应为 NULL
  closed_at timestamptz DEFAULT NULL,

  -- Employee who opened this batch, FK to user_list
  -- 开启批次的员工，外键指向 user_list
  opened_by_user_id integer REFERENCES public.user_list(user_id),

  -- Employee who closed this batch, FK to user_list
  -- 关闭批次的员工，外键指向 user_list
  closed_by_user_id integer REFERENCES public.user_list(user_id),

  -- Optional notes / comments about this batch
  -- 备注（可选）
  note text DEFAULT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

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

-- =============================================
-- Trigger: auto-assign batch_id on INSERT
-- 触发器：INSERT 时自动分配 batch_id
-- =============================================
DROP TRIGGER IF EXISTS trg_batch_list_assign_id ON public.batch_list;
CREATE TRIGGER trg_batch_list_assign_id
BEFORE INSERT ON public.batch_list
FOR EACH ROW
EXECUTE FUNCTION public.assign_batch_id_per_store();

-- =============================================
-- Partial unique index: only one open batch per store at a time
-- 部分唯一索引：同一门店同一时间只能有一个 open batch
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_batch_list_one_open_per_store
  ON public.batch_list (store_id)
  WHERE is_open = true;

-- =============================================
-- Index: look up recent batches for a store (ordered by open time descending)
-- 索引：查询某门店的最近批次（按开启时间倒序）
-- =============================================
CREATE INDEX IF NOT EXISTS idx_batch_list_store_opened_at
  ON public.batch_list (store_id, opened_at DESC);

-- =============================================
-- Trigger: auto-refresh updated_at (reuses set_updated_at() from file 03)
-- 触发器：自动刷新 updated_at（复用 03_user_list 中的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_batch_list_updated_at ON public.batch_list;
CREATE TRIGGER trg_batch_list_updated_at
BEFORE UPDATE ON public.batch_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
