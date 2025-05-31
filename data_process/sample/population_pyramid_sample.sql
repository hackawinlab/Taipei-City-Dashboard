-- PopulationPyramid 圖表測試資料
-- 此檔案提供測試用的人口金字塔資料，用於驗證 PopulationPyramid.vue 組件功能
-- 步驟 1：新增測試元件
INSERT INTO public.components (id, index, name)
VALUES (999, 'population_pyramid_sample', '人口金字塔測試圖表');
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'population_pyramid_sample',
		'{#E15F99,#2E91E5}',
		'{PopulationPyramid}',
		'人'
	);
-- 步驟 3：建立測試資料表
CREATE TABLE public.population_pyramid_sample_data (
	age_group TEXT,
	male_count INTEGER,
	female_count INTEGER
);
-- 步驟 4：插入測試資料 (模擬新北市人口分布)
INSERT INTO public.population_pyramid_sample_data (age_group, male_count, female_count)
VALUES ('0~4歲', 45000, 42000),
	('5~9歲', 48000, 45000),
	('10~14歲', 52000, 49000),
	('15~19歲', 55000, 52000),
	('20~24歲', 58000, 55000),
	('25~29歲', 62000, 59000),
	('30~34歲', 68000, 65000),
	('35~39歲', 72000, 75000),
	('40~44歲', 78000, 82000),
	('45~49歲', 85000, 90000),
	('50~54歲', 82000, 88000),
	('55~59歲', 75000, 82000),
	('60~64歲', 68000, 75000),
	('65~69歲', 58000, 68000),
	('70~74歲', 48000, 58000),
	('75~79歲', 38000, 48000),
	('80~84歲', 25000, 35000),
	('85~89歲', 15000, 22000),
	('90~94歲', 6000, 10000),
	('95~99歲', 2000, 4000),
	('100歲以上', 500, 800);
-- 步驟 5：新增 query_charts 設定
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
		'population_pyramid_sample',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		0,
		NULL,
		'測試資料來源',
		'人口金字塔測試圖表',
		'此為測試用人口金字塔圖表，展示新北市各年齡層男女人口分布。資料為模擬數據，用於驗證 PopulationPyramid 組件的顯示效果和互動功能。',
		'用於測試 PopulationPyramid 圖表組件的功能，包括資料顯示、工具提示、篩選功能等。開發者可使用此測試資料驗證圖表的正確性。',
		'{https://example.com/test-data}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'three_d',
		$$
		SELECT x_axis,
			y_axis,
			data
		FROM (
				SELECT age_group AS x_axis,
					'男性' AS y_axis,
					male_count AS data
				FROM public.population_pyramid_sample_data
				UNION ALL
				SELECT age_group AS x_axis,
					'女性' AS y_axis,
					female_count AS data
				FROM public.population_pyramid_sample_data
			) AS combined_data
		ORDER BY CASE
				x_axis
				WHEN '0~4歲' THEN 21
				WHEN '5~9歲' THEN 20
				WHEN '10~14歲' THEN 19
				WHEN '15~19歲' THEN 18
				WHEN '20~24歲' THEN 17
				WHEN '25~29歲' THEN 16
				WHEN '30~34歲' THEN 15
				WHEN '35~39歲' THEN 14
				WHEN '40~44歲' THEN 13
				WHEN '45~49歲' THEN 12
				WHEN '50~54歲' THEN 11
				WHEN '55~59歲' THEN 10
				WHEN '60~64歲' THEN 9
				WHEN '65~69歲' THEN 8
				WHEN '70~74歲' THEN 7
				WHEN '75~79歲' THEN 6
				WHEN '80~84歲' THEN 5
				WHEN '85~89歲' THEN 4
				WHEN '90~94歲' THEN 3
				WHEN '95~99歲' THEN 2
				WHEN '100歲以上' THEN 1
			END,
			y_axis;
$$,
NULL,
'metrotaipei'
);
-- 步驟 6：建立索引以提升查詢效能
CREATE INDEX idx_population_pyramid_sample_age ON public.population_pyramid_sample_data(age_group);
-- 步驟 7：將組件加入到測試 dashboard 中 (可選)
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 999, 99); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 此為測試資料，component_id 使用 999 避免與正式組件衝突
-- 2. 資料模擬真實人口分布特徵：年輕人口較少、中年人口較多、老年人口遞減
-- 3. 女性在高齡組別通常比男性多，符合實際人口統計特徵
-- 4. 查詢結果會產生 PopulationPyramid 組件所需的格式：x_axis(年齡組)、y_axis(性別)、data(人數)
-- 5. 年齡組排序從最年輕到最年長，符合人口金字塔的顯示慣例