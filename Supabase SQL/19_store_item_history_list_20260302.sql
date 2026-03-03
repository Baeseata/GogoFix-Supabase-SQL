-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 19 · store_item_history_list — Aggregated inventory change history (IMMUTABLE)
-- 文件 19 · store_item_history_list — 商品库存变动历史汇总表（不可变）
-- =============================================
-- Dependencies / 依赖:
--   01_store_list            (store_id FK)
--   03_user_list             (user_id FK)
--   06_mother_inventory_list (unique_id FK)
-- Dependents / 被依赖:
--   (none) （无）
-- =============================================
-- Aggregated, denormalized snapshot of inventory changes from multiple sources:
-- transactions, adjustments, transfers, serialized events, purchase orders, etc.
-- Used by the client for fast querying and display of product history.
-- Online-only: the client writes to this table during sync (no offline operation).
-- IMMUTABLE: triggers block all UPDATE and DELETE operations.
-- ─────────────────────────────────────────────
-- 汇总来自多个来源的库存变动记录（交易、盘点、调拨、serialized 事件、采购等）。
-- 表内数据为冗余快照，仅用于客户端快速查询和展示商品历史。
-- 不支持离线：由客户端在联网时从其他表同步写入。
-- 不可变：触发器强制拦截所有 UPDATE 和 DELETE 操作。
-- =============================================

CREATE TABLE IF NOT EXISTS public.store_item_history_list (

  -- Auto-increment primary key, starting from 0 (assigned by DB)
  -- 全局自增主键，从 0 开始（由数据库分配）
  history_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- Store where the inventory change occurred, FK to store_list
  -- 库存变动发生的门店，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Product reference, FK to mother_inventory_list
  -- 商品引用，外键指向 mother_inventory_list
  unique_id integer NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- Inventory quantity change (integer)
  -- Applies to all inventory_mode types:
  --   tracked    = actual qty change (positive = stock in, negative = stock out)
  --   serialized = per-unit change (+1 = received, -1 = sold, etc.)
  --   untracked  = qty from transaction; 0 for adjustments (bucket changes have no numeric qty)
  -- May be 0 (e.g., stocktake confirming no change, untracked bucket adjustment)
  -- 库存数量变动（整数）
  -- 适用于所有 inventory_mode：
  --   tracked    = 实际数量变化（正数入库，负数出库）
  --   serialized = 单件变动（+1 入库，-1 卖出等）
  --   untracked  = 交易时有数量；盘点时统一填 0（档位变更无数值意义）
  -- 允许为 0（如盘点确认无变化、untracked 盘点档位调整等）
  qty_delta integer NOT NULL DEFAULT 0,

  -- Post-event inventory snapshot (TEXT type for flexibility across modes)
  --   tracked    = current quantity as string (e.g., "42")
  --   serialized = count of in_stock units for this SKU in this store (e.g., "5")
  --   untracked  = current stock_bucket label (e.g., "normal", "few")
  -- Display-only; TEXT type accommodates all formats
  -- 事件后的库存快照（TEXT 类型，兼容所有模式的格式）
  --   tracked    = 当前库存数量字符串（如 "42"）
  --   serialized = 该 SKU 在该门店剩余的 in_stock 单件总数（如 "5"）
  --   untracked  = 当前档位描述（如 "normal"、"few"）
  -- 纯展示用途，TEXT 类型兼容所有格式
  qty_snapshot text NOT NULL,

  -- Employee who performed the operation, FK to user_list
  -- 执行操作的员工，外键指向 user_list
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- Event timestamp (NOT auto-generated; read from the source table):
  --   Transaction      → transaction's created_at
  --   Adjustment       → adjustment's created_at
  --   Transfer         → transfer's created_at
  --   Serialized event → serialized_event's created_at
  --   Purchase order   → PO's created_at
  -- 事件发生时间（非自动生成；从来源表读取）：
  --   交易     → 交易的 created_at
  --   盘点     → 盘点的 created_at
  --   调拨     → 调拨的 created_at
  --   序列号事件 → 序列号事件的 created_at
  --   采购     → 采购单的 created_at
  created_at timestamptz NOT NULL,

  -- Event type string (provided by client)
  -- For serialized items: copied from serialized_event_list.event_type
  --   e.g., 'purchase', 'sell', 'return', 'store_transferred', 'repair_out'
  -- For non-serialized items: set by client based on source
  --   e.g., 'sale', 'refund', 'exchange', 'inventory_adjustment',
  --         'store_transfer', 'purchase_order'
  -- 事件类型字符串（由客户端填写）
  -- serialized 商品：从 serialized_event_list.event_type 复制
  --   如 'purchase', 'sell', 'return', 'store_transferred', 'repair_out'
  -- 非 serialized 商品：按来源填写
  --   如 'sale', 'refund', 'exchange', 'inventory_adjustment',
  --      'store_transfer', 'purchase_order'
  event_type text NOT NULL,

  -- Source record ID (provided by client)
  -- Points to the PK of the originating table; TEXT type to accommodate both uuid and integer PKs
  -- e.g., transaction_line_list.line_id, adjustment_line_list.line_id,
  --       transfer_line_list.line_id, serialized_event_list.event_id
  -- 来源记录 ID（由客户端填写）
  -- 指向原始表的主键；TEXT 类型兼容 uuid 和 integer 主键
  -- 如 transaction_line_list.line_id、adjustment_line_list.line_id、
  --    transfer_line_list.line_id、serialized_event_list.event_id
  source_id text NOT NULL
);

