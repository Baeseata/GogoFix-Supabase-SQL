-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 08 · store_inventory_list — Per-store inventory table
-- 文件 08 · store_inventory_list — 门店库存明细表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list           (store_id FK)
--   06_mother_inventory_list (unique_id FK + inventory_mode ENUM)
-- Dependents / 被依赖:
--   15_store_inventory_adjustment_line_list (store_id, unique_id composite FK)
-- Shared components created here / 本文件创建的共享组件:
--   ENUM public.stock_bucket — also used by 15_adjustment_line, 19_store_item_history
-- =============================================
-- Per-store inventory for service / tracked / untracked items.
-- Serialized items have their own table: store_serialized_list (file 09).
-- ─────────────────────────────────────────────
-- 门店库存明细表：记录每个门店对 mother_inventory_list 中商品的实际库存状况。
-- 仅适用于 service / tracked / untracked 三种模式；
-- serialized 商品有独立的 store_serialized_list 表（文件 09），不在本处记录。
-- =============================================

-- =============================================
-- ENUM: stock_bucket — Fuzzy inventory level for untracked items
-- 枚举：stock_bucket — 非精确跟踪商品的模糊库存档位
-- =============================================
-- >>> Also used by 15_adjustment_line_list, 19_store_item_history_list <<<
-- >>> 也被 15_adjustment_line_list、19_store_item_history_list 引用 <<<
--
--   empty    = Out of stock / 无货
--   very_few = Very few left, near stockout / 极少，快断货
--   few      = Small quantity remaining / 少量
--   normal   = Normal stock level / 库存正常
--   too_much = Overstocked / 库存过多（积压）
DO $$
BEGIN
  CREATE TYPE public.stock_bucket AS ENUM ('empty', 'very_few', 'few', 'normal', 'too_much');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.store_inventory_list (

  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Product reference, FK to mother_inventory_list (NOT item_id, but the true PK unique_id)
  -- 商品引用，外键指向 mother_inventory_list（不是 item_id，而是真正的主键 unique_id）
  unique_id int NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- Exact stock quantity; used ONLY for tracked mode
  -- May be negative: business allows selling below zero to avoid blocking sales due to count errors
  -- Must be NULL for service / untracked modes
  -- 精确库存数量；仅 tracked 模式使用
  -- 允许负数：业务上为避免因库存计数偏差阻碍销售，允许先销售后修正
  -- service / untracked 模式应为 NULL
  qty_on_hand int DEFAULT NULL,

  -- Fuzzy stock level; used ONLY for untracked mode
  -- Must be NULL for service / tracked modes
  -- 模糊库存档位；仅 untracked 模式使用
  -- service / tracked 模式应为 NULL
  stock_bucket public.stock_bucket DEFAULT NULL,

  -- Store-specific cost per unit
  -- On INSERT, if NULL, auto-inherited from mother table default_cost; afterwards updated independently
  -- 门店的实际单位成本
  -- INSERT 时若为空，自动从母表 default_cost 继承；之后独立更新，不随母表变化
  cost numeric(10,2) DEFAULT NULL,

  -- Store-specific retail price per unit
  -- On INSERT, if NULL, auto-inherited from mother table default_price; afterwards updated independently
  -- 门店的当前零售单价
  -- INSERT 时若为空，自动从母表 default_price 继承；之后独立更新
  price numeric(10,2) DEFAULT NULL,

  -- Minimum suggested price for sales staff; advisory only, not enforced
  -- 前台最低报价指导价：销售人员可参考作为报价下限，不做强制限制
  last_price numeric(10,2) DEFAULT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Soft delete timestamp; NULL = active, non-NULL = product removed from this store
  -- Note: before soft-deleting, ensure the mother table inventory_mode hasn't changed incompatibly.
  -- To change mode, soft-delete all store rows first, then modify the mother table.
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示该门店已下架本商品
  -- 注意：软删除前应确保母表 inventory_mode 未发生不兼容的变更。
  -- 若需变更 mode，应先将所有门店的该商品行软删除，再修改母表。
  deleted_at timestamptz DEFAULT NULL,

  -- Composite PK: one row per product per store (including soft-deleted rows)
  -- 联合主键：同一门店内，同一 SKU 只能有一行（含软删除行）
  CONSTRAINT store_inventory_list_pkey PRIMARY KEY (store_id, unique_id),

  -- Mutual exclusion: qty_on_hand and stock_bucket cannot both be non-NULL
  -- (DB-level safety net; the trigger also validates this per inventory_mode)
  -- 互斥约束：qty_on_hand 和 stock_bucket 不能同时有值
  -- （数据库层面兜底；触发器也会按 inventory_mode 进行明确校验）
  CONSTRAINT chk_store_inventory_list_qty_bucket_mutex
    CHECK (NOT (qty_on_hand IS NOT NULL AND stock_bucket IS NOT NULL))
);

