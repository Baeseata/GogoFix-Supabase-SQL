-- =========================================
-- 21 · purchase_order_line_list 采购订单明细表
-- =========================================
-- 依赖: 06_mother_inventory_list (unique_id FK)
--        06 中的 ENUM inventory_mode
--        09_store_serialized_list (unit_id FK)
--        20_purchase_order_list (store_id, purchase_order_id 复合 FK)
-- 被依赖: 无

CREATE TABLE IF NOT EXISTS public.purchase_order_line_list (

  -- 全局自增主键，从 0 开始
  purchase_order_line_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 门店 ID（用于复合外键指向主表）
  store_id text NOT NULL,

  -- 所属采购单
  purchase_order_id integer NOT NULL,

  -- 关联母表商品
  unique_id integer NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- 序列号商品关联：serialized 商品应有值，非 serialized 商品应为 NULL
  unit_id integer DEFAULT NULL REFERENCES public.store_serialized_list(unit_id),

  -- 商品名称快照
  item_name text NOT NULL,

  -- 单位采购成本
  unit_cost numeric(10,2) NOT NULL DEFAULT 0,

  -- 采购数量：serialized 商品应为 1
  qty integer NOT NULL,

  -- 序列号文本：仅 serialized 商品有值
  serial text DEFAULT NULL,

  -- 备注
  note text DEFAULT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 软删除时间戳
  deleted_at timestamptz DEFAULT NULL,

  -- 复合外键：指向 purchase_order_list(store_id, purchase_order_id)
  CONSTRAINT purchase_order_line_fk_order
    FOREIGN KEY (store_id, purchase_order_id)
    REFERENCES public.purchase_order_list (store_id, purchase_order_id),

  -- 数量应大于 0
  CONSTRAINT purchase_order_line_qty_positive
    CHECK (qty > 0)
);

-- =========================================
-- Trigger：校验 inventory_mode 一致性
-- =========================================
-- - service 商品：拒绝（service 不跟踪库存，无需采购）
-- - serialized 商品：qty 应为 1，unit_id 和 serial 应有值
-- - tracked / untracked 商品：unit_id 和 serial 应为 NULL
CREATE OR REPLACE FUNCTION public.purchase_order_line_enforce_mode()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_mode public.inventory_mode;
BEGIN
  SELECT inventory_mode
    INTO v_mode
  FROM public.mother_inventory_list
  WHERE unique_id = NEW.unique_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'mother_inventory_list.unique_id % not found', NEW.unique_id;
  END IF;

  -- service 商品不可采购
  IF v_mode = 'service' THEN
    RAISE EXCEPTION 'service item (unique_id=%) cannot be purchased', NEW.unique_id;
  END IF;

  -- serialized 商品：qty 应为 1，且应有 unit_id 和 serial
  IF v_mode = 'serialized' THEN
    IF NEW.qty != 1 THEN
      RAISE EXCEPTION 'serialized item (unique_id=%) must have qty=1', NEW.unique_id;
    END IF;
    IF NEW.unit_id IS NULL THEN
      RAISE EXCEPTION 'serialized item (unique_id=%) requires unit_id', NEW.unique_id;
    END IF;
    IF NEW.serial IS NULL THEN
      RAISE EXCEPTION 'serialized item (unique_id=%) requires serial', NEW.unique_id;
    END IF;
  END IF;

  -- tracked / untracked 商品：不应有 unit_id 和 serial
  IF v_mode IN ('tracked', 'untracked') THEN
    IF NEW.unit_id IS NOT NULL THEN
      RAISE EXCEPTION 'non-serialized item (unique_id=%) must not have unit_id', NEW.unique_id;
    END IF;
    IF NEW.serial IS NOT NULL THEN
      RAISE EXCEPTION 'non-serialized item (unique_id=%) must not have serial', NEW.unique_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_purchase_order_line_enforce_mode ON public.purchase_order_line_list;
CREATE TRIGGER trg_purchase_order_line_enforce_mode
BEFORE INSERT OR UPDATE ON public.purchase_order_line_list
FOR EACH ROW
EXECUTE FUNCTION public.purchase_order_line_enforce_mode();

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_purchase_order_line_updated_at ON public.purchase_order_line_list;
CREATE TRIGGER trg_purchase_order_line_updated_at
BEFORE UPDATE ON public.purchase_order_line_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 索引
-- =========================================

-- 查某次采购单的所有明细行
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_order
  ON public.purchase_order_line_list (store_id, purchase_order_id)
  WHERE deleted_at IS NULL;

-- 查某商品的采购历史
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_unique_id
  ON public.purchase_order_line_list (unique_id)
  WHERE deleted_at IS NULL;

-- 查序列号单件的采购记录
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_unit_id
  ON public.purchase_order_line_list (unit_id)
  WHERE unit_id IS NOT NULL AND deleted_at IS NULL;
