-- Local SQLite version of 19_store_item_history_list.sql
-- Source: Supabase SQL/19_cloud_store_item_history_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_item_history_list (


  -- Auto-increment primary key, starting from 1 (assigned by DB)
  -- 全局自增主键，从 1 开始（由数据库分配）
  history_id integer PRIMARY KEY AUTOINCREMENT,

  -- Store where the inventory change occurred, FK to store_list
  -- 库存变动发生的门店，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Product reference, FK to mother_inventory_list
  -- 商品引用，外键指向 mother_inventory_list
  unique_id integer NOT NULL REFERENCES mother_inventory_list(unique_id),

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
  user_id integer NOT NULL REFERENCES user_list(user_id),

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
  created_at text NOT NULL,

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
  -- Points to the PK of the originating table; TEXT type to accommodate both text and integer PKs
  -- e.g., transaction_line_list.line_id, adjustment_line_list.line_id,
  --       transfer_line_list.line_id, serialized_event_list.event_id
  -- 来源记录 ID（由客户端填写）
  -- 指向原始表的主键；TEXT 类型兼容 text 和 integer 主键
  -- 如 transaction_line_list.line_id、adjustment_line_list.line_id、
  --    transfer_line_list.line_id、serialized_event_list.event_id
  source_id text NOT NULL
);
