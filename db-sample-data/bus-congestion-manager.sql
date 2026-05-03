-- bus-congestion-manager.sql
-- dashboardmanager DB (port 5432) migration
-- 新增公車壅塞地圖層設定

-- 0. 確保 idempotent upsert 所需的 unique 索引存在
-- query_charts / component_maps 出廠 schema 沒有 (index,city) / (index) 的 unique 約束,
-- 若沒有這兩個索引,下面的 ON CONFLICT 子句會以
-- "no unique or exclusion constraint matching the ON CONFLICT specification" 失敗。
--
-- 先去除 bus_congestion_{abs,delta} 的歷史重複（unique index 引入前 ON CONFLICT
-- DO NOTHING 沒有 constraint 可參考時根本不去重，重跑這個 seed 會累積重複行）；
-- 留 id 最小的一筆。對乾淨 DB 是 no-op。
DELETE FROM public.component_maps a
USING public.component_maps b
WHERE a.index IN ('bus_congestion_abs', 'bus_congestion_delta')
  AND a.index = b.index
  AND a.id > b.id;

CREATE UNIQUE INDEX IF NOT EXISTS component_maps_index_uniq
  ON public.component_maps (index);
CREATE UNIQUE INDEX IF NOT EXISTS query_charts_index_city_uniq
  ON public.query_charts (index, city);

-- 1. 地圖圖層設定
INSERT INTO public.component_maps (index, title, type, source, size, paint)
VALUES
  (
    'bus_congestion_abs',
    '公車壅塞（累積誤差）',
    'line',
    'geojson',
    'medium',
    '{"line-color": ["get", "color"], "line-width": ["interpolate",["linear"],["zoom"],10,3,15,6], "line-opacity": 0.85}'::json
  ),
  (
    'bus_congestion_delta',
    '公車壅塞（路段 Δerror）',
    'line',
    'geojson',
    'medium',
    '{"line-color": ["get", "color"], "line-width": ["interpolate",["linear"],["zoom"],10,3,15,6], "line-opacity": ["case",["get","has_delta"],1.0,0.45]}'::json
  )
ON CONFLICT (index) DO NOTHING;

-- 2. Component 設定
INSERT INTO public.components (index, name)
VALUES ('bus_congestion_layer', '公車 ETA 壅塞偵測')
ON CONFLICT (index) DO NOTHING;

-- 2b. Component chart 設定（MapLegend 圖例）
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
  'bus_congestion_layer',
  '{"#34A853","#FBBC04","#EA8600","#EA4335","#8B0000","#9CA3AF"}',
  ARRAY['MapLegend'],
  '路段'
)
ON CONFLICT (index) DO NOTHING;

-- 3. query_charts 設定（總覽壅塞路段數 + 關聯圖層）
-- ON CONFLICT (index, city) 依賴 §0 建立的 unique index。
-- time_from = 'static' 必填：FE DashboardComponent.dataTime 對非
-- 'static'/'current'/'demo'/'maintain' 的 time_from 會丟給
-- getComponentDataTimeframe，並在 time_to 為 NULL 時讀 undefined.slice 而 throw。
DO $$
DECLARE
  abs_id   INTEGER;
  delta_id INTEGER;
  comp_created_at TIMESTAMPTZ := now();
  taipei_query TEXT := $chart$
WITH levels AS (
  SELECT *
  FROM (VALUES
    (1, '暢通(≤0s)'),
    (2, '輕微(+1~30s)'),
    (3, '中度(+31~60s)'),
    (4, '嚴重(+61~120s)'),
    (5, '極嚴重(>120s)'),
    (6, '無資料')
  ) AS level(sort, name)
),
bucketed AS (
  SELECT CASE
    WHEN color IN ('#bbbbbb', '#444444') OR label ILIKE '%無資料%' THEN '無資料'
    WHEN seg_err <= 0 THEN '暢通(≤0s)'
    WHEN seg_err <= 30 THEN '輕微(+1~30s)'
    WHEN seg_err <= 60 THEN '中度(+31~60s)'
    WHEN seg_err <= 120 THEN '嚴重(+61~120s)'
    ELSE '極嚴重(>120s)'
  END AS name
  FROM public.bus_congestion_segments
  WHERE city = '台北市'
)
SELECT levels.name, 'line' AS type, COALESCE(COUNT(bucketed.name), 0)::float AS value
FROM levels
LEFT JOIN bucketed ON bucketed.name = levels.name
GROUP BY levels.sort, levels.name
ORDER BY levels.sort
$chart$;
  metrotaipei_query TEXT := $chart$
