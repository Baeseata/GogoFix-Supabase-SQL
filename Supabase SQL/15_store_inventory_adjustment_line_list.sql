-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 15 · store_inventory_adjustment_line_list — Inventory adjustment line item table
-- 文件 15 · store_inventory_adjustment_line_list — 库存盘点/调整明细行表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list            (store_id, via composite FK)
--   06_mother_inventory_list (unique_id, via composite FK + inventory_mode ENUM)
--   08_store_inventory_list  (store_id, unique_id composite FK + stock_bucket ENUM)
--   14_store_inventory_adjustment_list (adjustment_id FK)
-- Dependents / 被依赖:
--   (none) （无）
-- =============================================
-- Each adjustment (header) contains one or more line items, each recording the
-- inventory change for a single product.
-- Only for non-serialized products (service/tracked/untracked; service is rejected by trigger).
-- Serialized items have their own lifecycle management via serialized_event_list.
-- ─────────────────────────────────────────────
-- 每次盘点（主表）包含一条或多条明细行，记录每个商品的库存调整。
-- 仅适用于非 serialized 商品（service/tracked/untracked；service 会被触发器拦截）。
-- serialized 商品有独立的生命周期管理（serialized_event_list）。
-- =============================================

CREATE TABLE IF NOT EXISTS public.store_inventory_adjustment_line_list (

  -- Auto-increment primary key, starting from 0
  -- 全局自增主键，从 0 开始
  line_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- Store ID (matches header; also part of composite FK to store_inventory_list)
  -- 门店 ID（与主表一致；同时参与 store_inventory_list 复合外键）
  store_id text NOT NULL,

  -- Parent adjustment, FK to store_inventory_adjustment_list
  -- 所属盘点单，外键指向 store_inventory_adjustment_list
  adjustment_id integer NOT NULL REFERENCES public.store_inventory_adjustment_list(adjustment_id),

  -- Product reference (part of composite FK to store_inventory_list)
  -- 商品引用（与 store_id 一起组成 store_inventory_list 复合外键）
  unique_id integer NOT NULL,

  -- Quantity change for tracked items: new_qty − old_qty
  -- May be 0 (confirming count is correct), may be negative
  -- Must be NULL for untracked / service items
  -- tracked 商品的数量变动：新数量 − 旧数量
  -- 允许为 0（表示盘点确认数量无误）、允许为负
  -- untracked / service 商品应为 NULL
  qty_delta integer DEFAULT NULL,

  -- Post-adjustment quantity snapshot for tracked items
  -- Recorded by the client at adjustment time for audit purposes
  -- tracked 商品调整后的库存数量快照
  -- 由客户端在调整时记录，方便审计查询
  qty_after integer DEFAULT NULL,

  -- Post-adjustment stock level for untracked items (the new fuzzy level)
  -- untracked 商品调整后的模糊库存档位（新档位值）
  stock_bucket_after public.stock_bucket DEFAULT NULL,

  -- Cost per unit snapshot at adjustment time (read from store_inventory_list.cost)
  -- 调整时的单位成本快照（从 store_inventory_list.cost 读取）
  cost_per_unit numeric(10,2) DEFAULT NULL,

  -- Composite FK to store_inventory_list (store_id, unique_id)
  -- 复合外键指向 store_inventory_list (store_id, unique_id)
  CONSTRAINT fk_adjustment_line_list_store_inventory_list
    FOREIGN KEY (store_id, unique_id)
    REFERENCES public.store_inventory_list (store_id, unique_id),

  -- Mutual exclusion: qty_delta and stock_bucket_after cannot both be non-NULL
  -- 互斥约束：qty_delta 和 stock_bucket_after 不能同时有值
  CONSTRAINT chk_adjustment_line_list_qty_bucket_mutex
    CHECK (NOT (qty_delta IS NOT NULL AND stock_bucket_after IS NOT NULL))
);

-- =============================================
-- Trigger: validate inventory_mode consistency
-- 触发器：校验 inventory_mode 一致性
-- =============================================
-- Rules:
--   service    → reject (no inventory to adjust)
--   serialized → reject (use serialized_event_list instead)
--   tracked    → qty_delta required, stock_bucket fields must be NULL
--   untracked  → stock_bucket_after required, qty fields must be NULL
-- 规则：
--   service    → 拒绝（不跟踪库存，盘点无意义）
--   serialized → 拒绝（应使用 serialized_event_list）
--   tracked    → 必须有 qty_delta，stock_bucket 字段必须为 NULL
--   untracked  → 必须有 stock_bucket_after，qty 字段必须为 NULL
-- =============================================
CREATE OR REPLACE FUNCTION public.adjustment_line_enforce_mode()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Variable legend / 变量说明:
  --   v_mode = inventory_mode from mother table / 母表的库存跟踪模式
  v_mode public.inventory_mode;
BEGIN
  SELECT inventory_mode
    INTO v_mode
  FROM public.mother_inventory_list
  WHERE unique_id = NEW.unique_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'mother_inventory_list.unique_id % not found', NEW.unique_id;
  END IF;

  -- Service items cannot be adjusted (no inventory to track)
  -- service 商品不可盘点（不跟踪库存）
  IF v_mode = 'service' THEN
    RAISE EXCEPTION 'service item (unique_id=%) cannot be adjusted', NEW.unique_id;
  END IF;

  -- Serialized items cannot be adjusted here (use serialized_event_list)
  -- serialized 商品不可在本表盘点（应使用 serialized_event_list）
  IF v_mode = 'serialized' THEN
    RAISE EXCEPTION 'serialized item (unique_id=%) cannot be adjusted here', NEW.unique_id;
  END IF;

  -- Tracked items: must have qty_delta, must NOT have stock_bucket fields
  -- tracked 商品：应有 qty_delta，不应有 bucket 字段
  IF v_mode = 'tracked' THEN
    IF NEW.qty_delta IS NULL THEN
      RAISE EXCEPTION 'tracked item (unique_id=%) requires qty_delta', NEW.unique_id;
    END IF;
    IF NEW.stock_bucket_after IS NOT NULL THEN
      RAISE EXCEPTION 'tracked item (unique_id=%) must not have stock_bucket fields', NEW.unique_id;
    END IF;
  END IF;

  -- Untracked items: must have stock_bucket_after, must NOT have qty fields
  -- untracked 商品：应有 stock_bucket_after，不应有 qty 字段
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

-- =============================================
-- Indexes / 索引
-- =============================================

-- Look up all line items for a given adjustment
-- 查询某次盘点的所有明细行
CREATE INDEX IF NOT EXISTS idx_adjustment_line_adjustment
  ON public.store_inventory_adjustment_line_list (adjustment_id);

-- Look up adjustment history for a specific product
-- 查询某商品的盘点历史
CREATE INDEX IF NOT EXISTS idx_adjustment_line_unique_id
  ON public.store_inventory_adjustment_line_list (unique_id);

-- Look up all adjustment lines for a store
-- 查询门店的所有盘点明细
CREATE INDEX IF NOT EXISTS idx_adjustment_line_store
  ON public.store_inventory_adjustment_line_list (store_id);
