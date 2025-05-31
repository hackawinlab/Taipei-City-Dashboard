-- 步驟 1：新增元件
INSERT INTO public.components (id, index, name)
VALUES (
		225,
		'causes_of_death_statistics',
		'死亡原因統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'causes_of_death_statistics',
		'{#FF6B6B,#4ECDC4,#45B7D1,#96CEB4,#FFEAA7}',
		'{ColumnChart,BarChart}',
		'人'
	);
-- 步驟 3：新增台北市死亡原因統計資料表
CREATE TABLE public.causes_of_death_taipei (
	year INTEGER,
	female_breast_cancer INTEGER,
	all_cancer_deaths INTEGER,
	lung_cancer INTEGER,
	liver_cancer INTEGER,
	stomach_cancer INTEGER
);
-- 步驟 4：新增新北市死亡原因統計資料表
CREATE TABLE public.causes_of_death_new_taipei (
	year INTEGER,
	cancer INTEGER,
	heart_disease INTEGER,
	cerebrovascular_disease INTEGER,
	diabetes INTEGER
);
-- 步驟 5：新增台北市資料
INSERT INTO public.causes_of_death_taipei (
		year,
		female_breast_cancer,
		all_cancer_deaths,
		lung_cancer,
		liver_cancer,
		stomach_cancer
	)
VALUES (2019, 378, 5326, 1040, 661, 295),
	(2020, 354, 5146, 1026, 646, 277),
	(2021, 365, 5316, 995, 642, 256),
	(2022, 394, 5246, 990, 601, 277),
	(2023, 352, 5325, 1073, 617, 277);
-- 步驟 6：新增新北市資料
INSERT INTO public.causes_of_death_new_taipei (
		year,
		cancer,
		heart_disease,
		cerebrovascular_disease,
		diabetes
	)
VALUES (2019, 12775, 3533, 1497, 1215),
	(2020, 12493, 3743, 1505, 1332),
	(2021, 13146, 3822, 1614, 1652),
	(2022, 13254, 4291, 1633, 1731),
	(2023, 13521, 4036, 1728, 1562);
-- 步驟 7：新增台北市 query_charts 設定
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
		'causes_of_death_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'台北市死亡原因統計',
		'顯示台北市歷年主要死亡原因統計，包含女性乳房癌、所有癌症死亡原因、氣管支氣管和肺癌、肝和肝內膽管癌、胃癌等死亡數據。',
		'可用於了解台北市主要死亡原因趨勢，支援公共衛生政策制定與疾病防治規劃。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'three_d',
		$$
		SELECT CAST(year AS TEXT) AS x_axis,
			CASE
				WHEN cause_type = 'female_breast_cancer' THEN '女性乳房癌'
				WHEN cause_type = 'all_cancer_deaths' THEN '所有癌症死亡原因'
				WHEN cause_type = 'lung_cancer' THEN '氣管、支氣管和肺癌'
				WHEN cause_type = 'liver_cancer' THEN '肝和肝內膽管癌'
				WHEN cause_type = 'stomach_cancer' THEN '胃癌'
			END AS y_axis,
			'' AS icon,
			death_count AS data
		FROM (
				SELECT year,
					'female_breast_cancer' AS cause_type,
					female_breast_cancer AS death_count
				FROM public.causes_of_death_taipei
				UNION ALL
				SELECT year,
					'all_cancer_deaths' AS cause_type,
					all_cancer_deaths AS death_count
				FROM public.causes_of_death_taipei
				UNION ALL
				SELECT year,
					'lung_cancer' AS cause_type,
					lung_cancer AS death_count
				FROM public.causes_of_death_taipei
				UNION ALL
				SELECT year,
					'liver_cancer' AS cause_type,
					liver_cancer AS death_count
				FROM public.causes_of_death_taipei
				UNION ALL
				SELECT year,
					'stomach_cancer' AS cause_type,
					stomach_cancer AS death_count
				FROM public.causes_of_death_taipei
			) AS death_data
		WHERE year >= 2019
		ORDER BY year,
			CASE
				cause_type
				WHEN 'female_breast_cancer' THEN 1
				WHEN 'all_cancer_deaths' THEN 2
				WHEN 'lung_cancer' THEN 3
				WHEN 'liver_cancer' THEN 4
				WHEN 'stomach_cancer' THEN 5
			END;
$$,
NULL,
'taipei'
);
-- 步驟 8：新增新北市 query_charts 設定
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
		'causes_of_death_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'新北市死亡原因統計',
		'顯示新北市歷年主要死亡原因統計，包含癌症、心臟疾病、腦血管疾病、糖尿病等死亡數據。',
		'可用於了解新北市主要死亡原因趨勢，支援公共衛生政策制定與疾病防治規劃。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'three_d',
		$$
		SELECT CAST(year AS TEXT) AS x_axis,
			CASE
				WHEN cause_type = 'cancer' THEN '癌症'
				WHEN cause_type = 'heart_disease' THEN '心臟疾病'
				WHEN cause_type = 'cerebrovascular_disease' THEN '腦血管疾病'
				WHEN cause_type = 'diabetes' THEN '糖尿病'
			END AS y_axis,
			'' AS icon,
			death_count AS data
		FROM (
				SELECT year,
					'cancer' AS cause_type,
					cancer AS death_count
				FROM public.causes_of_death_new_taipei
				UNION ALL
				SELECT year,
					'heart_disease' AS cause_type,
					heart_disease AS death_count
				FROM public.causes_of_death_new_taipei
				UNION ALL
				SELECT year,
					'cerebrovascular_disease' AS cause_type,
					cerebrovascular_disease AS death_count
				FROM public.causes_of_death_new_taipei
				UNION ALL
				SELECT year,
					'diabetes' AS cause_type,
					diabetes AS death_count
				FROM public.causes_of_death_new_taipei
			) AS death_data
		WHERE year >= 2019
		ORDER BY year,
			CASE
				cause_type
				WHEN 'cancer' THEN 1
				WHEN 'heart_disease' THEN 2
				WHEN 'cerebrovascular_disease' THEN 3
				WHEN 'diabetes' THEN 4
			END;
$$,
NULL,
'metrotaipei'
);
-- 步驟 9：建立索引以提升查詢效能
CREATE INDEX idx_causes_of_death_taipei_year ON public.causes_of_death_taipei(year);
CREATE INDEX idx_causes_of_death_new_taipei_year ON public.causes_of_death_new_taipei(year);
-- 步驟 10：最後記得將組件加入到相關的 dashboard 中
-- 例如：
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 224, 12); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 記得調整 component_id (224) 確保不與現有組件衝突
-- 2. 台北市資料包含：女性乳房癌、所有癌症死亡原因、氣管支氣管和肺癌、肝和肝內膽管癌、胃癌
-- 3. 新北市資料包含：癌症、心臟疾病、腦血管疾病、糖尿病
-- 4. 查詢語句會產生年份作為 x_axis，死亡原因作為 y_axis
-- 5. 圖表類型設定為 ColumnChart 和 BarChart
-- 6. 台北市使用 city='taipei'，新北市使用 city='metrotaipei'