-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 05 · supplier_list — Supplier master table
-- 文件 05 · supplier_list — 供应商主表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (created_store_id FK)
-- Dependents / 被依赖:
--   06_mother_inventory_list (supplier_id FK)
--   20_purchase_order_list   (supplier_id FK)
-- =============================================

CREATE TABLE IF NOT EXISTS public.supplier_list (

  -- Auto-increment primary key, starting from 1; should not be manually assigned
  -- 全局自增主键，从 1 开始；业务端不应手动指定
  supplier_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 1 MINVALUE 1)
    PRIMARY KEY,

  -- Supplier name; unique among active (non-deleted) records via partial unique index below
  -- 供应商名称；在活跃（未删除）记录中唯一（见下方 partial unique index）
  supplier_name text NOT NULL,

  -- Supplier phone number (optional)
  -- 供应商电话（可选）
  supplier_phone_number text DEFAULT NULL,

  -- Supplier email address (optional)
  -- 供应商邮箱（可选）
  supplier_email_address text DEFAULT NULL,

  -- Store that created this supplier record
  -- 创建该供应商记录的门店 ID
  created_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Soft delete timestamp; NULL = active, non-NULL = disabled
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已停用
  deleted_at timestamptz DEFAULT NULL
);

-- =============================================
-- Partial unique index: supplier name must be unique among active records.
-- After soft delete the name is released, allowing reuse.
-- ─────────────────────────────────────────────
-- 部分唯一索引：供应商名称在活跃记录中唯一。
-- 软删除后名称释放，可被新记录使用。
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_supplier_list_name_active
  ON public.supplier_list (supplier_name)
  WHERE deleted_at IS NULL;

-- =============================================
-- Trigger: auto-refresh updated_at on every UPDATE
-- (reuses set_updated_at() created in 03_user_list)
-- 触发器：每次 UPDATE 自动刷新 updated_at
-- （复用 03_user_list 中创建的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_supplier_list_updated_at ON public.supplier_list;
CREATE TRIGGER trg_supplier_list_updated_at
BEFORE UPDATE ON public.supplier_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Index: quickly find active (non-deleted) suppliers
-- 索引：快速查找活跃（未删除）供应商
-- =============================================
CREATE INDEX IF NOT EXISTS idx_supplier_list_active
  ON public.supplier_list (supplier_id)
  WHERE deleted_at IS NULL;