-- =============================================
-- Immutability triggers: block all UPDATE and DELETE operations
-- 不可变触发器：拦截所有 UPDATE 和 DELETE 操作
-- =============================================
-- Once a history record is created, it must never be modified or removed.
-- This ensures the audit trail remains intact.
-- 一旦历史记录创建，就不能被修改或删除。
-- 这确保了审计线索的完整性。
-- =============================================
CREATE OR REPLACE FUNCTION public.store_item_history_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'store_item_history_list is immutable: % is not allowed', TG_OP;
  RETURN NULL;
END;
$$;

-- Block UPDATE / 拦截 UPDATE
DROP TRIGGER IF EXISTS trg_store_item_history_no_update ON public.store_item_history_list;
CREATE TRIGGER trg_store_item_history_no_update
BEFORE UPDATE ON public.store_item_history_list
FOR EACH ROW
EXECUTE FUNCTION public.store_item_history_immutable();

-- Block DELETE / 拦截 DELETE
DROP TRIGGER IF EXISTS trg_store_item_history_no_delete ON public.store_item_history_list;
CREATE TRIGGER trg_store_item_history_no_delete
BEFORE DELETE ON public.store_item_history_list
FOR EACH ROW
EXECUTE FUNCTION public.store_item_history_immutable();

-- =============================================
-- Indexes / 索引
-- =============================================

-- Core query: complete history for a specific product in a specific store (newest first)
-- 核心查询：某门店某商品的完整历史（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_item_history_store_item
  ON public.store_item_history_list (store_id, unique_id, created_at DESC);

-- All inventory changes in a store (newest first)
-- 门店的所有库存变动（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_item_history_store
  ON public.store_item_history_list (store_id, created_at DESC);

-- All changes for a product across all stores (newest first)
-- 某商品在所有门店的变动历史（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_item_history_unique_id
  ON public.store_item_history_list (unique_id, created_at DESC);

-- Filter by event type (e.g., find all 'sell' events, all 'inventory_adjustment' events)
-- 按事件类型筛选（如查找所有 'sell' 事件、所有 'inventory_adjustment' 事件）
CREATE INDEX IF NOT EXISTS idx_item_history_event_type
  ON public.store_item_history_list (event_type);
