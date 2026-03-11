-- Local SQLite version of 06_mother_inventory_list.sql
-- Source: Supabase SQL/06_cloud_mother_inventory_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS mother_inventory_list (


  -- Global unique PK, auto-generated IDENTITY starting from 1
  -- Business logic should NOT use this value directly as a display ID
  -- 全局唯一主键，IDENTITY 自动生成，从 1 开始递增
  -- 业务端不应直接使用本值做展示 ID
  unique_id integer PRIMARY KEY AUTOINCREMENT,

  -- Product number (item_id): different variants of the same product share the same item_id
  -- Valid range: 100000–999999 (enforced by CHECK constraint below)
  -- 商品编号（item_id）：同一商品的不同规格共享同一 item_id
  -- 有效范围：100000–999999（由下方 CHECK 约束强制）
  item_id integer NOT NULL,

  -- Variant number: auto-assigned per item_id starting from 1 (1 = default/only variant)
  -- 规格编号：同一 item_id 下从 1 开始自动分配（1 = 默认/唯一规格）
  variant_id integer NOT NULL DEFAULT 1,

  -- Product barcodes (UPC): supports multiple barcodes per product; may be empty or duplicated across products
  -- 商品条码（UPC）：支持多条码绑定；允许为空，允许与其他条目重复
  item_upc text[] NOT NULL DEFAULT '[]',

  -- Product display name (required)
  -- 商品名称（必填）
  item_name text NOT NULL,

  -- Hierarchical category path as a text array; empty array = "uncategorized"
  -- Array elements represent levels from root category to subcategory
  -- e.g., {"Electronics", "Phone Accessories", "Cases"}
  -- 树形分类路径，以文本数组存储；空数组 = "未分类"
  -- 数组元素按顺序表示从根分类到子分类
  -- 例如 {"Electronics", "Phone Accessories", "Cases"}
  category_path text[] NOT NULL DEFAULT '[]',

  -- Product description / notes (optional)
  -- 商品描述/备注（可选）
  description text DEFAULT NULL,

  -- Manufacturer / brand name (optional)
  -- 商品生产商/品牌（可选）
  manufacture text DEFAULT NULL,

  -- Supplier FK (replaces the old text-based supplier column)
  -- 供应商外键（替代旧的文本类型 supplier 字段）
  supplier_id integer DEFAULT NULL REFERENCES supplier_list(supplier_id),

  -- Compatible device models; mainly for repair parts
  -- Stores device model strings this part is compatible with
  -- e.g., {"iPhone 15 Pro", "iPhone 15 Pro Max"}
  -- 适配设备型号列表；主要用于维修配件
  -- 以数组形式记录该配件兼容的设备型号字符串
  -- 例如 {"iPhone 15 Pro", "iPhone 15 Pro Max"}
  device_compatibility text[] NOT NULL DEFAULT '[]',

  -- Inventory tracking mode; see inventory_mode ENUM definition above
  -- 库存跟踪模式；参见上方 inventory_mode 枚举定义
  inventory_mode text NOT NULL CHECK (inventory_mode IN ('service','untracked','tracked','serialized')),

  -- Cost valuation method; see valuation_method ENUM above; defaults to weighted moving average
  -- 成本估值方式；参见上方 valuation_method 枚举定义；默认使用加权滑动平均
  valuation_method text NOT NULL DEFAULT 'average' CHECK (valuation_method IN ('average','rate','fixed')),

  -- Default cost per unit (inherited by store tables on INSERT)
  -- 默认单位成本（门店表 INSERT 时继承此值）
  default_cost numeric,

  -- Default retail price per unit (inherited by store tables on INSERT)
  -- 默认零售价格（门店表 INSERT 时继承此值）
  default_price numeric,

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Store that created this product record
  -- 创建该商品记录的门店 ID
  created_store_id text NOT NULL REFERENCES store_list(store_id),

  -- Item-level visibility scope (which stores can view/use this item)
  -- 商品级可见范围（哪些门店可以查看/使用该商品）
  -- Example / 示例: {'marcel','decarie'}
  visible_store_ids text[] NOT NULL DEFAULT '[]',

  -- Soft delete timestamp; NULL = active, non-NULL = removed from catalog
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已从目录中移除
  deleted_at text DEFAULT NULL,

  -- CHECK: item_id must be in the range 100000–999999
  -- 约束：item_id 必须在 100000–999999 范围内
  CONSTRAINT chk_mother_inventory_list_item_id_range
    CHECK (item_id BETWEEN 100000 AND 999999)
);
