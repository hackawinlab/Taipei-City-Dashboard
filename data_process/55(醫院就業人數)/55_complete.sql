-- 醫院就業人數統計完整設定檔
-- 參考 76_complete.sql 結構，為醫院就業人數數據建立完整的組件配置
-- 步驟 1：新增元件 - 醫院就業人數統計
INSERT INTO public.components (id, index, name)
VALUES (
		309,
		'hospital_employment_stats',
		'醫院就業人數統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'hospital_employment_stats',
		'{#FF6B6B,#4ECDC4,#45B7D1,#96CEB4,#FFEAA7,#DDA0DD,#98FB98,#F0E68C,#FFB6C1,#87CEEB,#D2691E,#FF7F50,#6495ED,#20B2AA,#9370DB,#32CD32,#FF69B4,#1E90FF,#FF8C00,#8A2BE2,#FF1493,#00CED1,#9ACD32,#FF4500,#DA70D6}',
		'{BarChart,ColumnChart,DonutChart}',
		'人'
	);
-- 步驟 3：新增醫院就業人數統計資料表
CREATE TABLE public.hospital_employment_stats (city TEXT, profession TEXT, staff_count INT);
-- 步驟 4：新增醫院就業人數統計資料（臺北市+新北市+雙北）
INSERT INTO public.hospital_employment_stats (city, profession, staff_count)
VALUES -- 臺北市資料
	('臺北市', '西醫師', 8385),
	('臺北市', '中醫師', 154),
	('臺北市', '牙醫師', 635),
	('臺北市', '藥師', 1687),
	('臺北市', '藥劑生', 3),
	('臺北市', '醫事檢驗師', 1655),
	('臺北市', '醫事檢驗生', 8),
	('臺北市', '醫事放射師', 1434),
	('臺北市', '醫事放射士', 1),
	('臺北市', '護理師', 20774),
	('臺北市', '助產師', 0),
	('臺北市', '助產士', 0),
	('臺北市', '牙體技術師', 625),
	('臺北市', '營養師', 13),
	('臺北市', '物理治療師', 9),
	('臺北市', '物理治療生', 0),
	('臺北市', '職能治療師', 292),
	('臺北市', '職能治療生', 481),
	('臺北市', '臨床心理師', 36),
	('臺北市', '諮商心理師', 309),
	('臺北市', '呼吸治療師', 3),
	('臺北市', '語言治療師', 198),
	('臺北市', '聽力師', 25),
	('臺北市', '牙體技術生', 331),
	('臺北市', '鑲牙生', 111),
	('臺北市', '驗光師', 66),
	('臺北市', '驗光生', 29),
	-- 新北市資料
	('新北市', '西醫師', 3467),
	('新北市', '中醫師', 67),
	('新北市', '牙醫師', 186),
	('新北市', '藥師', 837),
	('新北市', '藥劑生', 10),
	('新北市', '醫事檢驗師', 721),
	('新北市', '醫事檢驗生', 7),
	('新北市', '醫事放射師', 694),
	('新北市', '醫事放射士', 3),
	('新北市', '護理師', 11446),
	('新北市', '助產師', 0),
	('新北市', '助產士', 0),
	('新北市', '牙體技術師', 531),
	('新北市', '營養師', 10),
	('新北市', '物理治療師', 4),
	('新北市', '物理治療生', 0),
	('新北市', '職能治療師', 173),
	('新北市', '職能治療生', 344),
	('新北市', '臨床心理師', 20),
	('新北市', '諮商心理師', 289),
	('新北市', '呼吸治療師', 5),
	('新北市', '語言治療師', 134),
	('新北市', '聽力師', 8),
	('新北市', '牙體技術生', 301),
	('新北市', '鑲牙生', 123),
	('新北市', '驗光師', 40),
	('新北市', '驗光生', 5),
	-- 雙北合計資料
	('雙北', '西醫師', 11852),
	('雙北', '中醫師', 221),
	('雙北', '牙醫師', 821),
	('雙北', '藥師', 2524),
	('雙北', '藥劑生', 13),
	('雙北', '醫事檢驗師', 2376),
	('雙北', '醫事檢驗生', 15),
	('雙北', '醫事放射師', 2128),
	('雙北', '醫事放射士', 4),
	('雙北', '護理師', 32220),
	('雙北', '助產師', 0),
	('雙北', '助產士', 0),
	('雙北', '牙體技術師', 1156),
	('雙北', '營養師', 23),
	('雙北', '物理治療師', 13),
	('雙北', '物理治療生', 0),
	('雙北', '職能治療師', 465),
	('雙北', '職能治療生', 825),
	('雙北', '臨床心理師', 56),
	('雙北', '諮商心理師', 598),
	('雙北', '呼吸治療師', 8),
	('雙北', '語言治療師', 332),
	('雙北', '聽力師', 33),
	('雙北', '牙體技術生', 632),
	('雙北', '鑲牙生', 234),
	('雙北', '驗光師', 106),
	('雙北', '驗光生', 34);
