-- 醫院人次統計完整設定檔
-- 參考 85_complete.sql 結構，為醫院人次數據建立完整的組件配置
-- 步驟 1：新增元件 - 醫院人次統計
INSERT INTO public.components (id, index, name)
VALUES (
		307,
		'hospital_admission_stats',
		'醫院人次統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'hospital_admission_stats',
		'{#FF6B6B,#4ECDC4,#45B7D1,#96CEB4,#FFEAA7,#DDA0DD,#98FB98,#F0E68C,#FFB6C1,#87CEEB,#D2691E,#FF7F50,#6495ED}',
		'{BarChart}',
		'人次'
	);
-- 步驟 3：新增醫院人次統計資料表
CREATE TABLE public.hospital_admission_stats (
	city TEXT,
	bed_type TEXT,
	admission_count INT
);
-- 步驟 4：新增醫院人次統計資料（臺北市+新北市+雙北）
INSERT INTO public.hospital_admission_stats (city, bed_type, admission_count)
VALUES -- 臺北市資料
	('臺北市', '合計', 563144),
	('臺北市', '急性病床', 553862),
	('臺北市', '慢性病床', 688),
	('臺北市', '加護病床', 38760),
	('臺北市', '燒傷病床', 867),
	('臺北市', '燒傷加護病床', 736),
	('臺北市', '嬰兒病床', 7234),
	('臺北市', '嬰兒床', 9583),
	('臺北市', '安寧病床', 2207),
	('臺北市', '慢性呼吸照護病床', 397),
	('臺北市', '亞急性呼吸照護病床', 945),
	('臺北市', '精神科加護病床', 89),
	('臺北市', '普通隔離病床', 5590),
	('臺北市', '正壓隔離病床', 1648),
	('臺北市', '負壓隔離病床', 4489),
	('臺北市', '骨髓移植病床', 392),
	('臺北市', '司法精神病床', 1349),
	-- 新北市資料
	('新北市', '合計', 295259),
	('新北市', '急性病床', 283048),
	('新北市', '慢性病床', 6870),
	('新北市', '加護病床', 30060),
	('新北市', '燒傷病床', 676),
	('新北市', '嬰兒病床', 4102),
	('新北市', '嬰兒床', 6295),
	('新北市', '安寧病床', 2428),
	('新北市', '慢性呼吸照護病床', 621),
	('新北市', '亞急性呼吸照護病床', 1154),
	('新北市', '普通隔離病床', 1542),
	('新北市', '負壓隔離病床', 2195),
	('新北市', '骨髓移植病床', 74),
	('新北市', '急性後期照護病床', 80),
	('新北市', '整合醫學急診後送病床', 1667),
	('新北市', '司法精神病床', 860),
	-- 雙北合計資料
	('雙北', '合計', 858403),
	('雙北', '急性病床', 836910),
	('雙北', '慢性病床', 7558),
	('雙北', '加護病床', 68820),
	('雙北', '燒傷病床', 1543),
	('雙北', '燒傷加護病床', 736),
	('雙北', '嬰兒病床', 11336),
	('雙北', '嬰兒床', 15878),
	('雙北', '安寧病床', 4635),
	('雙北', '慢性呼吸照護病床', 1018),
	('雙北', '亞急性呼吸照護病床', 2099),
	('雙北', '精神科加護病床', 89),
	('雙北', '普通隔離病床', 7132),
	('雙北', '正壓隔離病床', 1648),
	('雙北', '負壓隔離病床', 6684),
	('雙北', '骨髓移植病床', 466),
	('雙北', '急性後期照護病床', 80),
	('雙北', '整合醫學急診後送病床', 1667),
	('雙北', '司法精神病床', 2209);
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
		'hospital_admission_stats',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'臺北市醫院人次統計',
		'顯示臺北市各類病床的住院人次統計，包含急性病床、慢性病床、加護病床、特殊病床等不同類型病床的使用人次情況。',
		'可用於了解臺北市醫療服務需求量，支援醫療資源配置、服務容量規劃及醫療政策制定。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT bed_type AS x_axis,
			admission_count AS data
		FROM public.hospital_admission_stats
		WHERE city = '臺北市'
		ORDER BY admission_count DESC;
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
		'hospital_admission_stats',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'雙北醫院人次統計',
		'顯示雙北地區（臺北市與新北市）各類病床的住院人次統計，包含急性病床、慢性病床、加護病床、特殊病床等不同類型病床的使用人次情況。',
		'可用於了解雙北地區醫療服務需求量，支援區域醫療資源配置、服務容量規劃及醫療政策制定。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT bed_type AS x_axis,
			admission_count AS data
		FROM public.hospital_admission_stats
		WHERE city = '雙北'
		ORDER BY admission_count DESC;
$$,
NULL,
'metrotaipei'
);
-- 步驟 7：建立索引以提升查詢效能
CREATE INDEX idx_hospital_admission_city ON public.hospital_admission_stats(city);
CREATE INDEX idx_hospital_admission_bed_type ON public.hospital_admission_stats(bed_type);
-- 步驟 8：將組件加入到相關的 dashboard 中
-- 注意：實際執行時需要確認 dashboard_id 和調整 order_index
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 307, 15); -- 臺北市醫院人次統計
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (2, 307, 16); -- 雙北醫院人次統計
-- 備註：
-- 1. component_id 使用 307，請確保不與現有組件衝突
-- 2. 臺北市和雙北都使用 two_d 查詢類型，按住院人次降序排列
-- 3. 數據來源為原始 76.sql 中的真實數據
-- 4. 臺北市組件屬於 'taipei' 城市，雙北組件屬於 'metrotaipei' 城市
-- 5. 使用 ColumnChart 作為主要圖表類型，適合比較不同病床類型的住院人次
-- 6. 單位設定為 '人次'，符合住院人次的計量單位
-- 7. 雙北數據為臺北市和新北市的合計值
-- 8. 按住院人次降序排列，讓使用量最高的病床類型優先顯示
-- 9. 支援 DonutChart 顯示各病床類型住院人次的比例分布
-- 10. 急性病床佔絕大多數住院人次，其他特殊病床相對較少