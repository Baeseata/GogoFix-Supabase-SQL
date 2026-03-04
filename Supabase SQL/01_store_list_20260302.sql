-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 01 · store_list — Store master table
-- 文件 01 · store_list — 门店主表
-- =============================================
-- Dependencies / 依赖:
--   (none — this is the foundational table, created first)
--   （无 — 基础表，最先创建）
-- Dependents / 被依赖:
--   Almost all other tables reference this table via store_id FK
--   几乎所有其他表通过 store_id FK 引用本表
-- =============================================

CREATE TABLE IF NOT EXISTS public.store_list (

  -- Store ID: business-defined text identifier (e.g., "decarie", "marcel", "parcex")
  -- 门店 ID：业务端自定义的文本标记（如 "decarie"、"marcel"、"parcex"）
  store_id text PRIMARY KEY,

  -- Store display name (required)
  -- 门店名称（必填）
  store_name text NOT NULL,

  -- Store phone number (optional)
  -- 门店电话（可选）
  store_phone_number text DEFAULT NULL,

  -- Store physical address (optional)
  -- 门店地址（可选）
  store_address text DEFAULT NULL,

  -- Store email address, used for billing / settlement
  -- 门店邮箱，用于对账结算
  store_email_address text DEFAULT NULL,

  -- Email address for receiving automated business reports
  -- 报表接收邮箱，用于自动发送经营报表等
  store_report_email text DEFAULT NULL,

  -- Store sales policy printed on sales receipts
  -- 门店销售政策（打印在销售小票上）
  store_sale_policy text DEFAULT NULL,

  -- Store repair policy printed on repair tickets / repair receipts
  -- 门店维修政策（打印在维修工单/维修收据上）
  store_repair_policy text DEFAULT NULL,

  -- Store website URL
  -- 门店网站地址
  store_website text DEFAULT NULL,

  -- Store postcode / ZIP code
  -- 门店邮编
  store_postcode text DEFAULT NULL,

  -- Google review QR reference (recommended: URL or storage path to QR image)
  -- Google Review 二维码引用（推荐存 URL 或二维码图片存储路径）
  store_qr text DEFAULT NULL,

  -- Text displayed before the store QR on printouts
  -- 打印时显示在门店二维码前的一段话
  store_qr_note_before text DEFAULT NULL,

  -- Text displayed after the store QR on printouts
  -- 打印时显示在门店二维码后的一句话
  store_qr_note_after text DEFAULT NULL,

  -- Tax rate configuration stored as a JSONB object
  -- e.g. {"GST": 0.05, "QST": 0.09975}
  -- The CHECK constraint below ensures this is always a JSON object (not array, string, etc.)
  -- 税率配置，以 JSONB 对象存储
  -- 例如 {"GST": 0.05, "QST": 0.09975}
  -- 下方 CHECK 约束确保必须是 JSON 对象类型（不能是数组、字符串等）
  tax_rates jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- File path to store logo image (e.g., "stores/decarie/logo.png")
  -- 门店 Logo 图片的存储路径（如 "stores/decarie/logo.png"）
  store_logo text DEFAULT NULL,

  -- Soft delete timestamp; NULL = active store, non-NULL = closed / disabled
  -- 软删除时间戳；NULL 表示正常营业，非 NULL 表示门店已关闭/停用
  deleted_at timestamptz DEFAULT NULL,

  -- CHECK: tax_rates must be a JSON object (not array, string, number, etc.)
  -- 约束：tax_rates 必须是 JSON 对象类型
  CONSTRAINT chk_store_list_tax_rates_is_object
    CHECK (jsonb_typeof(tax_rates) = 'object')
);


-- =============================================
-- Migration safety patch: add newly introduced store profile fields
-- 迁移兼容补丁：补充新增门店信息字段
-- =============================================
ALTER TABLE public.store_list ADD COLUMN IF NOT EXISTS store_sale_policy text;
ALTER TABLE public.store_list ADD COLUMN IF NOT EXISTS store_repair_policy text;
ALTER TABLE public.store_list ADD COLUMN IF NOT EXISTS store_website text;
ALTER TABLE public.store_list ADD COLUMN IF NOT EXISTS store_postcode text;
ALTER TABLE public.store_list ADD COLUMN IF NOT EXISTS store_qr text;
ALTER TABLE public.store_list ADD COLUMN IF NOT EXISTS store_qr_note_before text;
ALTER TABLE public.store_list ADD COLUMN IF NOT EXISTS store_qr_note_after text;
