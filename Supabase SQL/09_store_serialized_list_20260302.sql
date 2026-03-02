-- =========================================
-- 09 · store_serialized_list 序列号商品库存表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        06_mother_inventory_list (unique_id FK)
--        06 中的 ENUM inventory_mode
-- 被依赖: 13_transaction_line_list (unit_id FK)
--         16_serialized_event_list (unit_id FK)
--         18_store_transfer_line_list (unit_id FK)
--         21_purchase_order_line_list (unit_id FK)
--
-- serialized item 库存表：每一行代表一件实物，仅适用于 inventory_mode = 'serialized' 的商品

-- =========================================
-- ENUM: serialized_status 序列号商品状态枚举
-- =========================================
-- >>> 也被 16_serialized_event_list 扩展（新增 lost, wasted）<<<
--
--   in_stock   = 在库
--   in_transit = 调拨途中
--   sold       = 已售出
--   repair     = 送修中
--   lost       = 丢失
--   wasted     = 报废
--   void       = 作废
DO $$
BEGIN
  CREATE TYPE public.serialized_status AS ENUM ('in_stock', 'in_transit', 'sold', 'repair', 'lost', 'wasted', 'void');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.store_serialized_list (

  -- 全局自增主键，从 0 开始，业务端不应手动指定
  unit_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 门店 ID
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 全局唯一序列号（如 IMEI、SN），不可复用，即使 void / 软删除后仍永久占位
  serial text NOT NULL,

  -- 关联 mother_inventory_list 的全局唯一主键
  unique_id int NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- 单件额外属性（颜色、容量、成色等），结构自由
  attribute jsonb DEFAULT NULL,

  -- 该单件的实际成本
  -- INSERT 时若为空，自动从母表 default_cost 继承；之后独立更新
  cost numeric(10,2) DEFAULT NULL,

  -- 该单件的当前售价
  -- INSERT 时若为空，自动从母表 default_price 继承；之后独立更新
  price numeric(10,2) DEFAULT NULL,

  -- 前台最低报价指导价
  last_price numeric(10,2) DEFAULT NULL,

  -- 单件当前业务状态
  status public.serialized_status NOT NULL DEFAULT 'in_stock',

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已删除
  -- 注意：软删除后 serial 仍占位，不可复用（全局唯一约束不带 WHERE 条件）
  deleted_at timestamptz DEFAULT NULL
);

-- =========================================
-- serial 全局唯一约束（DEFERRABLE，支持事务内互换）
-- =========================================
-- 不使用 partial index：即使 deleted_at IS NOT NULL 或 status = 'void'，
-- serial 仍概不可被新记录复用，保证全生命周期唯一
DO $$
BEGIN
  ALTER TABLE public.store_serialized_list
    ADD CONSTRAINT uq_store_serialized_serial
    UNIQUE (serial)
    DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- Trigger A：校验母表 inventory_mode = 'serialized'，并在 INSERT 时继承 cost/price
-- =========================================
CREATE OR REPLACE FUNCTION public.store_serialized_enforce_mode()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_mode  public.inventory_mode;
  m_cost  numeric(10,2);
  m_price numeric(10,2);
BEGIN
  -- 从母表读取 inventory_mode 及默认价格
  SELECT inventory_mode, default_cost, default_price
    INTO v_mode, m_cost, m_price
  FROM public.mother_inventory_list
  WHERE unique_id = NEW.unique_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'mother_inventory_list.unique_id % not found', NEW.unique_id;
  END IF;

  IF v_mode IS DISTINCT FROM 'serialized' THEN
    RAISE EXCEPTION 'unique_id % is not serialized (mode=%)', NEW.unique_id, v_mode;
  END IF;

  -- 仅 INSERT 时从母表继承默认 cost/price；UPDATE 时不覆盖（单件价格独立更新）
  IF TG_OP = 'INSERT' THEN
    IF NEW.cost  IS NULL THEN NEW.cost  := m_cost;  END IF;
    IF NEW.price IS NULL THEN NEW.price := m_price; END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_store_serialized_enforce_mode ON public.store_serialized_list;
CREATE TRIGGER trg_store_serialized_enforce_mode
BEFORE INSERT OR UPDATE ON public.store_serialized_list
FOR EACH ROW
EXECUTE FUNCTION public.store_serialized_enforce_mode();

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_store_serialized_updated_at ON public.store_serialized_list;
CREATE TRIGGER trg_store_serialized_updated_at
BEFORE UPDATE ON public.store_serialized_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 索引
-- =========================================

-- 查询门店的序列号商品（按状态过滤）
CREATE INDEX IF NOT EXISTS idx_store_serialized_store_status
  ON public.store_serialized_list (store_id, status);

-- 查询 SKU 的所有序列号单件
CREATE INDEX IF NOT EXISTS idx_store_serialized_unique_id
  ON public.store_serialized_list (unique_id);

-- 软删除过滤：查活跃记录
CREATE INDEX IF NOT EXISTS idx_store_serialized_active
  ON public.store_serialized_list (store_id)
  WHERE deleted_at IS NULL;

-- =========================================
-- =========================================
-- 母表触发器: mother_inventory_block_mode_change()
-- =========================================
-- =========================================
-- 拦截母表 inventory_mode 变更：
-- 当有活跃的门店库存行（store_inventory_list 或 store_serialized_list）时，
-- 禁止直接修改 mode。
-- 正常流程：UI 引导用户先将所有门店的该商品行软删除（或迁移），再修改母表 mode。
-- 这样数据库作为最后一道防线，杜绝任何入口（UI/API/脚本）绕过本约束。
CREATE OR REPLACE FUNCTION public.mother_inventory_block_mode_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  active_inv  int;
  active_ser  int;
BEGIN
  -- 仅在 inventory_mode 实际发生变化时才拦截
  IF NEW.inventory_mode IS DISTINCT FROM OLD.inventory_mode THEN

    -- 检查 store_inventory_list 中是否有活跃行（service / tracked / untracked）
    SELECT COUNT(*)
      INTO active_inv
    FROM public.store_inventory_list
    WHERE unique_id = NEW.unique_id
      AND deleted_at IS NULL;

    -- 检查 store_serialized_list 中是否有活跃行（serialized）
    SELECT COUNT(*)
      INTO active_ser
    FROM public.store_serialized_list
    WHERE unique_id = NEW.unique_id
      AND deleted_at IS NULL;

    IF (active_inv + active_ser) > 0 THEN
      RAISE EXCEPTION
        'Cannot change inventory_mode for unique_id %: '
        '% active store_inventory row(s) + % active store_serialized row(s) exist. '
        'Soft-delete all store rows first, then retry.',
        NEW.unique_id, active_inv, active_ser;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mother_inventory_block_mode_change ON public.mother_inventory_list;
CREATE TRIGGER trg_mother_inventory_block_mode_change
BEFORE UPDATE ON public.mother_inventory_list
FOR EACH ROW
EXECUTE FUNCTION public.mother_inventory_block_mode_change();
