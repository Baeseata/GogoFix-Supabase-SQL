-- =========================================
-- 06 · mother_inventory_list 全局商品母表
-- =========================================
-- 依赖: 01_store_list (created_store_id FK)
--        05_supplier_list (supplier_id FK)
-- 被依赖: 08_store_inventory_list, 09_store_serialized_list,
--         13_transaction_line_list, 15_adjustment_line_list,
--         18_store_transfer_line_list, 19_store_item_history_list,
--         21_purchase_order_line_list, 23_repair_ticket_line_list

-- =========================================
-- ENUM: inventory_mode 库存跟踪模式
-- =========================================
-- >>> 被以下文件的触发器引用 <<<
-- 08_store_inventory_list, 09_store_serialized_list,
-- 13_transaction_line_list, 15_adjustment_line_list,
-- 18_store_transfer_line_list, 21_purchase_order_line_list
--
--   service    = 服务类商品，不记录库存
--   untracked  = 不精确跟踪（模糊库存，可记录大概数量）
--   tracked    = 精确数量跟踪
--   serialized = 序列号管理跟踪（每件唯一）
DO $$
BEGIN
  CREATE TYPE public.inventory_mode AS ENUM ('service', 'untracked', 'tracked', 'serialized');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- ENUM: valuation_method 商品成本估值方式
-- =========================================
--   average = 加权滑动平均成本
--   rate    = 按固定比率计算（如进价×系数）
--   fixed   = 固定成本，手动指定不自动更新
DO $$
BEGIN
  CREATE TYPE public.valuation_method AS ENUM ('average', 'rate', 'fixed');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- 函数: assign_variant_id_per_item()
-- =========================================
-- variant_id 按 item_id 分组自动分配函数：
-- 同一 item_id 下，variant_id 从 0 开始依次递增（0, 1, 2...）
-- 使用行级咨询锁（pg_advisory_xact_lock）阻止并发插入时产生重复编号
-- 注意：本处使用 COUNT(*) 作为下一个 variant_id：
-- 若该 item_id 已有 N 条记录（含软删除），新记录的 variant_id = N
-- 这保证了同一 item_id 下 variant_id 从 0 开始单调递增
-- 警告：软删除的记录仍会被计入，因此 variant_id 序列中可能出现"空洞"
-- （例如 variant_id=1 已软删除，但序号不会被复用）
CREATE OR REPLACE FUNCTION public.assign_variant_id_per_item()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_vid int;
BEGIN
  -- 防御性
  IF NEW.item_id IS NULL THEN
    RAISE EXCEPTION 'item_id cannot be null';
  END IF;

  -- 同一 item_id 串行：第一个参数是"命名空间"，随值挑个常数避免和别处冲突
  PERFORM pg_advisory_xact_lock(1001, NEW.item_id);

  SELECT COUNT(*)::int
    INTO next_vid
  FROM public.mother_inventory_list
  WHERE item_id = NEW.item_id;  -- 软删除亦计

  NEW.variant_id := next_vid;
  RETURN NEW;
END;
$$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.mother_inventory_list (
  -- 全局唯一主键，IDENTITY 自动生成，从 0 开始递增，业务端不应直接使用本值做关联
  unique_id integer GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0) PRIMARY KEY,

  -- 商品编号（item_id），同一商品的不同规格共享同一 item_id，范围限定 100000~999999
  item_id integer NOT NULL,

  -- 规格编号（variant_id），同一 item_id 下从 0 开始自动分配，0 表示默认/唯一规格
  variant_id integer NOT NULL DEFAULT 0,

  -- 商品条码（UPC），支持多条码绑定，允许为空，允许与其他条目重复
  item_upc text[] NOT NULL DEFAULT '{}'::text[],

  -- 商品名字
  item_name text NOT NULL,

  -- 树形分类路径，空数组表示"未分类"，数组元素按顺序表示从几分类到子分类
  category_path text[] NOT NULL DEFAULT '{}'::text[],

  -- 商品描述
  description text DEFAULT NULL,

  -- 商品生产商
  manufacture text DEFAULT NULL,

  -- 供应商 FK（替代旧的 text 类型 supplier 字段）
  supplier_id integer DEFAULT NULL REFERENCES public.supplier_list(supplier_id),

  -- 适配设备型号列表，主要用于维修配件，以数组形式记录该配件兼容的设备型号字符串
  device_compatibility text[] NOT NULL DEFAULT '{}'::text[],

  -- 库存跟踪模式，参见 inventory_mode 枚举定义
  inventory_mode public.inventory_mode NOT NULL,

  -- 成本估值方式，参见 valuation_method 枚举定义，默认使用加权滑动平均
  valuation_method public.valuation_method NOT NULL DEFAULT 'average',

  -- 默认成本
  default_cost numeric(10,2),

  -- 默认零售价格
  default_price numeric(10,2),

  -- 创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- 更新时间
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 创建该商品的门店
  created_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 软删除时间
  deleted_at timestamptz DEFAULT NULL,

  -- item_id 范围约束
  CONSTRAINT mother_inventory_list_item_id_range
    CHECK (item_id BETWEEN 100000 AND 999999)
);

-- =========================================
-- 业务唯一性：同一 item_id 下，variant_id 全局绝对唯一
-- =========================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_mother_item_variant
ON public.mother_inventory_list (item_id, variant_id);

-- =========================================
-- Triggers
-- =========================================

-- updated_at（复用 03_user_list 中创建的 public.set_updated_at()）
DROP TRIGGER IF EXISTS trg_mother_inventory_list_updated_at ON public.mother_inventory_list;
CREATE TRIGGER trg_mother_inventory_list_updated_at
BEFORE UPDATE ON public.mother_inventory_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- variant_id 分配
DROP TRIGGER IF EXISTS trg_mother_inventory_list_assign_variant_id ON public.mother_inventory_list;
CREATE TRIGGER trg_mother_inventory_list_assign_variant_id
BEFORE INSERT ON public.mother_inventory_list
FOR EACH ROW
EXECUTE FUNCTION public.assign_variant_id_per_item();

-- =========================================
-- Indexes
-- =========================================
CREATE INDEX IF NOT EXISTS idx_mother_inventory_list_item_id
  ON public.mother_inventory_list (item_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_mother_inventory_list_inventory_mode
  ON public.mother_inventory_list (inventory_mode);

CREATE INDEX IF NOT EXISTS gin_mother_inventory_list_category_path
  ON public.mother_inventory_list USING gin (category_path);

CREATE INDEX IF NOT EXISTS gin_mother_inventory_list_device_compatibility
  ON public.mother_inventory_list USING gin (device_compatibility);

CREATE INDEX IF NOT EXISTS gin_mother_item_upc
  ON public.mother_inventory_list USING gin (item_upc);
