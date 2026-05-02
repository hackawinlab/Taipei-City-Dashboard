-- bus-congestion.sql
-- dashboard DB (port 5433) migration
-- 建立公車壅塞路段資料表

CREATE TABLE IF NOT EXISTS public.bus_congestion_segments (
    id         SERIAL PRIMARY KEY,
    seg_id     TEXT NOT NULL,
    from_name  TEXT,
    to_name    TEXT,
    direction  TEXT,
    city       TEXT,
    seg_err    DOUBLE PRECISION,
    color      TEXT,
    label      TEXT,
    has_delta  BOOLEAN DEFAULT false,
    n_samples  INTEGER DEFAULT 0,
    geojson    TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bus_cong_city ON public.bus_congestion_segments (city);
CREATE INDEX IF NOT EXISTS idx_bus_cong_err  ON public.bus_congestion_segments (seg_err DESC);
