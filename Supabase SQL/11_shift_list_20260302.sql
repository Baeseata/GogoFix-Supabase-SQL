-- =========================================
-- 11 · shift_list 班次表
-- =========================================
-- 依赖: 01_store_list (store_id)
--        03_user_list (user_id FK)
--        10_batch_list (store_id, batch_id 复合 FK)
-- 被依赖: 12_transaction_list (store_id, batch_id, shift_id 复合 FK)
--
-- 每个班次归属于某个 batch，同一设备同一时间只能有一个 open shift
-- 不支持软删除：班次是历史记录，关闭后永久保留

-- =========================================
-- 函数: assign_shift_id_per_store()
-- =========================================
-- 同一门店下，shift_id 从 1 开始全局递增（不按 batch 重置），由触发器分配
CREATE OR REPLACE FUNCTION public.assign_shift_id_per_store()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_sid int;
BEGIN
  IF NEW.store_id IS NULL OR NEW.batch_id IS NULL THEN
    RAISE EXCEPTION 'store_id and batch_id cannot be null';
  END IF;

  -- 咨询锁：命名空间 1003，按 store_id 锁定
  PERFORM pg_advisory_xact_lock(1003, hashtext(NEW.store_id));

  SELECT COALESCE(MAX(shift_id), 0) + 1
    INTO next_sid
  FROM public.shift_list
  WHERE store_id = NEW.store_id;

  NEW.shift_id := next_sid;
  RETURN NEW;
END;
$$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.shift_list (

  -- 门店 ID
  store_id text NOT NULL,

  -- 所属批次编号
  batch_id integer NOT NULL,

  -- 班次编号，同一门店内全局递增（不随 batch 重置），由触发器分配
  shift_id integer NOT NULL,

  -- 当班用户
  user_id integer REFERENCES public.user_list(user_id),

  -- 使用的设备 ID
  device_id text DEFAULT NULL,

  -- 班次是否处于开启状态
  is_open boolean NOT NULL DEFAULT true,

  -- 班次开启时间
  opened_at timestamptz NOT NULL DEFAULT now(),

  -- 班次关闭时间；开启状态下应为 NULL
  closed_at timestamptz DEFAULT NULL,

  -- 开班时的现金底数
  opening_cash numeric(10,2) NOT NULL DEFAULT 0,

  -- 关班时的现金实点数；开班状态下允许为 NULL
  closing_cash numeric(10,2) DEFAULT NULL,

  -- 备注
  note text DEFAULT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 三列联合主键
  CONSTRAINT shift_list_pk PRIMARY KEY (store_id, batch_id, shift_id),

  -- shift_id 应为正整数
  CONSTRAINT shift_list_shift_id_positive CHECK (shift_id > 0),

  -- 开关状态一致性
  CONSTRAINT shift_list_open_close_consistency CHECK (
    (is_open = true  AND closed_at IS NULL)
    OR
    (is_open = false AND closed_at IS NOT NULL)
  ),

  -- 外键指向 batch_list
  CONSTRAINT shift_list_fk_batch
    FOREIGN KEY (store_id, batch_id)
    REFERENCES public.batch_list (store_id, batch_id)
);

-- =========================================
-- shift_id 自动分配触发器
-- =========================================
DROP TRIGGER IF EXISTS trg_shift_list_assign_id ON public.shift_list;
CREATE TRIGGER trg_shift_list_assign_id
BEFORE INSERT ON public.shift_list
FOR EACH ROW
EXECUTE FUNCTION public.assign_shift_id_per_store();

-- =========================================
-- 同一设备同一时间只能有一个 open shift
-- =========================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_shift_one_open_per_device
  ON public.shift_list (store_id, device_id)
  WHERE is_open = true AND device_id IS NOT NULL;

-- =========================================
-- 索引
-- =========================================

-- 某店最近班次
CREATE INDEX IF NOT EXISTS idx_shift_store_opened_at
  ON public.shift_list (store_id, opened_at DESC);

-- 某 batch 下的班次
CREATE INDEX IF NOT EXISTS idx_shift_batch_opened_at
  ON public.shift_list (store_id, batch_id, opened_at DESC);

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_shift_list_updated_at ON public.shift_list;
CREATE TRIGGER trg_shift_list_updated_at
BEFORE UPDATE ON public.shift_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
