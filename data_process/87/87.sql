-- 步驟 1：新增元件 - 臺北市醫療設備統計
INSERT INTO public.components (id, index, name)
VALUES (
		301,
		'taipei_medical_devices_statistics',
		'臺北市醫療設備統計'
	);
-- 步驟 2：新增元件 - 雙北醫療設備統計
INSERT INTO public.components (id, index, name)
VALUES (
		226,
		'metro_taipei_medical_devices_statistics',
		'雙北醫療設備統計'
	);
-- 步驟 3：設定圖表型態 - 臺北市
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'taipei_medical_devices_statistics',
		'{#FF6B6B,#4ECDC4,#45B7D1,#96CEB4,#FFEAA7,#DDA0DD,#98FB98,#F0E68C,#FFB6C1,#87CEEB,#D2691E,#FF7F50,#6495ED}',
		'{ColumnChart,BarChart}',
		'個'
	);
-- 步驟 4：設定圖表型態 - 雙北
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'metro_taipei_medical_devices_statistics',
		'{#FF6B6B,#4ECDC4}',
		'{ColumnChart,BarChart}',
		'個'
	);
-- 步驟 5：新增雙北醫療設備統計資料表
CREATE TABLE public.metro_taipei_medical_devices_stats (
	city TEXT,
	device_type TEXT,
	device_count INT
);
-- 步驟 6：新增雙北醫療設備統計資料（臺北市+新北市）
INSERT INTO public.metro_taipei_medical_devices_stats (city, device_type, device_count)
VALUES -- 臺北市資料
	('臺北市', '電腦斷層掃描儀', 75),
	('臺北市', '核磁共振', 65),
	('臺北市', '高能遠距放射', 40),
	('臺北市', '近接式放射', 9),
	('臺北市', '單光子斷層掃描儀', 40),
	('臺北市', '正子斷層掃描儀', 15),
	('臺北市', '高壓氧設備', 20),
	('臺北市', '磁珠標記自動細胞分選儀', 0),
	('臺北市', '重粒子治療設備', 1),
	('臺北市', '單機型質子機', 1),
	('臺北市', '多治療室質子機', 0),
	('臺北市', '手術台', 403),
	('臺北市', '產台', 45),
	-- 新北市資料
	('新北市', '電腦斷層掃描儀', 44),
	('新北市', '核磁共振', 28),
	('新北市', '高能遠距放射', 22),
	('新北市', '近接式放射', 5),
	('新北市', '單光子斷層掃描儀', 20),
	('新北市', '正子斷層掃描儀', 6),
	('新北市', '高壓氧設備', 10),
	('新北市', '磁珠標記自動細胞分選儀', 0),
	('新北市', '重粒子治療設備', 0),
	('新北市', '單機型質子機', 0),
	('新北市', '多治療室質子機', 0),
	('新北市', '手術台', 235),
	('新北市', '產台', 32);
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
		'medical_devices_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'臺北市醫療設備統計',
		'顯示臺北市各類醫療設備數量統計，包含電腦斷層掃描儀、核磁共振、各類放射設備、手術台、產台等醫療設備的分布情況。',
		'可用於了解臺北市醫療資源分布狀況，支援醫療政策制定、資源配置規劃及醫療品質提升策略。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT device_type AS x_axis,
			device_count AS data
		FROM public.metro_taipei_medical_devices_stats
		WHERE city = '臺北市'
		ORDER BY device_type;
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
		'medical_devices_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'雙北醫療設備統計',
		'顯示雙北地區（臺北市與新北市）各類醫療設備數量統計比較，包含電腦斷層掃描儀、核磁共振、各類放射設備、手術台、產台等醫療設備的分布情況。',
		'可用於了解雙北地區醫療資源分布狀況，支援區域醫療政策制定、資源配置規劃及醫療品質提升策略。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'three_d',
		$$
		SELECT device_type AS x_axis,
			city AS y_axis,
			'' AS icon,
			device_count AS data
		FROM public.metro_taipei_medical_devices_stats;
$$,
NULL,
'metrotaipei'
);
-- 步驟 9：建立索引以提升查詢效能
CREATE INDEX idx_metro_taipei_medical_devices_city ON public.metro_taipei_medical_devices_stats(city);
CREATE INDEX idx_metro_taipei_medical_devices_type ON public.metro_taipei_medical_devices_stats(device_type);
-- 步驟 10：最後記得將組件加入到相關的 dashboard 中
-- 例如：
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 301, 12); -- 臺北市醫療設備統計
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (2, 226, 13); -- 雙北醫療設備統計
-- 備註：
-- 1. 記得調整 component_id (301, 226) 確保不與現有組件衝突
-- 2. 臺北市使用 two_d 查詢類型，從同一個表中篩選臺北市資料
-- 3. 雙北使用 three_d 查詢類型，以醫療設備為categories，城市為series進行比較
-- 4. 所有資料都是基於原始提供的真實數據
-- 5. 臺北市組件屬於 'taipei' 城市，雙北組件屬於 'metrotaipei' 城市
-- 6. 雙北查詢會產生：categories為醫療設備名稱，data為每個設備在新北市和臺北市的數量陣列
-- 7. 使用文字排序而非數字排序，讓橫向長條圖按照設備名稱的字母順序排列