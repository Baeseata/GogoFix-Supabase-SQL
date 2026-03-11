-- Local SQLite version of 01_store_list.sql
-- Source: Supabase SQL/01_cloud_store_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_list (


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
  tax_rates text NOT NULL DEFAULT '{}',

  -- File path to store logo image (e.g., "stores/decarie/logo.png")
  -- 门店 Logo 图片的存储路径（如 "stores/decarie/logo.png"）
  store_logo text DEFAULT NULL,

  -- Store-level visibility scope (which stores' data this store is allowed to access)
  -- 门店级可见范围（本门店被允许访问哪些门店的数据）
  -- Example / 示例: {'decarie','marcel'}
  visible_store_ids text[] NOT NULL DEFAULT '[]',

  -- Store activation flag: false means the store is inactive for operational workflows
  -- 门店激活状态：false 表示门店不参与多数运营流程
  is_active integer NOT NULL DEFAULT 1,

  -- Soft delete timestamp; NULL = active store, non-NULL = closed / disabled
  -- 软删除时间戳；NULL 表示正常营业，非 NULL 表示门店已关闭/停用
  deleted_at text DEFAULT NULL,

  -- CHECK: tax_rates must be a JSON object (not array, string, number, etc.)
  -- 约束：tax_rates 必须是 JSON 对象类型
  CONSTRAINT chk_store_list_tax_rates_is_object
    CHECK (json_type(tax_rates) = 'object')
);
