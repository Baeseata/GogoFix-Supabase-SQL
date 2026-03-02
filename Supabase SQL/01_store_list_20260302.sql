-- =========================================
-- 01 · store_list 门店主表
-- =========================================
-- 依赖: 无 (基础表，最先创建)
-- 被依赖: 几乎所有其他表通过 store_id FK 引用本表

CREATE TABLE IF NOT EXISTS public.store_list (

  -- 门店 ID，业务端自定义的文本标记（如 decarie / marcel / parcex）
  store_id text PRIMARY KEY,

  -- 门店名称，必填
  store_name text NOT NULL,

  -- 门店电话
  store_phone_number text DEFAULT NULL,

  -- 门店地址
  store_address text DEFAULT NULL,

  -- 门店邮箱（对账结算用）
  store_email_address text DEFAULT NULL,

  -- 报表接收邮箱（自动发送经营报表等）
  store_report_email text DEFAULT NULL,

  -- 税率配置，以 JSON 对象存储，例如 {"GST":0.05,"QST":0.09975}
  -- 约束确保必须是 JSON 对象类型（不能是数组、字符串等）
  tax_rates jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- 门店 Logo 的存储路径（如 stores/decarie/logo.png）
  store_logo text DEFAULT NULL,

  -- 软删除时间戳；NULL 表示正常营业，非 NULL 表示门店已关闭 / 停用
  deleted_at timestamptz DEFAULT NULL,

  -- tax_rates 必须是 JSON 对象
  CONSTRAINT store_list_tax_rates_is_object
    CHECK (jsonb_typeof(tax_rates) = 'object')
);