-- 步驟 5：新增 query_charts 設定 - 臺北市
INSERT INTO public.query_charts (
		index,
		history_config,
		map_config_ids,
		map_filter,
		time_from,
		time_to,
		update_freq,
		update_freq_unit,
		source,
		short_desc,
		long_desc,
		use_case,
		links,
		contributors,
		created_at,
		updated_at,
		query_type,
		query_chart,
		query_history,
		city
	)
VALUES (
		'hospital_employment_stats',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'臺北市醫院就業人數統計',
		'顯示臺北市醫院各類醫療專業人員的就業人數統計，包含西醫師、護理師、藥師、醫事檢驗師等各類醫療從業人員的人力分布情況。',
		'可用於了解臺北市醫療人力資源配置，支援醫療人力規劃、專業人員培育政策制定及醫療服務品質管理。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT profession AS x_axis,
			staff_count AS data
		FROM public.hospital_employment_stats
		WHERE city = '臺北市'
			AND staff_count > 0
		ORDER BY staff_count DESC;
$$,
NULL,
'taipei'
);
-- 步驟 6：新增 query_charts 設定 - 雙北
INSERT INTO public.query_charts (
		index,
		history_config,
		map_config_ids,
		map_filter,
		time_from,
		time_to,
		update_freq,
		update_freq_unit,
		source,
		short_desc,
		long_desc,
		use_case,
		links,
		contributors,
		created_at,
		updated_at,
		query_type,
		query_chart,
		query_history,
		city
	)
VALUES (
		'hospital_employment_stats',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'雙北醫院就業人數統計',
		'顯示雙北地區（臺北市與新北市）醫院各類醫療專業人員的就業人數統計，包含西醫師、護理師、藥師、醫事檢驗師等各類醫療從業人員的人力分布情況。',
		'可用於了解雙北地區醫療人力資源配置，支援區域醫療人力規劃、專業人員培育政策制定及醫療服務品質管理。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT profession AS x_axis,
			staff_count AS data
		FROM public.hospital_employment_stats
		WHERE city = '雙北'
			AND staff_count > 0
		ORDER BY staff_count DESC;
$$,
NULL,
'metrotaipei'
);
-- 步驟 7：建立索引以提升查詢效能
CREATE INDEX idx_hospital_employment_city ON public.hospital_employment_stats(city);
CREATE INDEX idx_hospital_employment_profession ON public.hospital_employment_stats(profession);
-- 步驟 8：將組件加入到相關的 dashboard 中
-- 注意：實際執行時需要確認 dashboard_id 和調整 order_index
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 309, 17); -- 臺北市醫院就業人數統計
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (2, 309, 18); -- 雙北醫院就業人數統計
-- 備註：
-- 1. component_id 使用 309，請確保不與現有組件衝突
-- 2. 臺北市和雙北都使用 two_d 查詢類型，按就業人數降序排列
-- 3. 數據來源為原始 55.sql 中的真實數據，已重新整理為標準化格式
-- 4. 臺北市組件屬於 'taipei' 城市，雙北組件屬於 'metrotaipei' 城市
-- 5. 使用 BarChart 作為主要圖表類型，適合比較不同職業的就業人數
-- 6. 同時支援 ColumnChart 和 DonutChart，提供多種視覺化選擇
-- 7. 單位設定為 '人'，符合就業人數的計量單位
-- 8. 雙北數據為臺北市和新北市的合計值
-- 9. 按就業人數降序排列，讓人數最多的職業優先顯示
-- 10. 護理師人數最多，其次是西醫師、藥師等
-- 11. 查詢條件加入 staff_count > 0 過濾掉人數為0的職業
-- 12. 支援 DonutChart 顯示各職業就業人數的比例分布
-- 13. 數據反映了醫療體系中不同專業人員的人力配置情況
-- 14. 可用於醫療政策制定和專業人員培育規劃參考
-- 15. 涵蓋醫師、護理、藥學、檢驗、放射、復健等各專業領域
-- 16. 助產師/助產士在兩個城市都為0人，反映現代醫療體系變化