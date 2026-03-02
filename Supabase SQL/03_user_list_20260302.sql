-- =========================================
-- 03 · user_list 用户主表
-- =========================================
-- 依赖: 01_store_list (created_store_id FK)
-- 被依赖: 04_store_user_rights, 10_batch_list, 11_shift_list,
--         12_transaction_list, 14_store_inventory_adjustment_list,
--         16_serialized_event_list, 17_store_transfer_list,
--         19_store_item_history_list, 20_purchase_order_list,
--         22_repair_ticket_list
--
-- 自管登录体系，密码字段存储 bcrypt/argon2 哈希值，仅禁存明文

-- =========================================
-- 共享函数: set_updated_at()
-- =========================================
-- 通用 updated_at 自动刷新函数：
-- 任何绑定本触发器的表在 UPDATE 时自动将 updated_at 刷新为当前时间戳
-- >>> 本函数被以下所有后续表复用 <<<
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.user_list (

  -- 用户全局自增主键，从 0 开始，业务端不应手动指定
  user_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 登录用户名，活跃用户中唯一（见下方 partial unique index）
  -- 软删除后用户名释放，新用户可复用
  user_name text NOT NULL,

  -- 密码哈希（bcrypt / argon2），允许为空（如 SSO 登录或初始未设密码）
  user_password text DEFAULT NULL,

  -- 用户备注描述
  description text DEFAULT NULL,

  -- 用户手机号
  user_phone_number text DEFAULT NULL,

  -- 用户邮箱
  user_email_address text DEFAULT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 创建该用户记录的门店 ID
  created_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已停用
  deleted_at timestamptz DEFAULT NULL,

  -- 用户名不能为空白字符串
  CONSTRAINT user_list_user_name_not_blank
    CHECK (length(btrim(user_name)) > 0)
);

-- =========================================
-- 用户名唯一约束（仅活跃用户生效）
-- =========================================
-- 软删除后用户名释放，可被新用户使用
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_name_active
  ON public.user_list (user_name)
  WHERE deleted_at IS NULL;

-- =========================================
-- updated_at 自动刷新触发器（复用 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_user_list_updated_at ON public.user_list;
CREATE TRIGGER trg_user_list_updated_at
BEFORE UPDATE ON public.user_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 活跃用户索引
-- =========================================
CREATE INDEX IF NOT EXISTS idx_user_active
  ON public.user_list (user_id)
  WHERE deleted_at IS NULL;
