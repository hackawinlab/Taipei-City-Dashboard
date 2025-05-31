-- 醫院服務量統計完整設定檔
-- 參考 87.sql 結構，為醫院服務量數據建立完整的組件配置
-- 步驟 1：新增元件 - 臺北市醫院服務量統計
INSERT INTO public.components (id, index, name)
VALUES (
		305,
		'hospital_service_volume',
		'醫院服務量統計'
	);
-- 步驟 3：設定圖表型態 - 臺北市
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'hospital_service_volume',
		'{#FF6B6B,#4ECDC4,#45B7D1,#96CEB4,#FFEAA7,#DDA0DD,#98FB98,#F0E68C,#FFB6C1,#87CEEB,#D2691E,#FF7F50,#6495ED}',
		'{ColumnChart,BarChart,DonutChart}',
		'人次'
	);
-- 步驟 5：新增雙北醫院服務量統計資料表
CREATE TABLE public.hospital_service_volume (
	city TEXT,
	service_type TEXT,
	service_count INT
);
-- 步驟 6：新增雙北醫院服務量統計資料（臺北市+新北市）
INSERT INTO public.hospital_service_volume (city, service_type, service_count)
VALUES -- 臺北市資料
	('臺北市', '出院人次', 590892),
	('臺北市', '住院健檢人次', 18885),
	('臺北市', '手術人次', 453956),
	('臺北市', '門診人次', 22898069),
	('臺北市', '急診人次', 973054),
	('臺北市', '門診體檢人次', 769835),
	('臺北市', '接生人次', 12591),
	('臺北市', '剖腹產人次', 4553),
	('臺北市', '洗腎人次', 726915),
	-- 雙北資料
	('雙北', '出院人次', 910866),
	('雙北', '住院健檢人次', 18892),
	('雙北', '手術人次', 698447),
	('雙北', '門診人次', 35554994),
	('雙北', '急診人次', 1856398),
	('雙北', '門診體檢人次', 1191544),
	('雙北', '接生人次', 19838),
	('雙北', '剖腹產人次', 6671),
	('雙北', '洗腎人次', 1411795);
-- 步驟 7：新增 query_charts 設定 - 臺北市
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
		'hospital_service_volume',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'臺北市醫院服務量統計',
		'顯示臺北市各類醫院服務量統計，包含出院人次、手術人次、門診人次、急診人次、體檢人次、接生人次、洗腎人次等醫療服務的使用情況。',
		'可用於了解臺北市醫療服務使用狀況，支援醫療資源配置、服務品質提升及醫療政策制定。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT service_type AS x_axis,
			service_count AS data
		FROM public.hospital_service_volume
		WHERE city = '臺北市'
		ORDER BY service_count DESC;
$$,
NULL,
'taipei'
);
-- 步驟 8：新增 query_charts 設定 - 雙北
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
		'hospital_service_volume',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'雙北醫院服務量統計',
		'顯示雙北地區（臺北市與新北市）各類醫院服務量統計比較，包含出院人次、手術人次、門診人次、急診人次、體檢人次、接生人次、洗腎人次等醫療服務的使用情況。',
		'可用於了解雙北地區醫療服務使用狀況差異，支援區域醫療資源配置、服務品質提升及醫療政策制定。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT service_type AS x_axis,
			service_count AS data
		FROM public.hospital_service_volume
		WHERE city = '雙北'
		ORDER BY service_count DESC;
$$,
NULL,
'metrotaipei'
);
-- 步驟 9：建立索引以提升查詢效能
CREATE INDEX idx_metro_taipei_hospital_service_city ON public.metro_taipei_hospital_service_volume(city);
CREATE INDEX idx_metro_taipei_hospital_service_type ON public.metro_taipei_hospital_service_volume(service_type);
-- 步驟 10：將組件加入到相關的 dashboard 中
-- 注意：實際執行時需要確認 dashboard_id 和調整 order_index
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 302, 13); -- 臺北市醫院服務量統計
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (2, 227, 14); -- 雙北醫院服務量統計
-- 備註：
-- 1. component_id 使用 302 和 227，請確保不與現有組件衝突
-- 2. 臺北市使用 two_d 查詢類型，顯示單一城市的各項服務量
-- 3. 雙北使用 three_d 查詢類型，比較兩個城市的各項服務量
-- 4. 數據來源為原始 85.sql 中的真實數據
-- 5. 臺北市組件屬於 'taipei' 城市，雙北組件屬於 'metrotaipei' 城市
-- 6. 使用 ColumnChart 作為主要圖表類型，適合比較不同服務類型的數量
-- 7. 單位設定為 '人次'，符合醫療服務量的計量單位
-- 8. 顏色配置支援多種服務類型的視覺區分