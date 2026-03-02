-- =========================================
-- 13 · transaction_line_list 交易明细表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        06_mother_inventory_list (unique_id FK)
--        06 中的 ENUM inventory_mode
--        09_store_serialized_list (unit_id FK)
--        12_transaction_list (transaction_id FK)
-- 被依赖: 无
--
-- 每笔交易（transaction_list）包含一条或多条明细行
-- 支持离线创建：主键由客户端生成 UUID v7，所有字段值由客户端计算填入
-- 数据库通过 CHECK 约束兜底校验计算正确性

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.transaction_line_list (

  -- 明细行全局唯一主键，由客户端生成 UUID v7
  line_id uuid PRIMARY KEY,

  -- 所属交易，外键指向 transaction_list
  transaction_id uuid NOT NULL REFERENCES public.transaction_list(transaction_id),

  -- 门店 ID（冗余字段，避免高频查询时 JOIN transaction_list）
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 关联母表商品，不允许为空（每条明细应对应一个系统内商品）
  unique_id integer NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- 序列号商品关联：serialized 商品应有值，非 serialized 商品应为 NULL
  -- 由触发器校验一致性（见下方 Trigger A）
  unit_id integer DEFAULT NULL REFERENCES public.store_serialized_list(unit_id),

  -- 商品名称，由客户端从母表读取后填入，UI 层面允许修改
  -- 数据库不做自动继承触发器（离线场景下无法访问母表）
  item_name text NOT NULL,

  -- 数量：可以为 0（如纯服务项）、可以为负（如退货行）
  qty integer NOT NULL,

  -- 单位成本：由客户端从 store_inventory_list 或 store_serialized_list 读取
  cost_per_unit numeric(10,2) NOT NULL DEFAULT 0,

  -- 单位售价：由客户端从 store_inventory_list 或 store_serialized_list 读取
  price_per_unit numeric(10,2) NOT NULL DEFAULT 0,

  -- 该行折扣金额（正数表示优惠）
  line_discount numeric(10,2) NOT NULL DEFAULT 0,

  -- 该行税额
  line_tax numeric(10,2) NOT NULL DEFAULT 0,

  -- 该行税前金额 = qty × price_per_unit − line_discount
  line_total_before_tax numeric(10,2) NOT NULL DEFAULT 0,

  -- 该行税后总额 = line_total_before_tax + line_tax（客户最终支付金额）
  line_total numeric(10,2) NOT NULL DEFAULT 0,

  -- 该行利润 = line_total_before_tax − qty × cost_per_unit
  line_profit numeric(10,2) NOT NULL DEFAULT 0,

  -- 编辑时间戳：NULL 表示未被编辑过，有值 = 最近一次编辑时间
  edited_at timestamptz DEFAULT NULL,

  -- 软删除时间戳
  deleted_at timestamptz DEFAULT NULL,

  -- =========================================
  -- 兜底校验：确保客户端计算正确，阻止脏数据入库
  -- =========================================
  CONSTRAINT line_total_before_tax_check
    CHECK (line_total_before_tax = qty * price_per_unit - line_discount),

  CONSTRAINT line_total_check
    CHECK (line_total = line_total_before_tax + line_tax),

  CONSTRAINT line_profit_check
    CHECK (line_profit = line_total_before_tax - qty * cost_per_unit)
);

-- =========================================
-- Trigger A：校验 unit_id 与 inventory_mode 的一致性
-- =========================================
-- serialized 商品应提供 unit_id，非 serialized 商品 unit_id 应为 NULL
-- 本触发器在数据同步到服务端时执行，离线期间不生效
CREATE OR REPLACE FUNCTION public.transaction_line_enforce_unit_id()
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

  -- serialized 商品应关联具体单件
  IF v_mode = 'serialized' AND NEW.unit_id IS NULL THEN
    RAISE EXCEPTION 'serialized item (unique_id=%) requires unit_id', NEW.unique_id;
  END IF;

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

-- =========================================
-- 索引
-- =========================================

-- 查询某笔交易的所有明细行（最高频查询）
CREATE INDEX IF NOT EXISTS idx_transaction_line_transaction
  ON public.transaction_line_list (transaction_id)
  WHERE deleted_at IS NULL;

-- 查询门店的所有明细行（报表场景）
CREATE INDEX IF NOT EXISTS idx_transaction_line_store
  ON public.transaction_line_list (store_id)
  WHERE deleted_at IS NULL;

-- 查询商品的销售记录
CREATE INDEX IF NOT EXISTS idx_transaction_line_unique_id
  ON public.transaction_line_list (unique_id)
  WHERE deleted_at IS NULL;

-- 查询序列号单件的交易记录
CREATE INDEX IF NOT EXISTS idx_transaction_line_unit_id
  ON public.transaction_line_list (unit_id)
  WHERE unit_id IS NOT NULL AND deleted_at IS NULL;
