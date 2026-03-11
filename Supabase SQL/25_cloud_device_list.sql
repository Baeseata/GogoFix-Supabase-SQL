-- Last updated (America/Toronto): 2026-03-06 15:23:16 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 15:23:16 EST
-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 25 · device_list — POS device registry table
-- 文件 25 · device_list — POS 设备注册表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (store_id FK)
--   03_user_list  (set_updated_at() trigger function)
-- Dependents / 被依赖:
--   (none currently)
--   （当前无）
-- Shared components created here / 本文件创建的共享组件:
--   ENUM public.device_environment — this table only
-- =============================================

-- =============================================
-- ENUM: device_environment — App environment / mode of the terminal
-- 枚举：device_environment — 终端运行环境/模式
-- =============================================
--   dev      = developer mode
--   register = cashier/front-desk mode
--   amir     = owner mode
--   tech     = technician mode
DO $$
BEGIN
  CREATE TYPE public.device_environment AS ENUM (
    'dev', 'register', 'amir', 'tech'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.device_list (

  -- Device primary key (text). Recommended: client-generated GUID/UUID string.
  -- 设备主键（text）。建议使用客户端生成的 GUID/UUID 字符串。
  device_id text PRIMARY KEY,

  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

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
  is_active boolean NOT NULL DEFAULT true,

  -- Last heartbeat / online seen timestamp
  -- 最近心跳 / 最近在线时间
  last_seen_at timestamptz DEFAULT NULL,

  -- Current app version running on this device
  -- 当前设备运行的客户端版本号
  app_version text DEFAULT NULL,

  -- Sync checkpoint cursor (last synced cloud change_id)
  -- 同步检查点游标（最近一次同步到的云端 change_id）
  checkpoint bigint NOT NULL DEFAULT 0,

  -- Environment/mode of this device
  -- 设备运行环境/模式
  environment public.device_environment NOT NULL,

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Soft delete timestamp; NULL = active row
  -- 软删除时间戳；NULL 表示活跃记录
  deleted_at timestamptz DEFAULT NULL,

  -- CHECK: device_id must not be blank
  -- 约束：device_id 不可为空白字符串
  CONSTRAINT chk_device_list_device_id_not_blank
    CHECK (length(btrim(device_id)) > 0),

  -- CHECK: terminal_no must not be blank
  -- 约束：terminal_no 不可为空白字符串
  CONSTRAINT chk_device_list_terminal_no_not_blank
    CHECK (length(btrim(terminal_no)) > 0),

  -- CHECK: device_name must not be blank
  -- 约束：device_name 不可为空白字符串
  CONSTRAINT chk_device_list_device_name_not_blank
    CHECK (length(btrim(device_name)) > 0)
);

-- =============================================
-- Partial unique index: terminal_no unique per store among active rows
-- 部分唯一索引：terminal_no 在门店内活跃记录唯一
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_list_store_terminal_active
  ON public.device_list (store_id, terminal_no)
  WHERE deleted_at IS NULL;

-- =============================================
-- Indexes / 索引
-- =============================================

-- Filter devices by store + active status
-- 按门店和启用状态筛选设备
CREATE INDEX IF NOT EXISTS idx_device_list_store_active
  ON public.device_list (store_id, is_active)
  WHERE deleted_at IS NULL;

-- Recent heartbeat sorting
-- 最近心跳时间排序
CREATE INDEX IF NOT EXISTS idx_device_list_last_seen_at
  ON public.device_list (last_seen_at DESC)
  WHERE deleted_at IS NULL AND last_seen_at IS NOT NULL;

-- =============================================
-- Trigger: auto-refresh updated_at (reuses set_updated_at() from file 03)
-- 触发器：自动刷新 updated_at（复用 03_user_list 中的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_device_list_updated_at ON public.device_list;
CREATE TRIGGER trg_device_list_updated_at
BEFORE UPDATE ON public.device_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
