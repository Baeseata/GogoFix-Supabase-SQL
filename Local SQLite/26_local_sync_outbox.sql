-- Local SQLite version of 26_sync_outbox.sql
-- Source concept: Supabase SQL/26_cloud_sync_changes.sql (adapted as local outbox queue)
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sync_outbox (


  -- Idempotent event UUID generated client-side (one business action = one event_id)
  -- 客户端生成的幂等事件 UUID（一个业务动作对应一个 event_id）
  event_id text PRIMARY KEY,

  -- Source store that produced the event
  -- 产生该事件的源门店
  source_store_id text NOT NULL,

  -- Optional target store for directed events; NULL for broadcast/non-targeted events
  -- 可选目标门店；定向事件填写，广播/非定向事件为 NULL
  target_store_id text DEFAULT NULL,

  -- Optional source device identifier for tracing
  -- 可选源设备标识，用于追踪
  source_device_id text DEFAULT NULL,

  -- Business event type label (client/server agreed vocabulary)
  -- 业务事件类型标识（客户端/服务端约定枚举词）
  event_type text NOT NULL,

  -- Event payload JSON text, must be valid JSON
  -- 事件载荷 JSON 文本，必须是合法 JSON
  payload_json text NOT NULL CHECK (json_valid(payload_json)),

  -- Event occurrence timestamp from local device clock
  -- 事件发生时间（本地设备时钟）
  occurred_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Delivery state machine: pending -> acted / error
  -- 投递状态机：pending -> acted / error
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','acted','error')),


  -- Last sync error message for diagnostics
  -- 最近一次同步错误信息（用于排查）
  last_error text DEFAULT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (refreshed by application logic/trigger)
  -- 最后更新时间（由应用逻辑/触发器刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Queue scanning index: fetch pending/error jobs in chronological order
-- 队列扫描索引：按时间顺序拉取 pending/error 任务
CREATE INDEX IF NOT EXISTS idx_sync_outbox_status_created
  ON sync_outbox (status, created_at);
