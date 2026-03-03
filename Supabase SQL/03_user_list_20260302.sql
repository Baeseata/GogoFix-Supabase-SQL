-- =============================================
-- File 03 · user_list — Employee / user master table
-- 文件 03 · user_list — 员工/用户主表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (created_store_id FK)
-- Dependents / 被依赖:
--   04_store_user_rights, 10_batch_list, 11_shift_list,
--   12_transaction_list, 14_store_inventory_adjustment_list,
--   16_serialized_event_list, 17_store_transfer_list,
--   19_store_item_history_list, 20_purchase_order_list,
--   22_repair_ticket_list
-- Shared components created here / 本文件创建的共享组件:
--   Function public.set_updated_at() — used by ALL mutable tables in files
--   04, 05, 06, 07, 08, 09, 10, 11, 12, 17, 20, 21, 22, 23
-- =============================================
-- Self-managed authentication system. The password field stores
-- bcrypt/argon2 hashes; the client hashes the password before sending.
-- Supabase Auth is NOT used.
-- ─────────────────────────────────────────────
-- 自管登录体系。密码字段存储 bcrypt/argon2 哈希值，
-- 客户端在发送前对密码进行哈希处理。不使用 Supabase Auth。
-- =============================================

-- =============================================
-- Shared function: set_updated_at()
-- 共享函数：set_updated_at()
-- =============================================
-- Automatically refreshes the updated_at column to now() on every UPDATE.
-- Any table that binds this trigger will have its updated_at auto-maintained.
-- >>> This function is reused by ALL subsequent mutable tables <<<
-- ─────────────────────────────────────────────
-- 通用 updated_at 自动刷新函数：
-- 任何绑定本触发器的表在 UPDATE 时自动将 updated_at 刷新为当前时间戳。
-- >>> 本函数被所有后续可变表复用 <<<
-- =============================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.user_list (

  -- Auto-increment primary key, starting from 0; should not be manually assigned
  -- 用户全局自增主键，从 0 开始；业务端不应手动指定
  user_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

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
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Store that created this user record
  -- 创建该用户记录的门店 ID
  created_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Soft delete timestamp; NULL = active, non-NULL = disabled / deactivated
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已停用
  deleted_at timestamptz DEFAULT NULL,

  -- CHECK: username must not be blank (empty or whitespace-only)
  -- 约束：用户名不能为空白字符串
  CONSTRAINT chk_user_list_user_name_not_blank
    CHECK (length(btrim(user_name)) > 0)
);

-- =============================================
-- Partial unique index: username must be unique among active (non-deleted) users.
-- After soft delete the username is released, allowing a new user to reuse it.
-- ─────────────────────────────────────────────
-- 部分唯一索引：用户名在活跃（未删除）用户中唯一。
-- 软删除后用户名释放，可被新用户使用。
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_list_user_name_active
  ON public.user_list (user_name)
  WHERE deleted_at IS NULL;

-- =============================================
-- Trigger: auto-refresh updated_at on every UPDATE (reuses set_updated_at())
-- 触发器：每次 UPDATE 自动刷新 updated_at（复用 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_user_list_updated_at ON public.user_list;
CREATE TRIGGER trg_user_list_updated_at
BEFORE UPDATE ON public.user_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Index: quickly find active (non-deleted) users
-- 索引：快速查找活跃（未删除）用户
-- =============================================
CREATE INDEX IF NOT EXISTS idx_user_list_active
  ON public.user_list (user_id)
  WHERE deleted_at IS NULL;
