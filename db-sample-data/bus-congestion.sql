-- bus-congestion.sql
-- dashboard DB (port 5433) migration
-- 建立公車壅塞路段資料表（idempotent）

-- ────────────────────────────────────────────
-- Tables
-- ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.bus_congestion_history (
    seg_id        TEXT NOT NULL,
    snapshot_time TIMESTAMPTZ NOT NULL,
    color         TEXT,
    label         TEXT,
    seg_err       DOUBLE PRECISION,
    n_samples     INTEGER
);

CREATE SEQUENCE IF NOT EXISTS public.bus_congestion_segments_id_seq
    AS INTEGER
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE IF NOT EXISTS public.bus_congestion_segments (
    id             INTEGER NOT NULL DEFAULT nextval('public.bus_congestion_segments_id_seq'::regclass),
    seg_id         TEXT NOT NULL,
    from_name      TEXT,
    to_name        TEXT,
    direction      TEXT,
    city           TEXT,
    seg_err        DOUBLE PRECISION,
    color          TEXT,
    label          TEXT,
    has_delta      BOOLEAN DEFAULT false,
    n_samples      INTEGER DEFAULT 0,
    geojson        TEXT,
    updated_at     TIMESTAMPTZ DEFAULT now(),
    route_id       TEXT,
    route_uid      TEXT,
    route_name     TEXT,
    sub_route_id   TEXT,
    sub_route_uid  TEXT,
    sub_route_name TEXT
);

ALTER SEQUENCE IF EXISTS public.bus_congestion_segments_id_seq
    OWNED BY public.bus_congestion_segments.id;

ALTER TABLE ONLY public.bus_congestion_segments
    DROP CONSTRAINT IF EXISTS bus_congestion_segments_pkey;
ALTER TABLE ONLY public.bus_congestion_segments
    ADD CONSTRAINT bus_congestion_segments_pkey PRIMARY KEY (id);

-- ────────────────────────────────────────────
-- Views
-- ────────────────────────────────────────────

CREATE OR REPLACE VIEW public.bus_congestion_segment_dim AS
    SELECT DISTINCT ON (seg_id)
        seg_id, from_name, to_name, direction, city,
        route_id, route_uid, route_name,
        sub_route_id, sub_route_uid, sub_route_name
    FROM public.bus_congestion_segments
    ORDER BY seg_id, id;

-- ────────────────────────────────────────────
-- Materialized view
-- ────────────────────────────────────────────

CREATE MATERIALIZED VIEW IF NOT EXISTS public.bus_congestion_history_segments AS
    SELECT
        h.seg_id, h.snapshot_time,
        d.city,
        d.route_id, d.route_uid, d.route_name,
        d.sub_route_id, d.sub_route_uid, d.sub_route_name,
        d.direction, d.from_name, d.to_name,
        h.color, h.label, h.seg_err, h.n_samples
    FROM public.bus_congestion_history h
    JOIN public.bus_congestion_segment_dim d USING (seg_id)
    WHERE h.seg_id LIKE '%-%'
    WITH NO DATA;

-- ────────────────────────────────────────────
-- Indexes
-- ────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_bus_cong_city
    ON public.bus_congestion_segments USING btree (city);

CREATE INDEX IF NOT EXISTS idx_bus_cong_city_route_name
    ON public.bus_congestion_segments USING btree (city, route_name);

CREATE INDEX IF NOT EXISTS idx_bus_cong_err
    ON public.bus_congestion_segments USING btree (seg_err DESC);

CREATE INDEX IF NOT EXISTS idx_bus_cong_route_name
    ON public.bus_congestion_segments USING btree (route_name);

CREATE INDEX IF NOT EXISTS idx_bus_cong_route_uid
    ON public.bus_congestion_segments USING btree (route_uid);

CREATE INDEX IF NOT EXISTS idx_bus_congestion_history_seg_time
    ON public.bus_congestion_history USING btree (seg_id, snapshot_time);

CREATE INDEX IF NOT EXISTS idx_bus_congestion_history_time
    ON public.bus_congestion_history USING btree (snapshot_time);

CREATE INDEX IF NOT EXISTS idx_bus_congestion_history_segments_city_time
    ON public.bus_congestion_history_segments USING btree (city, snapshot_time);

CREATE INDEX IF NOT EXISTS idx_bus_congestion_history_segments_route_time
    ON public.bus_congestion_history_segments USING btree (route_name, snapshot_time);

CREATE INDEX IF NOT EXISTS idx_bus_congestion_history_segments_seg_time
    ON public.bus_congestion_history_segments USING btree (seg_id, snapshot_time);

CREATE INDEX IF NOT EXISTS idx_bus_congestion_history_segments_time
    ON public.bus_congestion_history_segments USING btree (snapshot_time);
