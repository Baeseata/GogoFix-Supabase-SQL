-- Local SQLite version of 25_device_list.sql
-- Source: Supabase SQL/25_device_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS device_list (


  -- Device primary key (text). Recommended: client-generated GUID/UUID string.
  -- 设备主键（text）。建议使用客户端生成的 GUID/UUID 字符串。
  device_id text PRIMARY KEY,

  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Human-friendly terminal number within a store (e.g., POS-01)
  -- 门店内可读终端编号（例如 POS-01）
  terminal_no text NOT NULL,

  -- Device display name (e.g., Front Desk iPad)
  -- 设备显示名称（例如 Front Desk iPad）
  device_name text NOT NULL,

  -- Optional description / notes
  -- 备注（可选）
  description text DEFAULT NULL,

  -- Whether this device is operationally active
  -- 设备是否处于启用状态
  is_active integer NOT NULL DEFAULT 1,

  -- Last heartbeat / online seen timestamp
  -- 最近心跳 / 最近在线时间
  last_seen_at text DEFAULT NULL,

  -- Current app version running on this device
  -- 当前设备运行的客户端版本号
  app_version text DEFAULT NULL,

  -- Sync checkpoint cursor (last synced cloud change_id)
  -- 同步检查点游标（最近一次同步到的云端 change_id）
  checkpoint bigint NOT NULL DEFAULT 0,

  -- Environment/mode of this device
  -- 设备运行环境/模式
  environment text NOT NULL CHECK (environment IN ('dev','register','amir','tech')),

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Soft delete timestamp; NULL = active row
  -- 软删除时间戳；NULL 表示活跃记录
  deleted_at text DEFAULT NULL,

  -- CHECK: device_id must not be blank
  -- 约束：device_id 不可为空白字符串
  CONSTRAINT chk_device_list_device_id_not_blank
    CHECK (length(trim(device_id)) > 0),

  -- CHECK: terminal_no must not be blank
  -- 约束：terminal_no 不可为空白字符串
  CONSTRAINT chk_device_list_terminal_no_not_blank
    CHECK (length(trim(terminal_no)) > 0),

  -- CHECK: device_name must not be blank
  -- 约束：device_name 不可为空白字符串
  CONSTRAINT chk_device_list_device_name_not_blank
    CHECK (length(trim(device_name)) > 0)
);
