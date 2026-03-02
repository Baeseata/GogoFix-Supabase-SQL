-- =========================================
-- 08 · store_inventory_list 门店库存明细表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        06_mother_inventory_list (unique_id FK)
--        06 中的 ENUM inventory_mode
-- 被依赖: 15_store_inventory_adjustment_line_list (store_id, unique_id 复合 FK)
--
-- 门店库存明细表：记录每个门店对 mother_inventory_list 中商品的实际库存状况
-- 仅适用于 service / tracked / untracked 三种模式；
-- serialized 商品有独立的 store_serialized_list 表，不在本处记录

-- =========================================
-- ENUM: stock_bucket 模糊库存档位枚举
-- =========================================
-- >>> 也被 15_store_inventory_adjustment_line_list 引用 <<<
--
-- 用于 untracked 模式商品：
--   empty    = 无货
--   very_few = 极少（快断货）
--   few      = 少量
--   normal   = 库存正常
--   too_much = 库存过多（积压）
DO $$
BEGIN
  CREATE TYPE public.stock_bucket AS ENUM ('empty', 'very_few', 'few', 'normal', 'too_much');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.store_inventory_list (

  -- 门店 ID
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 关联 mother_inventory_list 的全局唯一主键（非 item_id）
  unique_id int NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- 精确库存数量，仅 tracked 模式使用
  -- 允许负数：业务上为避免因库存计数跑偏阻碍，先行后期修正
  -- service / untracked 应为 NULL
  qty_on_hand int DEFAULT NULL,

  -- 模糊库存档位，仅 untracked 模式使用；service / tracked 应为 NULL
  stock_bucket public.stock_bucket DEFAULT NULL,

  -- 该门店的实际成本
  -- INSERT 时若为空，自动从母表 default_cost 继承；之后独立更新，不随母表变化
  cost numeric(10,2) DEFAULT NULL,

  -- 该门店的当前售价
  -- INSERT 时若为空，自动从母表 default_price 继承；之后独立更新
  price numeric(10,2) DEFAULT NULL,

  -- 前台最低报价指导价：门店销售人员可参考本价格作为对客报价下限，不做强制限制
  last_price numeric(10,2) DEFAULT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 软删除时间戳；NULL 表示正常状况，非 NULL 表示该门店已下架本商品
  -- 注意：软删除前应确保母表 inventory_mode 未发生无法兼容的变更，
  --       若需变更 mode，应先将所有门店该商品行软删除，再修改母表
  deleted_at timestamptz DEFAULT NULL,

  -- 联合主键：同一门店内，同一 SKU 只能有一行（含软删除行）
  CONSTRAINT store_inventory_list_pkey PRIMARY KEY (store_id, unique_id),

  -- 互斥约束：qty_on_hand 和 stock_bucket 不能同时有值（数据库兜底，触发器仍有明确校验）
  CONSTRAINT store_inventory_qty_bucket_mutex
    CHECK (NOT (qty_on_hand IS NOT NULL AND stock_bucket IS NOT NULL))
);

-- =========================================
-- Trigger A：校验 inventory_mode 一致性，并在 INSERT 时填充默认 cost/price
-- =========================================
-- 触发器逻辑说明：
--   - INSERT 和 UPDATE 时均执行 mode 一致性校验（软删除行跳过校验，允许字段为任意状况）
--   - 仅 INSERT 时将 cost/price 从母表默认值继承
--   - serialized 商品直接拒绝写入，应使用 store_serialized_list 表
CREATE OR REPLACE FUNCTION public.store_inventory_enforce_mode_and_defaults()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_mode public.inventory_mode;
  m_cost numeric(10,2);
  m_price numeric(10,2);
BEGIN
  -- 软删除行跳过所有业务校验，直接放行
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- 从母表读取 inventory_mode 及默认价格
  SELECT inventory_mode, default_cost, default_price
    INTO v_mode, m_cost, m_price
  FROM public.mother_inventory_list
  WHERE unique_id = NEW.unique_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'mother_inventory_list.unique_id % not found', NEW.unique_id;
  END IF;

  -- serialized 商品不允许写入本表，应使用 store_serialized_list
  IF v_mode = 'serialized' THEN
    RAISE EXCEPTION 'unique_id % is serialized; use store_serialized_list table instead', NEW.unique_id;
  END IF;

  -- service 商品：不跟踪库存，qty 和 bucket 均应为 NULL
  IF v_mode = 'service' THEN
    IF NEW.qty_on_hand IS NOT NULL OR NEW.stock_bucket IS NOT NULL THEN
      RAISE EXCEPTION 'service item must have qty_on_hand NULL and stock_bucket NULL (unique_id=%)', NEW.unique_id;
    END IF;
  END IF;

  -- tracked 商品：应有精确数量，bucket 应为 NULL
  IF v_mode = 'tracked' THEN
    IF NEW.qty_on_hand IS NULL OR NEW.stock_bucket IS NOT NULL THEN
      RAISE EXCEPTION 'tracked item must have qty_on_hand NOT NULL and stock_bucket NULL (unique_id=%)', NEW.unique_id;
    END IF;
  END IF;

  -- untracked 商品：应有档位标记，qty 应为 NULL
  IF v_mode = 'untracked' THEN
    IF NEW.stock_bucket IS NULL OR NEW.qty_on_hand IS NOT NULL THEN
      RAISE EXCEPTION 'untracked item must have stock_bucket NOT NULL and qty_on_hand NULL (unique_id=%)', NEW.unique_id;
    END IF;
  END IF;

  -- 仅 INSERT 时从母表继承默认 cost/price；UPDATE 时不覆盖（门店价格独立更新）
  IF TG_OP = 'INSERT' THEN
    IF NEW.cost IS NULL THEN NEW.cost := m_cost; END IF;
    IF NEW.price IS NULL THEN NEW.price := m_price; END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_store_inventory_enforce ON public.store_inventory_list;
CREATE TRIGGER trg_store_inventory_enforce
BEFORE INSERT OR UPDATE ON public.store_inventory_list
FOR EACH ROW
EXECUTE FUNCTION public.store_inventory_enforce_mode_and_defaults();

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_store_inventory_updated_at ON public.store_inventory_list;
CREATE TRIGGER trg_store_inventory_updated_at
BEFORE UPDATE ON public.store_inventory_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 索引
-- =========================================

-- PK (store_id, unique_id) 已覆盖"查询门店全量库存"的场景
-- 本索引补充"查询 SKU 在哪些门店有库存"的反向查询，过滤软删除行
CREATE INDEX IF NOT EXISTS idx_store_inventory_unique_id
  ON public.store_inventory_list (unique_id)
  WHERE deleted_at IS NULL;

-- 软删除过滤索引：加速"查询门店所有活跃商品"场景
CREATE INDEX IF NOT EXISTS idx_store_inventory_active
  ON public.store_inventory_list (store_id)
  WHERE deleted_at IS NULL;
