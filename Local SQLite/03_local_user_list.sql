-- Local SQLite version of 03_user_list.sql
-- Source: Supabase SQL/03_cloud_user_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS user_list (


  -- Auto-increment primary key, starting from 1; should not be manually assigned
  -- 用户全局自增主键，从 1 开始；业务端不应手动指定
  user_id integer PRIMARY KEY AUTOINCREMENT,

  -- Login username; unique among active (non-deleted) users via partial unique index below.
  -- After soft delete, the username is released and can be reused by a new user.
  -- 登录用户名；在活跃（未删除）用户中唯一（见下方 partial unique index）。
  -- 软删除后用户名释放，新用户可复用。
  user_name text NOT NULL,

  -- Password hash (bcrypt / argon2); may be NULL for SSO login or initial setup
  -- 密码哈希（bcrypt / argon2）；SSO 登录或初始未设密码时可为空
  user_password text DEFAULT NULL,

  -- Optional description / notes about this user
  -- 用户备注描述（可选）
  description text DEFAULT NULL,

  -- User's phone number (optional)
  -- 用户手机号（可选）
  user_phone_number text DEFAULT NULL,

  -- User's email address (optional)
  -- 用户邮箱（可选）
  user_email_address text DEFAULT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Store that created this user record
  -- 创建该用户记录的门店 ID
  created_store_id text NOT NULL REFERENCES store_list(store_id),

  -- Soft delete timestamp; NULL = active, non-NULL = disabled / deactivated
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已停用
  deleted_at text DEFAULT NULL,

  -- CHECK: username must not be blank (empty or whitespace-only)
  -- 约束：用户名不能为空白字符串
  CONSTRAINT chk_user_list_user_name_not_blank
    CHECK (length(trim(user_name)) > 0)
);
