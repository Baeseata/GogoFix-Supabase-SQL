-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =========================================
-- 20 · purchase_order_list 采购订单主表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        03_user_list (user_id FK)
--        05_supplier_list (supplier_id FK)
-- 被依赖: 21_purchase_order_line_list (store_id, purchase_order_id 复合 FK)
--
-- 记录从供应商采购商品的订单，仅在联网时可操作，不支持离线

-- =========================================
-- 函数: assign_purchase_order_id_per_store()
-- =========================================
-- 同一 store_id 下，purchase_order_id 从 0 开始依次递增
CREATE OR REPLACE FUNCTION public.assign_purchase_order_id_per_store()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_id int;
BEGIN
  IF NEW.store_id IS NULL THEN
    RAISE EXCEPTION 'store_id cannot be null';
  END IF;

  -- 咨询锁：命名空间 1004，避免和其他锁冲突
  PERFORM pg_advisory_xact_lock(1004, hashtext(NEW.store_id));

  SELECT COALESCE(MAX(purchase_order_id), -1) + 1
    INTO next_id
  FROM public.purchase_order_list
  WHERE store_id = NEW.store_id;

  NEW.purchase_order_id := next_id;
  RETURN NEW;
END;
$$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.purchase_order_list (

  -- 门店 ID
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 采购单编号，同一门店内从 0 开始自动递增，由触发器分配
  purchase_order_id integer NOT NULL,

  -- 供应商
  supplier_id integer DEFAULT NULL REFERENCES public.supplier_list(supplier_id),

  -- 操作人
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- 采购单备注 / 描述
  description text DEFAULT NULL,

  -- 采购总成本（客户端计算后传入）
  total_cost numeric(10,2) NOT NULL DEFAULT 0,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 软删除时间戳
  deleted_at timestamptz DEFAULT NULL,

  -- 联合主键：同一门店内采购单编号唯一
  CONSTRAINT purchase_order_list_pk PRIMARY KEY (store_id, purchase_order_id)
);

-- =========================================
-- purchase_order_id 自动分配触发器
-- =========================================
DROP TRIGGER IF EXISTS trg_purchase_order_assign_id ON public.purchase_order_list;
CREATE TRIGGER trg_purchase_order_assign_id
BEFORE INSERT ON public.purchase_order_list
FOR EACH ROW
EXECUTE FUNCTION public.assign_purchase_order_id_per_store();

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_purchase_order_updated_at ON public.purchase_order_list;
CREATE TRIGGER trg_purchase_order_updated_at
BEFORE UPDATE ON public.purchase_order_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 索引
-- =========================================

-- 某门店的采购单列表（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_purchase_order_store
  ON public.purchase_order_list (store_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- 按供应商查采购单
CREATE INDEX IF NOT EXISTS idx_purchase_order_supplier
  ON public.purchase_order_list (supplier_id)
  WHERE supplier_id IS NOT NULL AND deleted_at IS NULL;
