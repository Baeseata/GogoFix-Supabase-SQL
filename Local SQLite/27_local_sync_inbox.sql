-- Local SQLite version of 27_sync_inbox.sql
-- Source concept: Supabase SQL/26_cloud_sync_changes.sql (adapted as local inbox dedupe log)
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sync_inbox (


  -- Idempotent event UUID from cloud sync stream
  -- 来自云端同步流的幂等事件 UUID
  event_id text PRIMARY KEY,

  -- Monotonic cloud change sequence number
  -- 云端单调递增变更序号
  change_id integer NOT NULL,

  -- Store that originally emitted the event
  -- 最初发出该事件的门店
  source_store_id text NOT NULL,

  -- Raw event payload JSON text, must be valid JSON
  -- 原始事件载荷 JSON 文本，必须是合法 JSON
  payload_json text NOT NULL CHECK (json_valid(payload_json)),

  -- Event occurrence timestamp from producer
  -- 生产端上报的事件发生时间
  occurred_at text NOT NULL,

  -- Cloud commit timestamp when event became visible in sync log
  -- 事件在云端同步日志中可见的提交时间
  committed_at text NOT NULL,

  -- Local apply timestamp after successful inbox processing
  -- 本地成功应用该事件后的时间戳
  applied_at text NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Seek index for incremental pull/apply checkpoints
-- 增量拉取/应用检查点查询索引
CREATE INDEX IF NOT EXISTS idx_sync_inbox_change_id
  ON sync_inbox (change_id);
