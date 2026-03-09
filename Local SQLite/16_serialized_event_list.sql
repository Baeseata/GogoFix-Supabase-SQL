-- Local SQLite version of 16_serialized_event_list.sql
-- Source: Supabase SQL/16_serialized_event_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS serialized_event_list (


  -- UUID v7 primary key, generated client-side for offline support
  -- UUID v7 主键，由客户端生成，支持离线
  event_id text PRIMARY KEY,

  -- Event type (see ENUM definition above)
  -- 事件类型（参见上方枚举定义）
  event_type text NOT NULL CHECK (event_type IN ('purchase','sell','return','mark_as_sold','mark_as_lost','mark_as_wasted','store_transferred','transferred_accepted','repair_out','repair_in','delete','revive','serial_edit')),

  -- Store where this event occurred, FK to store_list
  -- 事件发生的门店，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Serialized unit this event applies to, FK to store_serialized_list
  -- 本事件涉及的序列号单件，外键指向 store_serialized_list
  unit_id integer NOT NULL REFERENCES store_serialized_list(unit_id),

  -- Employee who performed this action, FK to user_list
  -- 执行本操作的员工，外键指向 user_list
  user_id integer NOT NULL REFERENCES user_list(user_id),

  -- Related transaction ID: populated for sell/return events, NULL for others
  -- No FK constraint: the related transaction may not yet be synced (offline scenario)
  -- 关联交易 ID：sell/return 事件时有值，其他事件为 NULL
  -- 不加外键约束：关联交易可能尚未同步到服务端（离线场景）
  transaction_id text DEFAULT NULL,

  -- Related transaction line ID: populated for sell/return events, NULL for others
  -- No FK constraint: same reason as above
  -- 关联交易明细行 ID：sell/return 事件时有值，其他事件为 NULL
  -- 不加外键约束：同上
  line_id text DEFAULT NULL,

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
  created_at text NOT NULL
);
