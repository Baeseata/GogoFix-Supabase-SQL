-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 24 · store_demand_list — Store demand quick-capture table
-- 文件 24 · store_demand_list — 门店需求快速记录表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (store_id FK)
--   03_user_list  (created_by / reviewed_by FK)
-- Dependents / 被依赖:
--   (none)
-- Shared components created here / 本文件创建的共享组件:
--   ENUM public.demand_status
--   Function public.assign_demand_id_per_store()
-- =============================================
-- Purpose:
--   Lightweight shared table for quickly recording daily demands/requests.
--   One row can contain one or multiple demand items in plain text.
-- ─────────────────────────────────────────────
-- 目的：
--   提供给全员快速记录需求的轻量表。
--   一行可记录一个或多个需求项（纯文本）。
-- =============================================

-- =============================================
-- ENUM: demand_status — demand review workflow state
-- 枚举：demand_status — 需求审核流程状态
-- =============================================
DO $$
BEGIN
  CREATE TYPE public.demand_status AS ENUM (
    'pending', 'processing', 'rejected', 'done'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Function: assign_demand_id_per_store()
-- 函数：assign_demand_id_per_store()
-- =============================================
-- Auto-assigns demand_id per store starting from 1.
-- Uses advisory lock namespace 1010 to avoid concurrent conflicts.
-- ─────────────────────────────────────────────
-- 按门店自动分配 demand_id，从 1 开始递增。
-- 使用咨询锁命名空间 1010 防止并发冲突。
-- =============================================
CREATE OR REPLACE FUNCTION public.assign_demand_id_per_store()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_demand_id integer;
BEGIN
  IF NEW.store_id IS NULL THEN
    RAISE EXCEPTION 'store_id cannot be null';
  END IF;

  PERFORM pg_advisory_xact_lock(1010, hashtext(NEW.store_id));

  SELECT COALESCE(MAX(demand_id), 0) + 1
    INTO next_demand_id
  FROM public.store_demand_list
  WHERE store_id = NEW.store_id;

  NEW.demand_id := next_demand_id;
  RETURN NEW;
END;
$$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.store_demand_list (

  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Per-store demand number, auto-assigned by trigger (starts at 0)
  -- 门店内需求编号，由触发器自动分配（从 1 开始）
  demand_id integer NOT NULL,

  -- Demand tag/category (client-managed vocabulary)
  -- 需求标签/分类（由客户端管理标签字典）
  tag text NOT NULL,

  -- Review workflow status
  -- 审核流程状态
  status public.demand_status NOT NULL DEFAULT 'pending',

  -- Demand content in plain text; can contain multiple items
  -- 需求正文（纯文本）；可在一行中写多个需求项
  content text NOT NULL,

  -- Creator user
  -- 创建人
  created_by integer NOT NULL REFERENCES public.user_list(user_id),

  -- Creation time
  -- 创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Reviewer user (manager+), NULL before review
  -- 审核人（manager+），未审核前为 NULL
  reviewed_by integer DEFAULT NULL REFERENCES public.user_list(user_id),

  -- Review timestamp, NULL before review
  -- 审核时间，未审核前为 NULL
  reviewed_at timestamptz DEFAULT NULL,

  -- Review note / rejection reason / handling instruction
  -- 审核备注 / 驳回原因 / 处理说明
  manager_note text DEFAULT NULL,

  -- Last update timestamp (auto-refreshed by trigger)
  -- 最后更新时间（由触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Soft delete timestamp
  -- 软删除时间戳
  deleted_at timestamptz DEFAULT NULL,

  -- Composite PK ensures demand_id uniqueness within each store
  -- 联合主键保证 demand_id 在门店内唯一
  CONSTRAINT store_demand_list_pkey PRIMARY KEY (store_id, demand_id),

  -- demand_id must be non-negative
  -- demand_id 必须为非负整数
  CONSTRAINT chk_store_demand_id_non_negative CHECK (demand_id >= 0),

  -- Review fields should be set together (both NULL or both non-NULL)
  -- 审核字段应同时为空或同时有值
  CONSTRAINT chk_store_demand_review_pair CHECK (
    (reviewed_by IS NULL AND reviewed_at IS NULL)
    OR
    (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
  )
);

-- =============================================
-- Trigger: auto-assign demand_id on INSERT
-- 触发器：INSERT 时自动分配 demand_id
-- =============================================
DROP TRIGGER IF EXISTS trg_store_demand_assign_id ON public.store_demand_list;
CREATE TRIGGER trg_store_demand_assign_id
BEFORE INSERT ON public.store_demand_list
FOR EACH ROW
EXECUTE FUNCTION public.assign_demand_id_per_store();

-- =============================================
-- Trigger: auto-refresh updated_at
-- 触发器：自动刷新 updated_at
-- =============================================
DROP TRIGGER IF EXISTS trg_store_demand_set_updated_at ON public.store_demand_list;
CREATE TRIGGER trg_store_demand_set_updated_at
BEFORE UPDATE ON public.store_demand_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Indexes / 索引
-- =============================================

-- Main list query: store demands sorted by newest first (active rows only)
-- 主列表查询：门店需求按时间倒序（仅活跃记录）
CREATE INDEX IF NOT EXISTS idx_store_demand_store_created
  ON public.store_demand_list (store_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- Filter by status within a store
-- 门店内按状态筛选
CREATE INDEX IF NOT EXISTS idx_store_demand_store_status_created
  ON public.store_demand_list (store_id, status, created_at DESC)
  WHERE deleted_at IS NULL;

-- Filter by tag within a store
-- 门店内按标签筛选
CREATE INDEX IF NOT EXISTS idx_store_demand_store_tag_created
  ON public.store_demand_list (store_id, tag, created_at DESC)
  WHERE deleted_at IS NULL;
