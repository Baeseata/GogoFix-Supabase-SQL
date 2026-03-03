-- =============================================
-- File 06 · mother_inventory_list — Global product catalog
-- 文件 06 · mother_inventory_list — 全局商品母表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list    (created_store_id FK)
--   05_supplier_list (supplier_id FK)
-- Dependents / 被依赖:
--   08_store_inventory_list, 09_store_serialized_list,
--   13_transaction_line_list, 15_adjustment_line_list,
--   18_store_transfer_line_list, 19_store_item_history_list,
--   21_purchase_order_line_list, 23_repair_ticket_line_list
-- Shared components created here / 本文件创建的共享组件:
--   ENUM  public.inventory_mode  — also used by 08, 09, 13, 15, 18, 21
--   ENUM  public.valuation_method — this table only
--   Function public.assign_variant_id_per_item() — this table only
-- =============================================

-- =============================================
-- ENUM: inventory_mode — Inventory tracking mode
-- 枚举：inventory_mode — 库存跟踪模式
-- =============================================
-- >>> Referenced by trigger functions in files 08, 09, 13, 15, 18, 21 <<<
-- >>> 被以下文件的触发器函数引用：08, 09, 13, 15, 18, 21 <<<
--
--   service    = Service item, no inventory tracked (e.g., repair labor)
--              = 服务类商品，不记录库存（如维修人工费）
--   untracked  = Fuzzy inventory tracking using stock_bucket levels (e.g., accessories)
--              = 不精确跟踪，使用模糊库存档位（如配件类）
--   tracked    = Exact quantity tracking with qty_on_hand (e.g., cases, chargers)
--              = 精确数量跟踪（如手机壳、充电器）
--   serialized = Per-unit tracking with unique serial numbers (e.g., phones with IMEI)
--              = 序列号管理跟踪，每件唯一（如手机 IMEI）
DO $$
BEGIN
  CREATE TYPE public.inventory_mode AS ENUM ('service', 'untracked', 'tracked', 'serialized');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- ENUM: valuation_method — Product cost valuation method
-- 枚举：valuation_method — 商品成本估值方式
-- =============================================
--   average = Weighted moving average cost (auto-updated on each purchase)
--           = 加权滑动平均成本（每次进货自动更新）
--   rate    = Cost calculated by fixed ratio (e.g., purchase price × coefficient)
--           = 按固定比率计算（如进价 × 系数）
--   fixed   = Fixed cost, manually specified, never auto-updated
--           = 固定成本，手动指定，不自动更新
DO $$
BEGIN
  CREATE TYPE public.valuation_method AS ENUM ('average', 'rate', 'fixed');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Function: assign_variant_id_per_item()
-- 函数：assign_variant_id_per_item()
-- =============================================
-- Auto-assigns variant_id per item_id (0, 1, 2, ...) on INSERT.
-- Uses pg_advisory_xact_lock to prevent race conditions during concurrent inserts.
-- Note: Uses COUNT(*) as the next variant_id — if item_id already has N rows
-- (including soft-deleted), the new row gets variant_id = N.
-- Warning: Soft-deleted rows are still counted, so gaps may appear in the sequence
-- (e.g., variant_id=1 is soft-deleted but the number is NOT reused).
-- ─────────────────────────────────────────────
-- 按 item_id 自动分配 variant_id（0, 1, 2, ...），在 INSERT 时触发。
-- 使用 pg_advisory_xact_lock 防止并发插入时产生重复编号。
-- 注意：使用 COUNT(*) 作为下一个 variant_id——若该 item_id 已有 N 条记录
-- （含软删除），新记录的 variant_id = N。
-- 警告：软删除的记录仍会被计入，因此序列中可能出现"空洞"
-- （例如 variant_id=1 已软删除，但序号不会被复用）。
-- ─────────────────────────────────────────────
-- Advisory Lock Namespace Allocation / 咨询锁命名空间分配:
--   1001 = assign_variant_id_per_item()         (this file, 06)
--   1002 = assign_batch_id_per_store()           (file 10)
--   1003 = assign_shift_id_per_store()           (file 11)
--   1004 = assign_purchase_order_id_per_store()  (file 20)
-- =============================================
CREATE OR REPLACE FUNCTION public.assign_variant_id_per_item()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Variable legend / 变量说明:
  --   next_vid = next variant_id to assign for this item_id / 本 item_id 下要分配的下一个 variant_id
  next_vid int;
