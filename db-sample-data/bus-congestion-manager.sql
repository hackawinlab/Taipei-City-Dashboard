-- bus-congestion-manager.sql
-- dashboardmanager DB (port 5432) migration
-- 新增公車壅塞地圖層設定

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
ON CONFLICT DO NOTHING;

-- 2. Component 設定
INSERT INTO public.components (index, name)
VALUES ('bus_congestion_layer', '公車 ETA 壅塞偵測')
ON CONFLICT (index) DO NOTHING;

-- 3. query_charts 設定（地圖圖例 + 關聯圖層）
-- 注意：若 bus_congestion_layer 已存在，只更新 map_config_ids
DO $$
DECLARE
  abs_id   INTEGER;
  delta_id INTEGER;
  comp_created_at TIMESTAMPTZ := now();
BEGIN
  SELECT id INTO abs_id   FROM public.component_maps WHERE index = 'bus_congestion_abs'   LIMIT 1;
  SELECT id INTO delta_id FROM public.component_maps WHERE index = 'bus_congestion_delta' LIMIT 1;

  IF EXISTS (SELECT 1 FROM public.query_charts WHERE index = 'bus_congestion_layer') THEN
    UPDATE public.query_charts
    SET map_config_ids = ARRAY[abs_id, delta_id],
        updated_at = now()
    WHERE index = 'bus_congestion_layer';
  ELSE
    INSERT INTO public.query_charts
      (index, query_type, query_chart, map_config_ids, created_at, updated_at)
    VALUES (
      'bus_congestion_layer',
      'map_legend',
      $sql$SELECT unnest(array['暢通(≤0s)','輕微(+1~30s)','中度(+31~60s)','嚴重(+61~120s)','極嚴重(>120s)','無資料']) as name, 'line' as type$sql$,
      ARRAY[abs_id, delta_id],
      comp_created_at,
      comp_created_at
    );
  END IF;
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

-- 5. 加入 group（台北市 group_id=2）
INSERT INTO public.dashboard_groups (dashboard_id, group_id)
SELECT id, 2
FROM public.dashboards
WHERE index = 'smart_commute_taipei'
ON CONFLICT DO NOTHING;
