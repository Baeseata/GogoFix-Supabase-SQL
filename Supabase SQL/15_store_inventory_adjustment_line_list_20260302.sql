-- =========================================
-- 15 · store_inventory_adjustment_line_list 盘点明细表
-- =========================================
-- 依赖: 01_store_list (store_id)
--        06_mother_inventory_list (unique_id)
--        06 中的 ENUM inventory_mode
--        08_store_inventory_list (store_id, unique_id 复合 FK)
--        08 中的 ENUM stock_bucket
--        14_store_inventory_adjustment_list (adjustment_id FK)
-- 被依赖: 无
--
-- 每次盘点（adjustment）包含一条或多条明细行，记录每个商品的库存调整
-- 仅适用于非 serialized 商品（service / tracked / untracked，其中 service 会被触发器拦截）

CREATE TABLE IF NOT EXISTS public.store_inventory_adjustment_line_list (

  -- 全局自增主键，从 0 开始
  line_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 门店 ID（与主表一致，亦用于复合外键指向 store_inventory_list）
  store_id text NOT NULL,

  -- 所属盘点单
  adjustment_id integer NOT NULL REFERENCES public.store_inventory_adjustment_list(adjustment_id),

  -- 关联门店库存行（复合外键）
  unique_id integer NOT NULL,

  -- 库存数量变动（tracked 商品使用）：新库存 − 旧库存
  -- 允许为 0（表示盘点确认数量无误）、允许为负
  -- untracked / service 商品应为 NULL
  qty_delta integer DEFAULT NULL,

  -- 调整后的库存数量快照（tracked 商品使用）
  -- 由客户端在调整时记录，方便审计查询
  qty_after integer DEFAULT NULL,

  -- 调整后的档位快照（untracked 商品使用）
  -- 实际上和 new_stock_bucket 相同，但显式保留以便和 qty_after 风格统一
  stock_bucket_after public.stock_bucket DEFAULT NULL,

  -- 调整前该商品的当前成本快照，从 store_inventory_list.cost 读取填入
  cost_per_unit numeric(10,2) DEFAULT NULL,

  -- 复合外键：指向 store_inventory_list(store_id, unique_id)
  CONSTRAINT adjustment_line_fk_store_inventory
    FOREIGN KEY (store_id, unique_id)
    REFERENCES public.store_inventory_list (store_id, unique_id),

  -- 互斥约束：qty_delta 和 new_stock_bucket 不能同时有值
  CONSTRAINT adjustment_line_qty_bucket_mutex
    CHECK (NOT (qty_delta IS NOT NULL AND stock_bucket_after IS NOT NULL))
);

-- =========================================
-- Trigger：校验 inventory_mode 一致性
-- =========================================
-- - service 商品：直接拒绝（service 不跟踪库存，盘点无意义）
-- - serialized 商品：直接拒绝（serialized 有独立管理方式）
-- - tracked 商品：qty_delta 应有值，stock_bucket 字段应为 NULL
-- - untracked 商品：stock_bucket_after 应有值，qty 字段应为 NULL
CREATE OR REPLACE FUNCTION public.adjustment_line_enforce_mode()
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

  -- service 商品不可盘点
  IF v_mode = 'service' THEN
    RAISE EXCEPTION 'service item (unique_id=%) cannot be adjusted', NEW.unique_id;
  END IF;

  -- serialized 商品不可在本表盘点
  IF v_mode = 'serialized' THEN
    RAISE EXCEPTION 'serialized item (unique_id=%) cannot be adjusted here', NEW.unique_id;
  END IF;

  -- tracked：应有 qty_delta，不应有 bucket 字段
  IF v_mode = 'tracked' THEN
    IF NEW.qty_delta IS NULL THEN
      RAISE EXCEPTION 'tracked item (unique_id=%) requires qty_delta', NEW.unique_id;
    END IF;
    IF NEW.stock_bucket_after IS NOT NULL THEN
      RAISE EXCEPTION 'tracked item (unique_id=%) must not have stock_bucket fields', NEW.unique_id;
    END IF;
  END IF;

  -- untracked：应有 stock_bucket_after，不应有 qty 字段
  IF v_mode = 'untracked' THEN
    IF NEW.stock_bucket_after IS NULL THEN
      RAISE EXCEPTION 'untracked item (unique_id=%) requires stock_bucket_after', NEW.unique_id;
    END IF;
    IF NEW.qty_delta IS NOT NULL OR NEW.qty_after IS NOT NULL THEN
      RAISE EXCEPTION 'untracked item (unique_id=%) must not have qty fields', NEW.unique_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_adjustment_line_enforce_mode ON public.store_inventory_adjustment_line_list;
CREATE TRIGGER trg_adjustment_line_enforce_mode
BEFORE INSERT OR UPDATE ON public.store_inventory_adjustment_line_list
FOR EACH ROW
EXECUTE FUNCTION public.adjustment_line_enforce_mode();

-- =========================================
-- 索引
-- =========================================

-- 查询某次盘点的所有明细行
CREATE INDEX IF NOT EXISTS idx_adjustment_line_adjustment
  ON public.store_inventory_adjustment_line_list (adjustment_id);

-- 查询商品的盘点历史
CREATE INDEX IF NOT EXISTS idx_adjustment_line_unique_id
  ON public.store_inventory_adjustment_line_list (unique_id);

-- 查询门店的所有盘点明细
CREATE INDEX IF NOT EXISTS idx_adjustment_line_store
  ON public.store_inventory_adjustment_line_list (store_id);