BEGIN
  -- Guard: item_id must not be null / 防御性检查：item_id 不能为空
  IF NEW.item_id IS NULL THEN
    RAISE EXCEPTION 'item_id cannot be null';
  END IF;

  -- Serialize inserts for the same item_id using advisory lock (namespace 1001)
  -- 对同一 item_id 的插入串行化，使用咨询锁（命名空间 1001）
  PERFORM pg_advisory_xact_lock(1001, NEW.item_id);

  SELECT COUNT(*)::int
    INTO next_vid
  FROM public.mother_inventory_list
  WHERE item_id = NEW.item_id;  -- includes soft-deleted rows / 含软删除行

  NEW.variant_id := next_vid;
  RETURN NEW;
END;
$$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.mother_inventory_list (

  -- Global unique PK, auto-generated IDENTITY starting from 0
  -- Business logic should NOT use this value directly as a display ID
  -- 全局唯一主键，IDENTITY 自动生成，从 0 开始递增
  -- 业务端不应直接使用本值做展示 ID
  unique_id integer GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0) PRIMARY KEY,

  -- Product number (item_id): different variants of the same product share the same item_id
  -- Valid range: 100000–999999 (enforced by CHECK constraint below)
  -- 商品编号（item_id）：同一商品的不同规格共享同一 item_id
  -- 有效范围：100000–999999（由下方 CHECK 约束强制）
  item_id integer NOT NULL,

  -- Variant number: auto-assigned per item_id starting from 0 (0 = default/only variant)
  -- 规格编号：同一 item_id 下从 0 开始自动分配（0 = 默认/唯一规格）
  variant_id integer NOT NULL DEFAULT 0,

  -- Product barcodes (UPC): supports multiple barcodes per product; may be empty or duplicated across products
  -- 商品条码（UPC）：支持多条码绑定；允许为空，允许与其他条目重复
  item_upc text[] NOT NULL DEFAULT '{}'::text[],

  -- Product display name (required)
  -- 商品名称（必填）
  item_name text NOT NULL,

  -- Hierarchical category path as a text array; empty array = "uncategorized"
  -- Array elements represent levels from root category to subcategory
  -- e.g., {"Electronics", "Phone Accessories", "Cases"}
  -- 树形分类路径，以文本数组存储；空数组 = "未分类"
  -- 数组元素按顺序表示从根分类到子分类
  -- 例如 {"Electronics", "Phone Accessories", "Cases"}
  category_path text[] NOT NULL DEFAULT '{}'::text[],

  -- Product description / notes (optional)
  -- 商品描述/备注（可选）
  description text DEFAULT NULL,

  -- Manufacturer / brand name (optional)
  -- 商品生产商/品牌（可选）
  manufacture text DEFAULT NULL,

  -- Supplier FK (replaces the old text-based supplier column)
  -- 供应商外键（替代旧的文本类型 supplier 字段）
  supplier_id integer DEFAULT NULL REFERENCES public.supplier_list(supplier_id),

  -- Compatible device models; mainly for repair parts
  -- Stores device model strings this part is compatible with
  -- e.g., {"iPhone 15 Pro", "iPhone 15 Pro Max"}
  -- 适配设备型号列表；主要用于维修配件
  -- 以数组形式记录该配件兼容的设备型号字符串
  -- 例如 {"iPhone 15 Pro", "iPhone 15 Pro Max"}
  device_compatibility text[] NOT NULL DEFAULT '{}'::text[],

  -- Inventory tracking mode; see inventory_mode ENUM definition above
  -- 库存跟踪模式；参见上方 inventory_mode 枚举定义
  inventory_mode public.inventory_mode NOT NULL,

  -- Cost valuation method; see valuation_method ENUM above; defaults to weighted moving average
  -- 成本估值方式；参见上方 valuation_method 枚举定义；默认使用加权滑动平均
  valuation_method public.valuation_method NOT NULL DEFAULT 'average',

  -- Default cost per unit (inherited by store tables on INSERT)
  -- 默认单位成本（门店表 INSERT 时继承此值）
  default_cost numeric(10,2),

  -- Default retail price per unit (inherited by store tables on INSERT)
  -- 默认零售价格（门店表 INSERT 时继承此值）
  default_price numeric(10,2),

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Store that created this product record
  -- 创建该商品记录的门店 ID
  created_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Soft delete timestamp; NULL = active, non-NULL = removed from catalog
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已从目录中移除
  deleted_at timestamptz DEFAULT NULL,

  -- CHECK: item_id must be in the range 100000–999999
  -- 约束：item_id 必须在 100000–999999 范围内
  CONSTRAINT chk_mother_inventory_list_item_id_range
    CHECK (item_id BETWEEN 100000 AND 999999)
);

