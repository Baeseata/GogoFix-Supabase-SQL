-- =========================================
-- 16 · serialized_event_list 序列号商品事件表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        03_user_list (user_id FK)
--        09_store_serialized_list (unit_id FK)
--        09 中的 ENUM serialized_status（本文件扩展 lost / wasted 值）
-- 被依赖: 无
--
-- 记录每一件 serialized 商品的完整生命线（状态变化历史）
-- 支持离线创建：主键由客户端生成 UUID v7
-- 设计上只允许 INSERT，不应 UPDATE 或 DELETE（但数据库层面不做强制拦截，留后余地）

-- =========================================
-- 扩展 serialized_status 枚举：新增 lost、wasted 状态
-- =========================================
-- 原枚举（09_store_serialized_list 中创建）：
--   'in_stock', 'in_transit', 'sold', 'repair', 'void'
-- 本处新增：
--   'lost'   = 丢失
--   'wasted' = 报废
-- ALTER TYPE ... ADD VALUE 是幂等安全的（IF NOT EXISTS）
ALTER TYPE public.serialized_status ADD VALUE IF NOT EXISTS 'lost';
ALTER TYPE public.serialized_status ADD VALUE IF NOT EXISTS 'wasted';

-- =========================================
-- ENUM: serialized_event_type 事件类型枚举
-- =========================================
-- 每种 event_type 对应 serialized_status 的一次状态迁移：
--   purchase              : → in_stock        新货入库，在 store_serialized_list 创建新行
--   sell                  : in_stock → sold    卖出
--   return                : sold → in_stock    客户退货回库
--   mark_as_sold          : in_stock → sold    手动标记为已售（非交易触发）
--   mark_as_lost          : in_stock → lost    标记为丢失
--   mark_as_wasted        : in_stock → wasted  标记为报废
--   store_transferred     : in_stock → in_transit   调拨发出
--   transferred_accepted  : in_transit → in_stock   调拨接收（同时 store_id 变更）
--   repair_out            : in_stock → repair  送修
--   repair_in             : repair → in_stock  修完回库
--   delete                : in_stock → void    作废
--   revive                : void → in_stock    从作废恢复
--   serial_edit           : （无状态变化）      修改了序列号
DO $$
BEGIN
  CREATE TYPE public.serialized_event_type AS ENUM (
    'purchase',
    'sell',
    'return',
    'mark_as_sold',
    'mark_as_lost',
    'mark_as_wasted',
    'store_transferred',
    'transferred_accepted',
    'repair_out',
    'repair_in',
    'delete',
    'revive',
    'serial_edit'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.serialized_event_list (

  -- 全局唯一主键，由客户端生成 UUID v7
  event_id uuid PRIMARY KEY,

  -- 事件类型
  event_type public.serialized_event_type NOT NULL,

  -- 事件发生的门店
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 关联的序列号单件，外键指向 store_serialized_list
  unit_id integer NOT NULL REFERENCES public.store_serialized_list(unit_id),

  -- 操作人
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- 关联交易 ID：sell / return 事件时有值，其他事件为 NULL
  -- 不加外键：离线场景下关联交易可能尚未同步
  transaction_id uuid DEFAULT NULL,

  -- 关联交易明细行 ID：sell / return 事件时有值，其他事件为 NULL
  -- 不加外键：同上
  line_id uuid DEFAULT NULL,

  -- 事件结束时该单件的 serial 值，由客户端填写
  -- 对于 serial_edit 事件，本值为修改后的新 serial
  serial text NOT NULL,

  -- 事件备注，可空
  -- serial_edit + swap 操作时，客户端填写互换的两组 serial 号
  note text DEFAULT NULL,

  -- 客户端本地创建时间（离线场景下由客户端提供）
  created_at timestamptz NOT NULL
);

-- =========================================
-- 索引
-- =========================================

-- 查询个单件的完整事件时间线（最高频查询）
CREATE INDEX IF NOT EXISTS idx_serialized_event_unit
  ON public.serialized_event_list (unit_id, created_at DESC);

-- 查询门店的所有事件
CREATE INDEX IF NOT EXISTS idx_serialized_event_store
  ON public.serialized_event_list (store_id, created_at DESC);

-- 查询某笔交易关联的事件
CREATE INDEX IF NOT EXISTS idx_serialized_event_transaction
  ON public.serialized_event_list (transaction_id)
  WHERE transaction_id IS NOT NULL;

-- 按事件类型过滤
CREATE INDEX IF NOT EXISTS idx_serialized_event_type
  ON public.serialized_event_list (event_type);

-- 查询用户的操作记录
CREATE INDEX IF NOT EXISTS idx_serialized_event_user
  ON public.serialized_event_list (user_id);