WITH levels AS (
  SELECT *
  FROM (VALUES
    (1, '暢通(≤0s)'),
    (2, '輕微(+1~30s)'),
    (3, '中度(+31~60s)'),
    (4, '嚴重(+61~120s)'),
    (5, '極嚴重(>120s)'),
    (6, '無資料')
  ) AS level(sort, name)
),
bucketed AS (
  SELECT CASE
    WHEN color IN ('#bbbbbb', '#444444') OR label ILIKE '%無資料%' THEN '無資料'
    WHEN seg_err <= 0 THEN '暢通(≤0s)'
    WHEN seg_err <= 30 THEN '輕微(+1~30s)'
    WHEN seg_err <= 60 THEN '中度(+31~60s)'
    WHEN seg_err <= 120 THEN '嚴重(+61~120s)'
    ELSE '極嚴重(>120s)'
  END AS name
  FROM public.bus_congestion_segments
  WHERE city IN ('台北市', '新北市')
)
SELECT levels.name, 'line' AS type, COALESCE(COUNT(bucketed.name), 0)::float AS value
FROM levels
LEFT JOIN bucketed ON bucketed.name = levels.name
GROUP BY levels.sort, levels.name
ORDER BY levels.sort
$chart$;
BEGIN
  SELECT id INTO abs_id   FROM public.component_maps WHERE index = 'bus_congestion_abs'   LIMIT 1;
  SELECT id INTO delta_id FROM public.component_maps WHERE index = 'bus_congestion_delta' LIMIT 1;

  INSERT INTO public.query_charts
    (index, city, query_type, query_chart, map_config_ids, time_from, created_at, updated_at)
  VALUES
    (
      'bus_congestion_layer', 'taipei', 'map_legend',
      taipei_query,
      ARRAY[abs_id, delta_id], 'static', comp_created_at, comp_created_at
    ),
    (
      'bus_congestion_layer', 'metrotaipei', 'map_legend',
      metrotaipei_query,
      ARRAY[abs_id, delta_id], 'static', comp_created_at, comp_created_at
    )
  ON CONFLICT (index, city) DO UPDATE
    SET query_chart    = EXCLUDED.query_chart,
        map_config_ids = EXCLUDED.map_config_ids,
        time_from      = EXCLUDED.time_from,
        updated_at     = now();
END $$;

-- 4. 加入智慧通勤 dashboard
-- 注意：若 smart_commute_taipei dashboard 不存在，自動建立（供全新部署使用）
INSERT INTO public.dashboards (index, name, components, icon, updated_at, created_at)
VALUES (
  'smart_commute_taipei',
  '智慧通勤',
  ARRAY(SELECT id FROM public.components WHERE index = 'bus_congestion_layer'),
  'directions_bus',
  now(), now()
)
ON CONFLICT (index) DO UPDATE
  SET components = (
    SELECT ARRAY(
      SELECT DISTINCT unnest(
        dashboards.components ||
        ARRAY(SELECT id FROM public.components WHERE index = 'bus_congestion_layer')
      )
    )
  ),
  updated_at = now();

-- 5. 加入 group（台北市 group_id=2，新北市 group_id=3）
INSERT INTO public.dashboard_groups (dashboard_id, group_id)
SELECT d.id, g.id
FROM public.dashboards d
CROSS JOIN (VALUES (2), (3)) AS g(id)
WHERE d.index = 'smart_commute_taipei'
ON CONFLICT DO NOTHING;
