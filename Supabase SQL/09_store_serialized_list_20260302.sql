-- =============================================
-- File 09 · store_serialized_list — Serialized item inventory table
-- 文件 09 · store_serialized_list — 序列号商品库存表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list            (store_id FK)
--   06_mother_inventory_list (unique_id FK + inventory_mode ENUM)
-- Dependents / 被依赖:
--   13_transaction_line_list      (unit_id FK)
--   16_serialized_event_list      (unit_id FK)
--   18_store_transfer_line_list   (unit_id FK)
--   21_purchase_order_line_list   (unit_id FK)
-- Shared components created here / 本文件创建的共享组件:
--   ENUM public.serialized_status — also used by 16_serialized_event_list
--   Function public.mother_inventory_block_mode_change() — trigger on mother_inventory_list
-- =============================================
-- Each row represents ONE physical unit of a serialized product (e.g., a phone with an IMEI).
-- Only for products where inventory_mode = 'serialized'.
-- ─────────────────────────────────────────────
-- 每一行代表一件序列号商品的实物（如一部有 IMEI 的手机）。
-- 仅适用于 inventory_mode = 'serialized' 的商品。
-- =============================================

-- =============================================
-- ENUM: serialized_status — Lifecycle status of a serialized unit
-- 枚举：serialized_status — 序列号商品的生命周期状态
-- =============================================
-- >>> Also referenced by 16_serialized_event_list <<<
-- >>> 也被 16_serialized_event_list 引用 <<<
--
--   in_stock   = In stock, available for sale / 在库，可售
--   in_transit = Being transferred between stores / 调拨途中
--   sold       = Sold to a customer / 已售出
--   repair     = Sent out for external repair / 送外部维修中
--   lost       = Marked as lost / 标记为丢失
--   wasted     = Marked as damaged/wasted / 标记为损坏/报废
--   void       = Voided (logical deletion of the unit record) / 作废（逻辑删除该单件记录）
DO $$
BEGIN
  CREATE TYPE public.serialized_status AS ENUM ('in_stock', 'in_transit', 'sold', 'repair', 'lost', 'wasted', 'void');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.store_serialized_list (

  -- Auto-increment PK for each physical unit; starting from 0
  -- 每件实物的自增主键，从 0 开始
  unit_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- Store ID, FK to store_list (the store currently holding this unit)
  -- 门店 ID，外键指向 store_list（当前持有该单件的门店）
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Globally unique serial number (e.g., IMEI, SN); NEVER reused even after void/soft-delete
  -- 全局唯一序列号（如 IMEI、SN）；即使作废/软删除后仍永久占位，不可复用
  serial text NOT NULL,

  -- Product reference, FK to mother_inventory_list (must be inventory_mode = 'serialized')
  -- 商品引用，外键指向 mother_inventory_list（必须是 inventory_mode = 'serialized'）
  unique_id int NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- Extra attributes for this unit as free-form JSONB (e.g., color, capacity, condition)
  -- Example: {"color": "Space Black", "capacity": "256GB", "condition": "A+"}
  -- 单件额外属性，自由格式 JSONB（如颜色、容量、成色等）
  -- 例如：{"color": "Space Black", "capacity": "256GB", "condition": "A+"}
  attribute jsonb DEFAULT NULL,

  -- Unit cost; on INSERT, if NULL, auto-inherited from mother table default_cost
  -- 单件成本；INSERT 时若为空，自动从母表 default_cost 继承；之后独立更新
  cost numeric(10,2) DEFAULT NULL,

  -- Unit retail price; on INSERT, if NULL, auto-inherited from mother table default_price
  -- 单件零售价；INSERT 时若为空，自动从母表 default_price 继承；之后独立更新
  price numeric(10,2) DEFAULT NULL,

  -- Minimum suggested price for sales staff; advisory only
  -- 前台最低报价指导价，仅供参考
  last_price numeric(10,2) DEFAULT NULL,

  -- Current lifecycle status of this unit (see serialized_status ENUM above)
  -- 单件当前业务状态（参见上方 serialized_status 枚举）
  status public.serialized_status NOT NULL DEFAULT 'in_stock',

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Soft delete timestamp; NULL = active, non-NULL = deleted
  -- Note: even after soft delete, the serial is still reserved (global unique constraint has no WHERE filter)
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已删除
  -- 注意：软删除后 serial 仍占位，不可复用（全局唯一约束不带 WHERE 条件）
  deleted_at timestamptz DEFAULT NULL
);

