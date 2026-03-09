-- Local SQLite sync outbox table
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sync_outbox (
  event_id text PRIMARY KEY,
  source_store_id text NOT NULL,
  target_store_id text DEFAULT NULL,
  source_device_id text DEFAULT NULL,
  event_type text NOT NULL,
  payload_json text NOT NULL CHECK (json_valid(payload_json)),
  occurred_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','acted','error')),
  retry_count integer NOT NULL DEFAULT 0,
  last_error text DEFAULT NULL,
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sync_outbox_status_created
  ON sync_outbox (status, created_at);
