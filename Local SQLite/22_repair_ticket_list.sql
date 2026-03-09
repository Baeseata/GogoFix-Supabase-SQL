-- Local SQLite version of 22_repair_ticket_list.sql
-- Source: Supabase SQL/22_repair_ticket_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS repair_ticket_list (


  -- 客户端生成 UUIDv7，INSERT 时传入
  repair_ticket_id text PRIMARY KEY,

  -- 门店
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Human-readable repair document number
  -- Format: {store_code}{device_no}R-{YYMMDD}-{NNN} (e.g. D2R-260303-003)
  -- NULL allowed for legacy rows / offline temp rows before server normalization
  -- 可读修理单号
  -- 格式：{store_code}{device_no}R-{YYMMDD}-{NNN}（例如 D2R-260303-003）
  -- 兼容历史数据与离线临时记录：允许为 NULL
  display_no text,

  -- 旧的整型展示编号，保留用于兼容
  repair_display_id integer,

  -- 客户
  customer_id text REFERENCES customer_list(customer_id),
  customer_name text,                             -- 快照

  -- 操作人（创建工单的员工）
  user_id integer REFERENCES user_list(user_id),

  -- 负责修理的技师，创建时可能未分配
  tech_id integer REFERENCES user_list(user_id),

  -- 设备信息
  device_name text,
  device_id text,                                  -- 创建/跟进该工单的POS设备ID
  serial text,                                    -- 客户设备序列号，可选
  condition_before text,                          -- 修理前状况描述
  password_note text,                             -- 客户端加密后存储

  -- 备注
  note_invoice text,                              -- 出现在 invoice 上
  note_store text,                                -- 店内 / 技师查看

  -- 状态
  repair_status text NOT NULL DEFAULT 'pending',
  completed_at text,                       -- 完成时间

  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at text,
  synced_at text

  -- 显示单号格式校验（可空）
);