-- =============================================
-- Serial global unique constraint (DEFERRABLE, supports in-transaction swaps)
-- Not a partial index: serial stays reserved even after soft-delete or void,
-- guaranteeing lifetime uniqueness across all records.
-- ─────────────────────────────────────────────
-- serial 全局唯一约束（DEFERRABLE，支持事务内互换）
-- 不使用 partial index：即使 deleted_at IS NOT NULL 或 status = 'void'，
-- serial 仍不可被新记录复用，保证全生命周期唯一。
-- =============================================
DO $$
BEGIN
  ALTER TABLE public.store_serialized_list
    ADD CONSTRAINT uq_store_serialized_serial
    UNIQUE (serial)
    DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Trigger A: validate mother table mode = 'serialized' + inherit cost/price on INSERT
-- 触发器 A：校验母表 inventory_mode = 'serialized' + INSERT 时继承 cost/price
-- =============================================
CREATE OR REPLACE FUNCTION public.store_serialized_enforce_mode()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Variable legend / 变量说明:
  --   v_mode  = inventory_mode from mother table / 母表的库存跟踪模式
  --   m_cost  = default_cost from mother table / 母表的默认成本
  --   m_price = default_price from mother table / 母表的默认价格
  v_mode  public.inventory_mode;
  m_cost  numeric(10,2);
  m_price numeric(10,2);
BEGIN
  -- Read inventory_mode and default prices from mother table
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

  -- On INSERT only: inherit default cost/price (UPDATE preserves unit-specific values)
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

-- =============================================
-- Trigger: auto-refresh updated_at (reuses set_updated_at() from file 03)
-- 触发器：自动刷新 updated_at（复用 03_user_list 中的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_store_serialized_list_updated_at ON public.store_serialized_list;
CREATE TRIGGER trg_store_serialized_list_updated_at
BEFORE UPDATE ON public.store_serialized_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Indexes / 索引
-- =============================================

-- Query a store's serialized items filtered by status (e.g., in_stock units for sale)
-- 查询门店的序列号商品，按状态筛选（如查找在库可售的单件）
CREATE INDEX IF NOT EXISTS idx_store_serialized_store_status
  ON public.store_serialized_list (store_id, status);

-- Query all serialized units for a given product (across all stores)
-- 查询某商品的所有序列号单件（跨门店）
CREATE INDEX IF NOT EXISTS idx_store_serialized_unique_id
  ON public.store_serialized_list (unique_id);

-- Quick lookup of active (non-deleted) serialized items in a store
-- 快速查找门店内活跃（未删除）的序列号商品
CREATE INDEX IF NOT EXISTS idx_store_serialized_active
  ON public.store_serialized_list (store_id)
  WHERE deleted_at IS NULL;

-- =============================================
-- =============================================
-- Mother table trigger: mother_inventory_block_mode_change()
-- 母表触发器：mother_inventory_block_mode_change()
-- =============================================
-- =============================================
-- Blocks changes to inventory_mode on mother_inventory_list when active store inventory rows exist.
-- Checks BOTH store_inventory_list (service/tracked/untracked) AND store_serialized_list (serialized).
-- Proper workflow: UI guides the user to soft-delete all store rows first, then change the mode.
-- This trigger is the last line of defense, preventing any entry point (UI/API/script) from bypassing.
-- ─────────────────────────────────────────────
-- 当有活跃的门店库存行时，拦截母表 inventory_mode 变更。
-- 同时检查 store_inventory_list（service/tracked/untracked）和 store_serialized_list（serialized）。
-- 正常流程：UI 引导用户先将所有门店的该商品行软删除（或迁移），再修改母表 mode。
-- 本触发器作为最后一道防线，杜绝任何入口（UI/API/脚本）绕过本约束。
-- =============================================
CREATE OR REPLACE FUNCTION public.mother_inventory_block_mode_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Variable legend / 变量说明:
  --   active_inv = count of active rows in store_inventory_list / store_inventory_list 中的活跃行数
  --   active_ser = count of active rows in store_serialized_list / store_serialized_list 中的活跃行数
  active_inv  int;
  active_ser  int;
BEGIN
  -- Only intercept when inventory_mode actually changes
  -- 仅在 inventory_mode 实际发生变化时才拦截
  IF NEW.inventory_mode IS DISTINCT FROM OLD.inventory_mode THEN

    -- Check store_inventory_list for active rows (service / tracked / untracked)
    -- 检查 store_inventory_list 中是否有活跃行（service / tracked / untracked）
    SELECT COUNT(*)
      INTO active_inv
    FROM public.store_inventory_list
    WHERE unique_id = NEW.unique_id
      AND deleted_at IS NULL;

    -- Check store_serialized_list for active rows (serialized)
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
