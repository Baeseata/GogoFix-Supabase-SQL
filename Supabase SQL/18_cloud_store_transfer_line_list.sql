-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 18 · store_transfer_line_list — Inter-store transfer line item table
-- 文件 18 · store_transfer_line_list — 调拨明细行表
-- =============================================
-- Dependencies / 依赖:
--   06_mother_inventory_list (unique_id FK + inventory_mode ENUM)
--   09_store_serialized_list (unit_id FK)
--   17_store_transfer_list   (store_transfer_id FK)
-- Dependents / 被依赖:
--   (none) （无）
-- =============================================
-- Each transfer (header) contains one or more line items.
-- Supports tracked (qty > 1 allowed), untracked (qty typically 1), and serialized (qty must be 1 with unit_id + serial).
-- ─────────────────────────────────────────────
-- 每次调拨（主表）包含一条或多条明细行。
-- 支持 tracked（qty 可大于 1）、untracked（qty 通常为 1）和 serialized（qty 必须为 1，需有 unit_id + serial）。
-- =============================================

CREATE TABLE IF NOT EXISTS public.store_transfer_line_list (

  -- Auto-increment primary key, starting from 1
  -- 全局自增主键，从 1 开始
  line_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 1 MINVALUE 1)
    PRIMARY KEY,

  -- Parent transfer, FK to store_transfer_list
  -- 所属调拨单，外键指向 store_transfer_list
  store_transfer_id integer NOT NULL REFERENCES public.store_transfer_list(store_transfer_id),

  -- Product reference, FK to mother_inventory_list
  -- 商品引用，外键指向 mother_inventory_list
  unique_id integer NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- Serialized unit reference: required for serialized items, must be NULL for non-serialized
  -- Consistency validated by trigger (see below)
  -- 序列号单件引用：serialized 商品必填，非 serialized 商品应为 NULL
  -- 一致性由触发器校验（见下方）
  unit_id integer DEFAULT NULL REFERENCES public.store_serialized_list(unit_id),

  -- Product name snapshot (denormalized, copied by client at transfer time)
  -- 商品名称快照（冗余字段，由客户端在调拨时复制）
  item_name text NOT NULL,

  -- Cost per unit snapshot at transfer time
  -- 调拨时的单位成本快照
  cost_per_unit numeric(10,2) NOT NULL DEFAULT 0,

  -- Retail price per unit snapshot at transfer time
  -- 调拨时的单位零售价快照
  price_per_unit numeric(10,2) NOT NULL DEFAULT 0,

  -- Transfer quantity: must be > 0; serialized items must be 1
  -- 调拨数量：必须大于 0；serialized 商品必须为 1
  qty integer NOT NULL,

  -- Serial number text: only for serialized items (copied from store_serialized_list)
  -- 序列号文本：仅 serialized 商品有值（从 store_serialized_list 复制）
  serial text DEFAULT NULL,

  -- CHECK: quantity must be positive (no zero or negative transfers)
  -- 约束：数量必须为正数（调拨不允许 0 或负数）
  CONSTRAINT chk_store_transfer_line_list_qty_positive
    CHECK (qty > 0)
);

-- =============================================
-- Trigger: validate inventory_mode consistency for transfer lines
-- 触发器：校验调拨明细行的 inventory_mode 一致性
-- =============================================
-- Rules:
--   service    → reject (service items have no inventory to transfer)
--   serialized → qty must be 1, unit_id and serial must be set
--   tracked / untracked → unit_id and serial must be NULL
-- 规则：
--   service    → 拒绝（服务类无库存，无需调拨）
--   serialized → qty 必须为 1，unit_id 和 serial 必须有值
--   tracked / untracked → unit_id 和 serial 必须为 NULL
-- =============================================
CREATE OR REPLACE FUNCTION public.transfer_line_enforce_mode()
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

  -- Service items cannot be transferred (no inventory to move)
  -- service 商品不可调拨（无库存可移动）
  IF v_mode = 'service' THEN
    RAISE EXCEPTION 'service item (unique_id=%) cannot be transferred', NEW.unique_id;
  END IF;

  -- Serialized items: qty must be 1, must have unit_id and serial
  -- serialized 商品：qty 必须为 1，必须有 unit_id 和 serial
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

  -- Tracked / untracked items: must NOT have unit_id or serial
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

-- =============================================
-- Indexes / 索引
-- =============================================

-- Look up all line items for a given transfer
-- 查询某次调拨的所有明细行
CREATE INDEX IF NOT EXISTS idx_transfer_line_transfer
  ON public.store_transfer_line_list (store_transfer_id);

-- Look up transfer history for a specific product
-- 查询某商品的调拨历史
CREATE INDEX IF NOT EXISTS idx_transfer_line_unique_id
  ON public.store_transfer_line_list (unique_id);

-- Look up transfer history for a specific serialized unit
-- 查询某序列号单件的调拨记录
CREATE INDEX IF NOT EXISTS idx_transfer_line_unit_id
  ON public.store_transfer_line_list (unit_id)
  WHERE unit_id IS NOT NULL;
