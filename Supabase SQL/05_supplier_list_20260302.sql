-- =========================================
-- 05 · supplier_list 供应商主表
-- =========================================
-- 依赖: 01_store_list (created_store_id FK)
-- 被依赖: 06_mother_inventory_list (supplier_id FK)
--         20_purchase_order_list (supplier_id FK)

CREATE TABLE IF NOT EXISTS public.supplier_list (

  -- 全局自增主键，从 0 开始
  supplier_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 供应商名称，活跃记录内唯一（见下方 partial unique index）
  supplier_name text NOT NULL,

  -- 供应商电话
  supplier_phone_number text DEFAULT NULL,

  -- 供应商邮箱
  supplier_email_address text DEFAULT NULL,

  -- 创建该供应商记录的门店 ID
  created_store_id text NOT NULL REFERENCES public.store_list(store_id),

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已停用
  deleted_at timestamptz DEFAULT NULL
);

-- =========================================
-- 供应商名称唯一约束（仅活跃记录生效）
-- =========================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_supplier_name_active
  ON public.supplier_list (supplier_name)
  WHERE deleted_at IS NULL;

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_supplier_list_updated_at ON public.supplier_list;
CREATE TRIGGER trg_supplier_list_updated_at
BEFORE UPDATE ON public.supplier_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 活跃供应商索引
-- =========================================
CREATE INDEX IF NOT EXISTS idx_supplier_active
  ON public.supplier_list (supplier_id)
  WHERE deleted_at IS NULL;
