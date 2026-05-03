-- YouBike 缺車成因分析 — 兩個 block（persistence、imbalance）作為真實 BE component
-- 併入 youbike-analysis-{taipei,metrotaipei} dashboard。
-- Run against dashboardmanager DB after dashboardmanager-demo.sql、
-- youbike-timemap-seed.sql 與 youbike-analysis-dashboard.sql。
-- Idempotent：可重複執行。

-- 1. Schema migration（鏡像 component_maps.api_endpoint）
ALTER TABLE component_charts ADD COLUMN IF NOT EXISTS api_endpoint VARCHAR;

-- 2. Component charts（types/color/unit + api_endpoint）
INSERT INTO component_charts (index, color, types, unit, api_endpoint)
VALUES
  ('youbike_persistence', '{"#ff6b6b"}', '{BarChart}', '小時', '/commute/youbike/persistence'),
  ('youbike_imbalance',   '{"#fb7185"}', '{BarChart}', '輛',   '/commute/youbike/imbalance')
ON CONFLICT (index) DO UPDATE
  SET color        = EXCLUDED.color,
      types        = EXCLUDED.types,
      unit         = EXCLUDED.unit,
      api_endpoint = EXCLUDED.api_endpoint;

-- 3. Components（id 由 sequence 分配；用 index 唯一鍵 idempotent upsert）
INSERT INTO components (index, name)
VALUES
  ('youbike_persistence', 'YouBike 長時段缺車站排行'),
  ('youbike_imbalance',   'YouBike 站點淨流出量排行')
ON CONFLICT (index) DO UPDATE
  SET name = EXCLUDED.name;

-- 4. Query charts（每 component × 每 city；query_chart 留空字串，
--    api_endpoint 路徑接管，不會被 controller 執行）
--
--    query_charts 沒有 (index, city) unique constraint，所以無法用 ON CONFLICT。
--    改成「先刪後插」：每次重跑都會刷新 short_desc / long_desc 等描述欄位。
DELETE FROM query_charts
 WHERE index IN ('youbike_persistence', 'youbike_imbalance')
   AND city  IN ('taipei', 'metrotaipei');

INSERT INTO query_charts
  (index, history_config, map_config_ids, map_filter, time_from, update_freq,
   update_freq_unit, source, short_desc, long_desc, use_case, links,
   contributors, created_at, updated_at, query_type, query_chart, city)
VALUES
  ('youbike_persistence', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示觀測時段內每小時平均可借車輛低於 1 的小時數最多的前 20 站。',
   '以觀測時段中每小時的平均可借車輛數作為基準，當該時段平均可借車輛低於 1 時計入該站的缺車時數，並依累計時數由高至低排序。本指標反映站點長時間處於可借車輛不足之狀態，前段排名以站柱數較少的觀光與郊區終點型站為主，係因該類站點車量上限較低、達門檻所需流出量較少。資料採用 2026/05/01 之單日快照，與線上「YouBike 見車率」之月度統計相互對照可獲得較完整之長期趨勢。',
   '輔助辨識長時間缺車之站點，作為補給班次規劃、站點規模檢討及調度資源配置之參考。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'taipei'),

  ('youbike_persistence', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示觀測時段內每小時平均可借車輛低於 1 的小時數最多的前 20 站。',
   '以觀測時段中每小時的平均可借車輛數作為基準，當該時段平均可借車輛低於 1 時計入該站的缺車時數，並依累計時數由高至低排序。本指標反映站點長時間處於可借車輛不足之狀態，前段排名以站柱數較少的觀光與郊區終點型站為主，係因該類站點車量上限較低、達門檻所需流出量較少。資料採用 2026/05/01 之單日快照，與線上「YouBike 見車率」之月度統計相互對照可獲得較完整之長期趨勢。',
   '輔助辨識長時間缺車之站點，作為補給班次規劃、站點規模檢討及調度資源配置之參考。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'metrotaipei'),

  ('youbike_imbalance', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示觀測時段內估計借出量與歸還量差距最大之前 15 站。',
   '以 30 分鐘間隔快照逐筆比對可借車輛數變化，將下降量加總作為估計借出量、上升量加總作為估計歸還量（含調度補車），兩者差值之絕對值最高者代表結構性流出顯著大於歸還之站點。歸還量並依單筆變化幅度區分為市民自然還車與調度補車。資料採用 2026/05/01 之單日快照，連續多日累積後可進一步辨識結構性需求站點。',
   '作為補車班次優先序、調度路線規劃及站點需求結構分析之輔助資訊。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'taipei'),

  ('youbike_imbalance', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示觀測時段內估計借出量與歸還量差距最大之前 15 站。',
   '以 30 分鐘間隔快照逐筆比對可借車輛數變化，將下降量加總作為估計借出量、上升量加總作為估計歸還量（含調度補車），兩者差值之絕對值最高者代表結構性流出顯著大於歸還之站點。歸還量並依單筆變化幅度區分為市民自然還車與調度補車。資料採用 2026/05/01 之單日快照，連續多日累積後可進一步辨識結構性需求站點。',
   '作為補車班次優先序、調度路線規劃及站點需求結構分析之輔助資訊。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'metrotaipei');

-- 5. 把 youbike-analysis-{taipei,metrotaipei} 兩個 dashboard 的 components 陣列
--    重建成 5 個 id（idempotent，重跑也只會得到同一份結果）。
--    防呆：5 個 component 任何一個缺，subquery 會塞 NULL 進 array，這裡用 WHERE
--    限制只在全部存在時才 update，避免 dashboard 變成包含 NULL 的陣列。
UPDATE dashboards
SET components = ARRAY[
  (SELECT id FROM components WHERE index = 'youbike_timemap'),
  (SELECT id FROM components WHERE index = 'youbike_persistence'),
  (SELECT id FROM components WHERE index = 'youbike_imbalance'),
  (SELECT id FROM components WHERE index = 'bike_map'),
  (SELECT id FROM components WHERE index = 'bike_network')
]::integer[],
    updated_at = NOW()
WHERE index IN ('youbike-analysis-taipei', 'youbike-analysis-metrotaipei')
  AND (
    SELECT COUNT(*) FROM components
    WHERE index IN ('youbike_timemap','youbike_persistence',
                    'youbike_imbalance','bike_map','bike_network')
  ) = 5;
