-- Local SQLite version of 13_transaction_line_list.sql
-- Source: Supabase SQL/13_cloud_transaction_line_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS transaction_line_list (


  -- UUID v7 primary key, generated client-side for offline support
  -- UUID v7 主键，由客户端生成，支持离线
  line_id text PRIMARY KEY,

  -- Parent transaction, FK to transaction_list
  -- 所属交易，外键指向 transaction_list
  transaction_id text NOT NULL REFERENCES transaction_list(transaction_id),

  -- Store ID (denormalized to avoid frequent JOINs with transaction_list for queries)
  -- 门店 ID（冗余字段，避免高频查询时 JOIN transaction_list）
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Product reference, FK to mother_inventory_list (required — every line must map to a catalog item)
  -- 母表商品引用，外键指向 mother_inventory_list（必填 — 每条明细必须对应一个目录商品）
  unique_id integer NOT NULL REFERENCES mother_inventory_list(unique_id),

  -- Serialized unit reference: required for serialized items, must be NULL for non-serialized
  -- Consistency validated by trigger (see Trigger A below)
  -- 序列号单件引用：serialized 商品必填，非 serialized 商品应为 NULL
  -- 一致性由触发器校验（见下方触发器 A）
  unit_id integer DEFAULT NULL REFERENCES store_serialized_list(unit_id),

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
  cost_per_unit numeric NOT NULL DEFAULT 0,

  -- Selling price per unit: read by client from store_inventory_list or store_serialized_list
  -- 单位售价：由客户端从 store_inventory_list 或 store_serialized_list 读取
  price_per_unit numeric NOT NULL DEFAULT 0,

  -- Discount amount for this line (positive value = money off)
  -- 该行折扣金额（正数表示优惠金额）
  line_discount numeric NOT NULL DEFAULT 0,

  -- Tax amount for this line
  -- 该行税额
  line_tax numeric NOT NULL DEFAULT 0,

  -- Pre-tax line total = qty × price_per_unit − line_discount (validated by CHECK)
  -- 税前行总额 = qty × price_per_unit − line_discount（由 CHECK 约束校验）
  line_total_before_tax numeric NOT NULL DEFAULT 0,

  -- Line total including tax = line_total_before_tax + line_tax (validated by CHECK)
  -- 含税行总额 = line_total_before_tax + line_tax（由 CHECK 约束校验）
  line_total numeric NOT NULL DEFAULT 0,

  -- Line profit = line_total_before_tax − qty × cost_per_unit (validated by CHECK)
  -- 行利润 = line_total_before_tax − qty × cost_per_unit（由 CHECK 约束校验）
  line_profit numeric NOT NULL DEFAULT 0,

  -- Last edit timestamp; NULL = never edited, non-NULL = time of most recent edit
  -- 编辑时间戳；NULL 表示未被编辑过，有值 = 最近一次编辑时间
  edited_at text DEFAULT NULL,

  -- Soft delete timestamp; NULL = active, non-NULL = voided
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已作废
  deleted_at text DEFAULT NULL,

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
