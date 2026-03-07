-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: YES - offline POS must continue high-frequency essential operations using local snapshot; sync changes to cloud after reconnection.
-- 异步需求：是 - POS 离线时需依赖本地快照继续高频必要操作，网络恢复后将变更同步到云端。
-- =============================================
-- File 13 · transaction_line_list — Transaction line item table
-- 文件 13 · transaction_line_list — 交易明细行表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list            (store_id FK)
--   06_mother_inventory_list (unique_id FK + inventory_mode ENUM)
--   09_store_serialized_list (unit_id FK)
--   12_transaction_list      (transaction_id FK)
-- Dependents / 被依赖:
--   (none) （无）
-- =============================================
-- Each transaction (transaction_list) contains one or more line items.
-- Supports offline creation: PK is a UUID v7 generated client-side.
-- All monetary values are calculated by the client; the database validates via CHECK constraints.
-- ─────────────────────────────────────────────
-- 每笔交易（transaction_list）包含一条或多条明细行。
-- 支持离线创建：主键由客户端生成 UUID v7。
-- 所有金额由客户端计算，数据库通过 CHECK 约束兜底校验。
-- =============================================

CREATE TABLE IF NOT EXISTS public.transaction_line_list (

  -- UUID v7 primary key, generated client-side for offline support
  -- UUID v7 主键，由客户端生成，支持离线
  line_id uuid PRIMARY KEY,

  -- Parent transaction, FK to transaction_list
  -- 所属交易，外键指向 transaction_list
  transaction_id uuid NOT NULL REFERENCES public.transaction_list(transaction_id),

  -- Store ID (denormalized to avoid frequent JOINs with transaction_list for queries)
  -- 门店 ID（冗余字段，避免高频查询时 JOIN transaction_list）
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Product reference, FK to mother_inventory_list (required — every line must map to a catalog item)
  -- 母表商品引用，外键指向 mother_inventory_list（必填 — 每条明细必须对应一个目录商品）
  unique_id integer NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- Serialized unit reference: required for serialized items, must be NULL for non-serialized
  -- Consistency validated by trigger (see Trigger A below)
  -- 序列号单件引用：serialized 商品必填，非 serialized 商品应为 NULL
  -- 一致性由触发器校验（见下方触发器 A）
  unit_id integer DEFAULT NULL REFERENCES public.store_serialized_list(unit_id),

  -- Product name snapshot: copied from catalog by the client at transaction time
  -- The client may allow manual edits; DB does NOT auto-inherit (offline can't access catalog)
  -- 商品名称快照：交易时由客户端从目录复制
  -- 客户端 UI 层面允许修改；数据库不做自动继承触发器（离线场景下无法访问母表）
  item_name text NOT NULL,

  -- Quantity: can be 0 (pure service item) or negative (return/refund line)
  -- 数量：可以为 0（纯服务项）或负数（退货行）
  qty integer NOT NULL,

  -- Cost per unit: read by client from store_inventory_list or store_serialized_list
  -- 单位成本：由客户端从 store_inventory_list 或 store_serialized_list 读取
  cost_per_unit numeric(10,2) NOT NULL DEFAULT 0,

  -- Selling price per unit: read by client from store_inventory_list or store_serialized_list
  -- 单位售价：由客户端从 store_inventory_list 或 store_serialized_list 读取
  price_per_unit numeric(10,2) NOT NULL DEFAULT 0,

  -- Discount amount for this line (positive value = money off)
  -- 该行折扣金额（正数表示优惠金额）
  line_discount numeric(10,2) NOT NULL DEFAULT 0,

  -- Tax amount for this line
  -- 该行税额
  line_tax numeric(10,2) NOT NULL DEFAULT 0,

  -- Pre-tax line total = qty × price_per_unit − line_discount (validated by CHECK)
  -- 税前行总额 = qty × price_per_unit − line_discount（由 CHECK 约束校验）
  line_total_before_tax numeric(10,2) NOT NULL DEFAULT 0,

  -- Line total including tax = line_total_before_tax + line_tax (validated by CHECK)
  -- 含税行总额 = line_total_before_tax + line_tax（由 CHECK 约束校验）
  line_total numeric(10,2) NOT NULL DEFAULT 0,

  -- Line profit = line_total_before_tax − qty × cost_per_unit (validated by CHECK)
  -- 行利润 = line_total_before_tax − qty × cost_per_unit（由 CHECK 约束校验）
  line_profit numeric(10,2) NOT NULL DEFAULT 0,

  -- Last edit timestamp; NULL = never edited, non-NULL = time of most recent edit
  -- 编辑时间戳；NULL 表示未被编辑过，有值 = 最近一次编辑时间
  edited_at timestamptz DEFAULT NULL,

  -- Soft delete timestamp; NULL = active, non-NULL = voided
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已作废
  deleted_at timestamptz DEFAULT NULL,

  -- =============================================
  -- CHECK constraints: validate client-side calculations to prevent dirty data
  -- 兜底校验：确保客户端计算正确，阻止脏数据入库
  -- =============================================

  -- CHECK: line_total_before_tax = qty × price_per_unit − line_discount
  -- 约束：税前行总额 = 数量 × 单价 − 折扣
  CONSTRAINT chk_transaction_line_list_total_before_tax
    CHECK (line_total_before_tax = qty * price_per_unit - line_discount),

  -- CHECK: line_total = line_total_before_tax + line_tax
  -- 约束：含税行总额 = 税前行总额 + 税额
  CONSTRAINT chk_transaction_line_list_total
    CHECK (line_total = line_total_before_tax + line_tax),

  -- CHECK: line_profit = line_total_before_tax − qty × cost_per_unit
  -- 约束：行利润 = 税前行总额 − 数量 × 单位成本
  CONSTRAINT chk_transaction_line_list_profit
    CHECK (line_profit = line_total_before_tax - qty * cost_per_unit)
);

-- =============================================
-- Trigger A: validate unit_id consistency with inventory_mode
-- 触发器 A：校验 unit_id 与 inventory_mode 的一致性
-- =============================================
-- Serialized items must provide unit_id; non-serialized items must have unit_id = NULL.
-- This trigger fires on sync to Supabase; it does NOT apply during offline operation.
-- ─────────────────────────────────────────────
-- serialized 商品应提供 unit_id，非 serialized 商品 unit_id 应为 NULL。
-- 本触发器在数据同步到 Supabase 时执行，离线期间不生效。
-- =============================================
CREATE OR REPLACE FUNCTION public.transaction_line_enforce_unit_id()
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

  -- Serialized items must reference a specific unit
  -- serialized 商品应关联具体单件
  IF v_mode = 'serialized' AND NEW.unit_id IS NULL THEN
    RAISE EXCEPTION 'serialized item (unique_id=%) requires unit_id', NEW.unique_id;
  END IF;

  -- Non-serialized items must NOT have a unit_id
  -- 非 serialized 商品不应该有 unit_id
  IF v_mode IS DISTINCT FROM 'serialized' AND NEW.unit_id IS NOT NULL THEN
    RAISE EXCEPTION 'non-serialized item (unique_id=%) must not have unit_id', NEW.unique_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_transaction_line_enforce_unit_id ON public.transaction_line_list;
CREATE TRIGGER trg_transaction_line_enforce_unit_id
BEFORE INSERT OR UPDATE ON public.transaction_line_list
FOR EACH ROW
EXECUTE FUNCTION public.transaction_line_enforce_unit_id();

-- =============================================
-- Indexes / 索引
-- =============================================

-- Most frequent query: list all line items for a transaction (active only)
-- 最高频查询：列出某笔交易的所有明细行（仅活跃记录）
CREATE INDEX IF NOT EXISTS idx_transaction_line_transaction
  ON public.transaction_line_list (transaction_id)
  WHERE deleted_at IS NULL;

-- List all line items for a store (report scenarios)
-- 列出门店的所有明细行（报表场景）
CREATE INDEX IF NOT EXISTS idx_transaction_line_store
  ON public.transaction_line_list (store_id)
  WHERE deleted_at IS NULL;

-- Look up sales history for a specific product
-- 查询某商品的销售记录
CREATE INDEX IF NOT EXISTS idx_transaction_line_unique_id
  ON public.transaction_line_list (unique_id)
  WHERE deleted_at IS NULL;

-- Look up transaction history for a specific serialized unit
-- 查询某序列号单件的交易记录
CREATE INDEX IF NOT EXISTS idx_transaction_line_unit_id
  ON public.transaction_line_list (unit_id)
  WHERE unit_id IS NOT NULL AND deleted_at IS NULL;
