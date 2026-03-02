-- =========================================
-- 18 · store_transfer_line_list 调拨明细表
-- =========================================
-- 依赖: 06_mother_inventory_list (unique_id FK)
--        06 中的 ENUM inventory_mode
--        09_store_serialized_list (unit_id FK)
--        17_store_transfer_list (store_transfer_id FK)
-- 被依赖: 无

CREATE TABLE IF NOT EXISTS public.store_transfer_line_list (

  -- 全局自增主键，从 0 开始
  line_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 所属调拨单
  store_transfer_id integer NOT NULL REFERENCES public.store_transfer_list(store_transfer_id),

  -- 关联母表商品
  unique_id integer NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- 序列号商品关联：serialized 商品应有值，非 serialized 商品应为 NULL
  -- 由触发器校验一致性（见下方 Trigger）
  unit_id integer DEFAULT NULL REFERENCES public.store_serialized_list(unit_id),

  -- 商品名称快照，由客户端从 store_inventory_list 或 store_serialized_list 读取填入
  item_name text NOT NULL,

  -- 单位成本快照
  cost_per_unit numeric(10,2) NOT NULL DEFAULT 0,

  -- 单位售价快照
  price_per_unit numeric(10,2) NOT NULL DEFAULT 0,

  -- 调拨数量：serialized 商品应为 1，其他商品由客户端填写
  qty integer NOT NULL,

  -- 序列号文本：仅 serialized 商品有值
  serial text DEFAULT NULL,

  -- qty 应大于 0（调拨不应有 0 或负数）
  CONSTRAINT transfer_line_qty_positive
    CHECK (qty > 0)
);

-- =========================================
-- Trigger：校验 inventory_mode 一致性
-- =========================================
-- - service 商品：拒绝（service 不跟踪库存，无需调拨）
-- - serialized 商品：qty 应为 1，unit_id 和 serial 应有值
-- - tracked / untracked 商品：unit_id 和 serial 应为 NULL
CREATE OR REPLACE FUNCTION public.transfer_line_enforce_mode()
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

  -- service 商品不可调拨
  IF v_mode = 'service' THEN
    RAISE EXCEPTION 'service item (unique_id=%) cannot be transferred', NEW.unique_id;
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

DROP TRIGGER IF EXISTS trg_transfer_line_enforce_mode ON public.store_transfer_line_list;
CREATE TRIGGER trg_transfer_line_enforce_mode
BEFORE INSERT OR UPDATE ON public.store_transfer_line_list
FOR EACH ROW
EXECUTE FUNCTION public.transfer_line_enforce_mode();

-- =========================================
-- 索引
-- =========================================

-- 查询某次调拨的所有明细行
CREATE INDEX IF NOT EXISTS idx_transfer_line_transfer
  ON public.store_transfer_line_list (store_transfer_id);

-- 查询商品的调拨历史
CREATE INDEX IF NOT EXISTS idx_transfer_line_unique_id
  ON public.store_transfer_line_list (unique_id);

-- 查询序列号单件的调拨记录
CREATE INDEX IF NOT EXISTS idx_transfer_line_unit_id
  ON public.store_transfer_line_list (unit_id)
  WHERE unit_id IS NOT NULL;
