-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: YES - offline POS must continue high-frequency essential operations using local snapshot; sync changes to cloud after reconnection.
-- 异步需求：是 - POS 离线时需依赖本地快照继续高频必要操作，网络恢复后将变更同步到云端。
-- =============================================
-- File 16 · serialized_event_list — Serialized item lifecycle event log
-- 文件 16 · serialized_event_list — 序列号商品生命周期事件表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list            (store_id FK)
--   03_user_list             (user_id FK)
--   09_store_serialized_list (unit_id FK + serialized_status ENUM)
-- Dependents / 被依赖:
--   (none) （无）
-- Shared components created here / 本文件创建的共享组件:
--   ENUM public.serialized_event_type — this table only
--   Uses ENUM public.serialized_status created in file 09
-- =============================================
-- Immutable audit log recording every lifecycle event for serialized items (e.g., phones).
-- Supports offline creation: PK is a UUID v7 generated client-side.
-- By design, only INSERT is intended (no UPDATE or DELETE), but the DB does not
-- enforce immutability here to allow future flexibility.
-- ─────────────────────────────────────────────
-- 不可变审计日志，记录每一件序列号商品（如手机）的完整生命线（状态变化历史）。
-- 支持离线创建：主键由客户端生成 UUID v7。
-- 设计上只允许 INSERT，不应 UPDATE 或 DELETE
-- （但数据库层面不做强制拦截，留后余地）。
-- =============================================

-- =============================================
-- Note: serialized_status is defined in file 09 and already includes lost/wasted.
-- 说明：serialized_status 在 09 文件中定义，且已包含 lost/wasted。
-- =============================================

-- =============================================
-- ENUM: serialized_event_type — Event types for serialized item lifecycle
-- 枚举：serialized_event_type — 序列号商品生命周期事件类型
-- =============================================
-- Each event_type corresponds to a status transition in serialized_status:
-- 每种 event_type 对应 serialized_status 的一次状态迁移：
--
--   purchase              : → in_stock          New unit received into inventory
--                         = 新货入库，在 store_serialized_list 创建新行
--   sell                  : in_stock → sold      Sold to a customer via transaction
--                         = 通过交易卖出给客户
--   return                : sold → in_stock      Customer returned the unit
--                         = 客户退货回库
--   mark_as_sold          : in_stock → sold      Manually marked as sold (inventory correction, not via transaction)
--                         = 手动标记为已售（库存修正，非交易触发）
--   mark_as_lost          : in_stock → lost      Marked as lost
--                         = 标记为丢失
--   mark_as_wasted        : in_stock → wasted    Marked as damaged/wasted
--                         = 标记为损坏/报废
--   store_transferred     : in_stock → in_transit  Sent to another store (transfer initiated)
--                         = 调拨发出到其他门店（调拨发起）
--   transferred_accepted  : in_transit → in_stock  Received from another store (store_id changes)
--                         = 从其他门店接收（store_id 变更）
--   repair_out            : in_stock → repair    Sent out for external repair
--                         = 送外部维修
--   repair_in             : repair → in_stock    Returned from external repair
--                         = 外部维修返回
--   delete                : in_stock → void      Logically deleted (voided)
--                         = 逻辑删除（作废）
--   revive                : void → in_stock      Restored from voided state
--                         = 从作废状态恢复
--   serial_edit           : (no status change)   Serial number was edited
--                         = （无状态变化）序列号被修改
DO $$
BEGIN
  CREATE TYPE public.serialized_event_type AS ENUM (
    'purchase',
    'sell',
    'return',
    'mark_as_sold',
    'mark_as_lost',
    'mark_as_wasted',
    'store_transferred',
    'transferred_accepted',
    'repair_out',
    'repair_in',
    'delete',
    'revive',
    'serial_edit'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.serialized_event_list (

  -- UUID v7 primary key, generated client-side for offline support
  -- UUID v7 主键，由客户端生成，支持离线
  event_id uuid PRIMARY KEY,

  -- Event type (see ENUM definition above)
  -- 事件类型（参见上方枚举定义）
  event_type public.serialized_event_type NOT NULL,

  -- Store where this event occurred, FK to store_list
  -- 事件发生的门店，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Serialized unit this event applies to, FK to store_serialized_list
  -- 本事件涉及的序列号单件，外键指向 store_serialized_list
  unit_id integer NOT NULL REFERENCES public.store_serialized_list(unit_id),

  -- Employee who performed this action, FK to user_list
  -- 执行本操作的员工，外键指向 user_list
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- Related transaction ID: populated for sell/return events, NULL for others
  -- No FK constraint: the related transaction may not yet be synced (offline scenario)
  -- 关联交易 ID：sell/return 事件时有值，其他事件为 NULL
  -- 不加外键约束：关联交易可能尚未同步到服务端（离线场景）
  transaction_id uuid DEFAULT NULL,

  -- Related transaction line ID: populated for sell/return events, NULL for others
  -- No FK constraint: same reason as above
  -- 关联交易明细行 ID：sell/return 事件时有值，其他事件为 NULL
  -- 不加外键约束：同上
  line_id uuid DEFAULT NULL,

  -- Serial number snapshot at event time (provided by client)
  -- For serial_edit events, this is the NEW serial after the edit
  -- 事件发生时的序列号快照（由客户端填写）
  -- 对于 serial_edit 事件，本值为修改后的新 serial
  serial text NOT NULL,

  -- Optional event note
  -- For serial_edit + swap operations, the client records the swapped serial pairs here
  -- 事件备注（可选）
  -- serial_edit + 互换操作时，客户端在此记录互换的两组序列号
  note text DEFAULT NULL,

  -- Client-side creation timestamp (provided by client for offline scenarios)
  -- 客户端本地创建时间（离线场景下由客户端提供）
  created_at timestamptz NOT NULL
);

-- =============================================
-- Indexes / 索引
-- =============================================

-- Look up the complete event timeline for a specific unit (most frequent query)
-- 查询某单件的完整事件时间线（最高频查询）
CREATE INDEX IF NOT EXISTS idx_serialized_event_unit
  ON public.serialized_event_list (unit_id, created_at DESC);

-- Look up all events in a store (newest first)
-- 查询门店的所有事件（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_serialized_event_store
  ON public.serialized_event_list (store_id, created_at DESC);

-- Look up events related to a specific transaction
-- 查询某笔交易关联的事件
CREATE INDEX IF NOT EXISTS idx_serialized_event_transaction
  ON public.serialized_event_list (transaction_id)
  WHERE transaction_id IS NOT NULL;

-- Filter events by type (e.g., find all sell events, all transfer events)
-- 按事件类型筛选（如查找所有卖出事件、所有调拨事件）
CREATE INDEX IF NOT EXISTS idx_serialized_event_type
  ON public.serialized_event_list (event_type);

-- Look up events by the employee who performed them
-- 按操作员工查询事件记录
CREATE INDEX IF NOT EXISTS idx_serialized_event_user
  ON public.serialized_event_list (user_id);
