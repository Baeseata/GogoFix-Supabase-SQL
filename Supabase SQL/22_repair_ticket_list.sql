-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: YES - offline POS must continue high-frequency essential operations using local snapshot; sync changes to cloud after reconnection.
-- 异步需求：是 - POS 离线时需依赖本地快照继续高频必要操作，网络恢复后将变更同步到云端。
-- =========================================
-- 22 · repair_ticket_list 修理工单主表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        03_user_list (user_id / tech_id FK)
--        07_customer_list (customer_id FK)
-- 被依赖: 23_repair_ticket_line_list (repair_ticket_id FK)
--         12_transaction_list (repair_ticket_id FK，本文件通过 ALTER TABLE 添加)
--
-- 记录客户送修设备的工单信息，内容离线运行

-- =========================================
-- ENUM: repair_status 修理工单状态枚举
-- =========================================
--   pending   = 待修理
--   completed = 修理完成
--   paid      = 已付款
--   cancelled = 已取消
DO $$
BEGIN
  CREATE TYPE public.repair_status AS ENUM ('pending', 'completed', 'paid', 'cancelled');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.repair_ticket_list (

  -- 客户端生成 UUIDv7，INSERT 时传入
  repair_ticket_id uuid PRIMARY KEY,

  -- 门店
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Human-readable repair document number
  -- Format: {store_code}{device_no}R-{YYMMDD}-{NNN} (e.g. D2R-260303-003)
  -- NULL allowed for legacy rows / offline temp rows before server normalization
  -- 可读修理单号
  -- 格式：{store_code}{device_no}R-{YYMMDD}-{NNN}（例如 D2R-260303-003）
  -- 兼容历史数据与离线临时记录：允许为 NULL
  display_no text,

  -- 旧的整型展示编号，保留用于兼容
  repair_display_id int4,

  -- 客户
  customer_id uuid REFERENCES public.customer_list(customer_id),
  customer_name text,                             -- 快照

  -- 操作人（创建工单的员工）
  user_id int4 REFERENCES public.user_list(user_id),

  -- 负责修理的技师，创建时可能未分配
  tech_id int4 REFERENCES public.user_list(user_id),

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
  repair_status public.repair_status NOT NULL DEFAULT 'pending',
  completed_at timestamptz,                       -- 完成时间

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  synced_at timestamptz,

  -- 显示单号格式校验（可空）
  CONSTRAINT chk_repair_ticket_display_no_format
    CHECK (
      display_no IS NULL
      OR display_no ~ '^[A-Za-z0-9]+R-[0-9]{6}-[0-9]{3}$'
    )
);

-- Migration safety patch: add device_id for existing databases
-- 迁移兼容补丁：为已存在数据库补充 device_id 字段
ALTER TABLE public.repair_ticket_list
  ADD COLUMN IF NOT EXISTS device_id text;

-- =========================================
-- 索引
-- =========================================

-- 某门店工单列表（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_repair_ticket_store_created
  ON public.repair_ticket_list (store_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- 某客户的工单历史
CREATE INDEX IF NOT EXISTS idx_repair_ticket_customer_created
  ON public.repair_ticket_list (customer_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- 按状态筛选
CREATE INDEX IF NOT EXISTS idx_repair_ticket_status
  ON public.repair_ticket_list (store_id, repair_status)
  WHERE deleted_at IS NULL;

-- 按门店 + 设备查询工单（便于离线后在同设备续做）
CREATE INDEX IF NOT EXISTS idx_repair_ticket_store_device_created
  ON public.repair_ticket_list (store_id, device_id, created_at DESC)
  WHERE deleted_at IS NULL AND device_id IS NOT NULL;

-- display_no 唯一（同门店内，非空且未删除）
CREATE UNIQUE INDEX IF NOT EXISTS uq_repair_ticket_store_display_no
  ON public.repair_ticket_list (store_id, display_no)
  WHERE display_no IS NOT NULL AND deleted_at IS NULL;

-- 旧展示编号唯一（同门店内，非空且未删除）
CREATE UNIQUE INDEX IF NOT EXISTS uq_repair_ticket_store_display_id
  ON public.repair_ticket_list (store_id, repair_display_id)
  WHERE repair_display_id IS NOT NULL AND deleted_at IS NULL;

-- =========================================
-- 迁移兼容补丁：为已存在数据库补充 display_no 列与约束
-- =========================================
ALTER TABLE public.repair_ticket_list
  ADD COLUMN IF NOT EXISTS display_no text;

DO $$
BEGIN
  ALTER TABLE public.repair_ticket_list
    ADD CONSTRAINT chk_repair_ticket_display_no_format
    CHECK (
      display_no IS NULL
      OR display_no ~ '^[A-Za-z0-9]+R-[0-9]{6}-[0-9]{3}$'
    );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_repair_ticket_set_updated_at ON public.repair_ticket_list;
CREATE TRIGGER trg_repair_ticket_set_updated_at
BEFORE UPDATE ON public.repair_ticket_list
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 补丁：为 transaction_list 添加 repair_ticket_id FK
-- =========================================
-- 修理完成后付款时，transaction_list 中的交易通过此字段关联修理工单
ALTER TABLE public.transaction_list
  ADD COLUMN IF NOT EXISTS repair_ticket_id uuid;

DO $$
BEGIN
  ALTER TABLE public.transaction_list
    ADD CONSTRAINT fk_transaction_repair_ticket
    FOREIGN KEY (repair_ticket_id) REFERENCES public.repair_ticket_list(repair_ticket_id);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