-- =============================================
-- Unique index: (item_id, variant_id) must be globally unique (including soft-deleted rows)
-- 唯一索引：(item_id, variant_id) 必须全局唯一（包含软删除行）
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_mother_item_variant
ON public.mother_inventory_list (item_id, variant_id);

-- =============================================
-- Triggers / 触发器
-- =============================================

-- Trigger: auto-refresh updated_at (reuses set_updated_at() from file 03)
-- 触发器：自动刷新 updated_at（复用 03_user_list 中的 set_updated_at()）
DROP TRIGGER IF EXISTS trg_mother_inventory_list_updated_at ON public.mother_inventory_list;
CREATE TRIGGER trg_mother_inventory_list_updated_at
BEFORE UPDATE ON public.mother_inventory_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- Trigger: auto-assign variant_id on INSERT
-- 触发器：INSERT 时自动分配 variant_id
DROP TRIGGER IF EXISTS trg_mother_inventory_list_assign_variant_id ON public.mother_inventory_list;
CREATE TRIGGER trg_mother_inventory_list_assign_variant_id
BEFORE INSERT ON public.mother_inventory_list
FOR EACH ROW
EXECUTE FUNCTION public.assign_variant_id_per_item();

-- =============================================
-- Indexes / 索引
-- =============================================

-- Look up products by item_id (active only)
-- 按 item_id 查找商品（仅活跃记录）
CREATE INDEX IF NOT EXISTS idx_mother_inventory_list_item_id
  ON public.mother_inventory_list (item_id)
  WHERE deleted_at IS NULL;

-- Filter products by inventory_mode
-- 按库存跟踪模式筛选商品
CREATE INDEX IF NOT EXISTS idx_mother_inventory_list_inventory_mode
  ON public.mother_inventory_list (inventory_mode);

-- GIN index for category_path array searches (e.g., find all products in a category)
-- GIN 索引：用于分类路径数组搜索（如查找某分类下的所有商品）
CREATE INDEX IF NOT EXISTS gin_mother_inventory_list_category_path
  ON public.mother_inventory_list USING gin (category_path);

-- GIN index for device_compatibility array searches (e.g., find parts for a specific phone model)
-- GIN 索引：用于适配设备数组搜索（如查找适配某手机型号的配件）
CREATE INDEX IF NOT EXISTS gin_mother_inventory_list_device_compatibility
  ON public.mother_inventory_list USING gin (device_compatibility);

-- GIN index for item_upc barcode array searches (e.g., scan a barcode to find the product)
-- GIN 索引：用于商品条码数组搜索（如扫码查找商品）
CREATE INDEX IF NOT EXISTS gin_mother_inventory_list_item_upc
  ON public.mother_inventory_list USING gin (item_upc);
