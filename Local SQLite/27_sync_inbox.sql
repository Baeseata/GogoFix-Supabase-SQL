-- Local SQLite sync inbox table for dedupe
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sync_inbox (
  event_id text PRIMARY KEY,
  change_id integer NOT NULL,
  source_store_id text NOT NULL,
  payload_json text NOT NULL CHECK (json_valid(payload_json)),
  occurred_at text NOT NULL,
  committed_at text NOT NULL,
  applied_at text NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sync_inbox_change_id
  ON sync_inbox (change_id);
