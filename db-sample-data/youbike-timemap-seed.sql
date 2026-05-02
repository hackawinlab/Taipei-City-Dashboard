-- YouBike 一日可用率動態地圖 component seed
-- Run against dashboardmanager DB after dashboardmanager-demo.sql

-- 1. Schema migration (idempotent)
ALTER TABLE component_maps ADD COLUMN IF NOT EXISTS api_endpoint VARCHAR;

-- 2. Chart config
INSERT INTO component_charts (index, color, types, unit)
VALUES ('youbike_timemap', '{"#22c55e","#f97316","#ef4444"}', '{YouBikeTimeMap}', '')
ON CONFLICT (index) DO NOTHING;

-- 3. Component
INSERT INTO components (index, name)
VALUES ('youbike_timemap', 'YouBike 一日可用率動態地圖')
ON CONFLICT (index) DO NOTHING;

-- 4. Map config (api source)
INSERT INTO component_maps (index, title, type, source, api_endpoint, paint)
SELECT 'youbike_timemap', 'YouBike站點時段可用率', 'circle', 'api',
       '/api/commute/youbike/map',
       '{"circle-color":["step",["get","availability_pct"],"#ef4444",10,"#f97316",30,"#22c55e"],"circle-radius":["interpolate",["linear"],["get","total_docks"],10,4,50,9],"circle-opacity":0.85,"circle-stroke-width":1,"circle-stroke-color":"#1a1a1a"}'
WHERE NOT EXISTS (SELECT 1 FROM component_maps WHERE index = 'youbike_timemap');

-- 5. Query charts (taipei and metrotaipei)
INSERT INTO query_charts
  (index, history_config, map_config_ids, map_filter, time_from, update_freq,
   update_freq_unit, source, short_desc, long_desc, use_case, links,
   contributors, created_at, updated_at, query_type, query_chart, city)
SELECT
  'youbike_timemap', NULL, ARRAY[cm.id]::integer[], '{}', 'current', 30,
  'minute', '交通局', '顯示YouBike各站點一日可用率動態地圖',
  '透過時間滑桿顯示YouBike各站點在一日24小時中的可用率變化，顏色以紅橙綠三色表示缺車、普通、充足三個狀態。',
  '用於分析YouBike各站點在不同時段的可用率分布，有助於了解城市共享單車使用模式，優化站點規劃與調度策略。',
  '{}', '{doit}', NOW(), NOW(), 'map_legend',
  'SELECT ''YouBike'' AS name, ''circle'' AS type', city_val.city
FROM component_maps cm
CROSS JOIN (VALUES ('taipei'), ('metrotaipei')) AS city_val(city)
WHERE cm.index = 'youbike_timemap'
  AND NOT EXISTS (
    SELECT 1 FROM query_charts qc
    WHERE qc.index = 'youbike_timemap' AND qc.city = city_val.city
  )
ORDER BY cm.id DESC
LIMIT 2;