-- =============================================
-- Trigger A: validate inventory_mode consistency + inherit default cost/price on INSERT
-- 触发器 A：校验 inventory_mode 一致性 + INSERT 时从母表继承默认 cost/price
-- =============================================
-- Logic:
--   - On INSERT and UPDATE: validates mode consistency (soft-deleted rows skip validation)
--   - On INSERT only: inherits cost/price from mother table defaults
--   - Serialized items are rejected (must use store_serialized_list instead)
-- 逻辑说明：
--   - INSERT 和 UPDATE 时均执行 mode 一致性校验（软删除行跳过校验）
--   - 仅 INSERT 时将 cost/price 从母表默认值继承
--   - serialized 商品直接拒绝写入，应使用 store_serialized_list 表
-- =============================================
CREATE OR REPLACE FUNCTION public.store_inventory_enforce_mode_and_defaults()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Variable legend / 变量说明:
  --   v_mode  = inventory_mode from mother table / 母表的库存跟踪模式
  --   m_cost  = default_cost from mother table / 母表的默认成本
  --   m_price = default_price from mother table / 母表的默认价格
  v_mode public.inventory_mode;
  m_cost numeric(10,2);
  m_price numeric(10,2);
BEGIN
  -- Soft-deleted rows skip all business validation / 软删除行跳过所有业务校验
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Read inventory_mode and default prices from mother table
  -- 从母表读取 inventory_mode 及默认价格
  SELECT inventory_mode, default_cost, default_price
    INTO v_mode, m_cost, m_price
  FROM public.mother_inventory_list
  WHERE unique_id = NEW.unique_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'mother_inventory_list.unique_id % not found', NEW.unique_id;
  END IF;

  -- Serialized items must NOT be inserted here; use store_serialized_list instead
  -- serialized 商品不允许写入本表，应使用 store_serialized_list
  IF v_mode = 'serialized' THEN
    RAISE EXCEPTION 'unique_id % is serialized; use store_serialized_list table instead', NEW.unique_id;
  END IF;

  -- Service items: no inventory tracking, both qty and bucket must be NULL
  -- service 商品：不跟踪库存，qty 和 bucket 均应为 NULL
  IF v_mode = 'service' THEN
    IF NEW.qty_on_hand IS NOT NULL OR NEW.stock_bucket IS NOT NULL THEN
      RAISE EXCEPTION 'service item must have qty_on_hand NULL and stock_bucket NULL (unique_id=%)', NEW.unique_id;
    END IF;
  END IF;

  -- Tracked items: must have exact quantity, bucket must be NULL
  -- tracked 商品：应有精确数量，bucket 应为 NULL
  IF v_mode = 'tracked' THEN
    IF NEW.qty_on_hand IS NULL OR NEW.stock_bucket IS NOT NULL THEN
      RAISE EXCEPTION 'tracked item must have qty_on_hand NOT NULL and stock_bucket NULL (unique_id=%)', NEW.unique_id;
    END IF;
  END IF;

  -- Untracked items: must have bucket level, qty must be NULL
  -- untracked 商品：应有档位标记，qty 应为 NULL
  IF v_mode = 'untracked' THEN
    IF NEW.stock_bucket IS NULL OR NEW.qty_on_hand IS NOT NULL THEN
      RAISE EXCEPTION 'untracked item must have stock_bucket NOT NULL and qty_on_hand NULL (unique_id=%)', NEW.unique_id;
    END IF;
  END IF;

  -- On INSERT only: inherit default cost/price from mother table (UPDATE preserves store-specific values)
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

-- =============================================
-- Trigger: auto-refresh updated_at (reuses set_updated_at() from file 03)
-- 触发器：自动刷新 updated_at（复用 03_user_list 中的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_store_inventory_list_updated_at ON public.store_inventory_list;
CREATE TRIGGER trg_store_inventory_list_updated_at
BEFORE UPDATE ON public.store_inventory_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Indexes / 索引
-- =============================================

-- Reverse lookup: find which stores carry a given product (active only)
-- PK already covers "list all products for a store" queries
-- 反向查询：查找哪些门店有某商品的库存（仅活跃记录）
-- PK 已覆盖"查询门店全量库存"的场景
CREATE INDEX IF NOT EXISTS idx_store_inventory_list_unique_id
  ON public.store_inventory_list (unique_id)
  WHERE deleted_at IS NULL;

-- Quick lookup of all active products in a store
-- 快速查询门店所有活跃商品
CREATE INDEX IF NOT EXISTS idx_store_inventory_list_active
  ON public.store_inventory_list (store_id)
  WHERE deleted_at IS NULL;
