-- 醫院占床率統計完整設定檔
-- 參考 85_complete.sql 結構，為醫院占床率數據建立完整的組件配置
-- 步驟 1：新增元件 - 醫院占床率統計
INSERT INTO public.components (id, index, name)
VALUES (
		306,
		'hospital_occupancy_rate',
		'醫院占床率統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'hospital_occupancy_rate',
		'{#FF6B6B,#4ECDC4,#45B7D1,#96CEB4,#FFEAA7,#DDA0DD,#98FB98,#F0E68C,#FFB6C1,#87CEEB,#D2691E,#FF7F50,#6495ED}',
		'{ColumnChart,BarChart,DonutChart}',
		'%'
	);
-- 步驟 3：新增醫院占床率統計資料表
CREATE TABLE public.hospital_occupancy_rate (
	city TEXT,
	bed_type TEXT,
	occupancy_rate FLOAT
);
-- 步驟 4：新增醫院占床率統計資料（臺北市+新北市+雙北）
INSERT INTO public.hospital_occupancy_rate (city, bed_type, occupancy_rate)
VALUES -- 臺北市資料
	('臺北市', '合計', 70.46),
	('臺北市', '急性病床', 69.72),
	('臺北市', '慢性病床', 77.48),
	('臺北市', '加護病床', 74.30),
	('臺北市', '燒傷病床', 63.36),
	('臺北市', '燒傷加護病床', 59.15),
	('臺北市', '嬰兒病床', 42.79),
	('臺北市', '嬰兒床', 24.65),
	('臺北市', '安寧病床', 60.66),
	('臺北市', '慢性呼吸照護病床', 83.74),
	('臺北市', '亞急性呼吸照護病床', 62.82),
	('臺北市', '精神科加護病床', 90.39),
	('臺北市', '普通隔離病床', 78.75),
	('臺北市', '正壓隔離病床', 79.26),
	('臺北市', '負壓隔離病床', 57.33),
	('臺北市', '骨髓移植病床', 50.05),
	-- 新北市資料
	('新北市', '合計', 71.98),
	('新北市', '急性病床', 69.33),
	('新北市', '慢性病床', 62.29),
	('新北市', '加護病床', 78.64),
	('新北市', '燒傷病床', 60.17),
	('新北市', '嬰兒病床', 46.76),
	('新北市', '嬰兒床', 29.18),
	('新北市', '安寧病床', 58.00),
	('新北市', '慢性呼吸照護病床', 84.92),
	('新北市', '亞急性呼吸照護病床', 81.65),
	('新北市', '普通隔離病床', 79.57),
	('新北市', '負壓隔離病床', 50.46),
	('新北市', '骨髓移植病床', 31.16),
	('新北市', '急性後期照護病床', 45.01),
	('新北市', '整合醫學急診後送病床', 90.75),
	-- 雙北平均資料
	('雙北', '合計', 71.22),
	('雙北', '急性病床', 69.53),
	('雙北', '慢性病床', 69.89),
	('雙北', '加護病床', 76.47),
	('雙北', '燒傷病床', 61.77),
	('雙北', '燒傷加護病床', 59.15),
	('雙北', '嬰兒病床', 44.78),
	('雙北', '嬰兒床', 26.92),
	('雙北', '安寧病床', 59.33),
	('雙北', '慢性呼吸照護病床', 84.33),
	('雙北', '亞急性呼吸照護病床', 72.24),
	('雙北', '精神科加護病床', 90.39),
	('雙北', '普通隔離病床', 79.16),
	('雙北', '正壓隔離病床', 79.26),
	('雙北', '負壓隔離病床', 53.90),
	('雙北', '骨髓移植病床', 40.61);
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
		'hospital_occupancy_rate',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'臺北市醫院占床率統計',
		'顯示臺北市各類病床的占床率統計，包含急性病床、慢性病床、加護病床、特殊病床等不同類型病床的使用率情況。',
		'可用於了解臺北市醫療資源使用效率，支援病床配置優化、醫療服務規劃及醫療政策制定。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT bed_type AS x_axis,
			occupancy_rate AS data
		FROM public.hospital_occupancy_rate
		WHERE city = '臺北市'
		ORDER BY occupancy_rate DESC;
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
		'hospital_occupancy_rate',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'雙北醫院占床率統計',
		'顯示雙北地區（臺北市與新北市）各類病床的占床率統計，包含急性病床、慢性病床、加護病床、特殊病床等不同類型病床的使用率情況。',
		'可用於了解雙北地區醫療資源使用效率，支援區域病床配置優化、醫療服務規劃及醫療政策制定。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT bed_type AS x_axis,
			occupancy_rate AS data
		FROM public.hospital_occupancy_rate
		WHERE city = '雙北'
		ORDER BY occupancy_rate DESC;
$$,
NULL,
'metrotaipei'
);
-- 步驟 7：建立索引以提升查詢效能
CREATE INDEX idx_hospital_occupancy_city ON public.hospital_occupancy_rate(city);
CREATE INDEX idx_hospital_occupancy_bed_type ON public.hospital_occupancy_rate(bed_type);
-- 步驟 8：將組件加入到相關的 dashboard 中
-- 注意：實際執行時需要確認 dashboard_id 和調整 order_index
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 306, 14); -- 臺北市醫院占床率統計
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (2, 306, 15); -- 雙北醫院占床率統計
-- 備註：
-- 1. component_id 使用 306，請確保不與現有組件衝突
-- 2. 臺北市和雙北都使用 two_d 查詢類型，按占床率降序排列
-- 3. 數據來源為原始 82.sql 中的真實數據
-- 4. 臺北市組件屬於 'taipei' 城市，雙北組件屬於 'metrotaipei' 城市
-- 5. 使用 ColumnChart 作為主要圖表類型，適合比較不同病床類型的占床率
-- 6. 單位設定為 '%'，符合占床率的計量單位
-- 7. 雙北數據為臺北市和新北市的平均值（針對有數據的病床類型）
-- 8. 按占床率降序排列，讓使用率最高的病床類型優先顯示
-- 9. 支援 DonutChart 顯示各病床類型占床率的比例分布