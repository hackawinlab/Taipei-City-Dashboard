-- YouBike 空車站佔比時段分布 — Block 1 重生為真實 BE component。
-- 併入 youbike-analysis-{taipei,metrotaipei} dashboard，splice 在 timemap 與 persistence 之間。
-- Run against dashboardmanager DB AFTER:
--   - dashboardmanager-demo.sql
--   - youbike-timemap-seed.sql
--   - youbike-analysis-dashboard.sql
--   - youbike-shortage-blocks-seed.sql  (建 persistence + imbalance)
-- Idempotent：可重複執行。

-- 1. Schema migration: TimelineSeparateChart.vue 讀 chart_config.fit 才能自適應卡片高度。
--    chart_config 是 row_to_json(component_charts.*) 投影出來的，schema 必須有 fit 欄位
--    才能持久化此設定（舊 client-side shim 直接構造物件可塞任意 key，已不適用）。
ALTER TABLE component_charts ADD COLUMN IF NOT EXISTS fit BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Component charts (api_endpoint 接管 chart-data fetch；color 直接套 production 既有色票)
INSERT INTO component_charts (index, color, types, unit, api_endpoint, fit)
VALUES
  ('youbike_shortage', '{"#ca0020","#154360"}', '{TimelineSeparateChart}', '%',
   '/commute/youbike/shortage', TRUE)
ON CONFLICT (index) DO UPDATE
  SET color        = EXCLUDED.color,
      types        = EXCLUDED.types,
      unit         = EXCLUDED.unit,
      api_endpoint = EXCLUDED.api_endpoint,
      fit          = EXCLUDED.fit;

-- 3. Components (id 由 sequence 分配；以 index 唯一鍵 idempotent upsert)
INSERT INTO components (index, name)
VALUES
  ('youbike_shortage', 'YouBike 空車站佔比時段分布')
ON CONFLICT (index) DO UPDATE
  SET name = EXCLUDED.name;

-- 4. Query charts (每 city 一列；query_chart 留空，api_endpoint 接管不會被執行)。
--    query_charts 沒有 (index, city) unique constraint，無法用 ON CONFLICT，
--    改成「先刪後插」（仿 persistence/imbalance pattern）。
DELETE FROM query_charts
 WHERE index = 'youbike_shortage'
   AND city  IN ('taipei', 'metrotaipei');

INSERT INTO query_charts
  (index, history_config, map_config_ids, map_filter, time_from, update_freq,
   update_freq_unit, source, short_desc, long_desc, use_case, links,
   contributors, created_at, updated_at, query_type, query_chart, city)
VALUES
  ('youbike_shortage', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示一日各時段中可借車輛為 0 的站點佔全市站點的比率。',
   '以每小時為單位，計算可借車輛為 0（即站點上完全借不到車）的站點佔全市站點的比率，呈現一日內缺車最為集中的時段。「= 0 車」之門檻與「YouBike 見車率」採「≥ 1 車」之門檻互補：見車率關注「站點」層面長期借車成功率，本指標關注「時段」層面的全市缺車強度。資料採用本機 youbike_snapshots 多日累積快照，因樣本仍受觀測窗影響，平假日與長期趨勢分析需累積跨日資料後再行比較。',
   '作為調度時段規劃的初步參考，協助辨識缺車尖峰時段並做為補車班次設計的輔助資訊。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'taipei'),

  ('youbike_shortage', NULL, ARRAY[]::integer[], '{}', 'static', 1,
   'hour', 'YouBike 開放資料',
   '顯示一日各時段中可借車輛為 0 的站點佔全市站點的比率。',
   '以每小時為單位，計算可借車輛為 0（即站點上完全借不到車）的站點佔全市站點的比率，呈現一日內缺車最為集中的時段。「= 0 車」之門檻與「YouBike 見車率」採「≥ 1 車」之門檻互補：見車率關注「站點」層面長期借車成功率，本指標關注「時段」層面的全市缺車強度。資料採用本機 youbike_snapshots 多日累積快照，因樣本仍受觀測窗影響，平假日與長期趨勢分析需累積跨日資料後再行比較。',
   '作為調度時段規劃的初步參考，協助辨識缺車尖峰時段並做為補車班次設計的輔助資訊。',
   '{}', '{doit}', NOW(), NOW(), 'two_d', '', 'metrotaipei');

-- 5. dashboards.components — splice shortage 進 timemap 與 persistence 之間。
--    防呆：7 個 component 任一缺，子查詢會塞 NULL 進 array，這裡用 WHERE 限制
--    只在 7 個 index 全存在時才 update，避免 dashboard 變成含 NULL 的陣列。
UPDATE dashboards
SET components = ARRAY[
  (SELECT id FROM components WHERE index = 'youbike_timemap'),
  (SELECT id FROM components WHERE index = 'youbike_shortage'),
  (SELECT id FROM components WHERE index = 'youbike_persistence'),
  (SELECT id FROM components WHERE index = 'youbike_imbalance'),
  (SELECT id FROM components WHERE index = 'youbike_availability'),
  (SELECT id FROM components WHERE index = 'bike_map'),
  (SELECT id FROM components WHERE index = 'bike_network')
]::integer[],
    updated_at = NOW()
WHERE index IN ('youbike-analysis-taipei', 'youbike-analysis-metrotaipei')
  AND 7 = (
    SELECT COUNT(*) FROM components
    WHERE index IN ('youbike_timemap','youbike_shortage','youbike_availability',
                    'youbike_persistence','youbike_imbalance','bike_map','bike_network')
  );
