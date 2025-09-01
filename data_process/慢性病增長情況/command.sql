-- 步驟 1：新增元件
INSERT INTO public.components (id, index, name)
VALUES (
		224,
		'chronic_disease_growth_statistics',
		'台北市慢性病增長情況統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'chronic_disease_growth_statistics',
		'{#4B96FA,#E15F99,#DDFF00FF,#08FF4AFF}',
		'{ColumnChart,BarChart}',
		'人'
	);
-- 步驟 3：新增台北市慢性病增長情況資料表
CREATE TABLE public.chronic_disease_growth_taipei (
	year_minguo TEXT,
	life_expectancy_65_total DECIMAL(5, 2),
	life_expectancy_80_total DECIMAL(5, 2),
	deaths_65_cancer_total INTEGER,
	deaths_65_heart_disease_total INTEGER,
	deaths_65_cerebrovascular_disease_total INTEGER,
	deaths_65_accidents_total INTEGER
);
-- 步驟 4：新增台北市資料 (從 a15003001-2149041757_cleaned.csv 匯入)
INSERT INTO public.chronic_disease_growth_taipei (
		year_minguo,
		life_expectancy_65_total,
		life_expectancy_80_total,
		deaths_65_cancer_total,
		deaths_65_heart_disease_total,
		deaths_65_cerebrovascular_disease_total,
		deaths_65_accidents_total
	)
VALUES ('99', 21.32, 10.87, 1173, 1359, 878, 154),
	('100', 21.47, 10.94, 1211, 1550, 955, 206),
	('101', 21.40, 10.78, 1286, 1623, 1019, 234),
	('102', 21.61, 10.87, 1277, 1649, 1007, 233),
	('103', 21.80, 10.93, 1333, 1998, 992, 248),
	('104', 22.09, 11.11, 1396, 1934, 965, 241),
	('105', 22.01, 10.99, 1510, 2096, 1022, 256),
	('106', 22.15, 11.02, 1537, 2251, 996, 218),
	('107', 22.16, 10.97, 1566, 2537, 967, 269),
	('108', 22.36, 11.06, 1607, 2333, 955, 208),
	('109', 22.58, 11.22, 1628, 2313, 854, 215);
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
		'chronic_disease_growth_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'台北市慢性病增長情況統計',
		'顯示台北市歷年65歲以上人口主要死因統計，包含癌症、心臟疾病、腦血管疾病及事故傷害等死亡人數變化趨勢。',
		'可用於了解台北市高齡人口健康趨勢，支援公共衛生政策制定與慢性病防治規劃，評估醫療資源配置需求。',
		'{https://www.mohw.gov.tw/cp-16-88717-1.html}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'three_d',
		$$
		SELECT year_minguo AS x_axis,
			CASE
				WHEN disease_type = 'deaths_65_cancer_total' THEN '癌症'
				WHEN disease_type = 'deaths_65_heart_disease_total' THEN '心臟疾病'
				WHEN disease_type = 'deaths_65_cerebrovascular_disease_total' THEN '腦血管疾病'
				WHEN disease_type = 'deaths_65_accidents_total' THEN '事故傷害'
			END AS y_axis,
			'' AS icon,
			death_count AS data
		FROM (
				SELECT year_minguo,
					'deaths_65_cancer_total' AS disease_type,
					deaths_65_cancer_total AS death_count
				FROM public.chronic_disease_growth_taipei
				UNION ALL
				SELECT year_minguo,
					'deaths_65_heart_disease_total' AS disease_type,
					deaths_65_heart_disease_total AS death_count
				FROM public.chronic_disease_growth_taipei
				UNION ALL
				SELECT year_minguo,
					'deaths_65_cerebrovascular_disease_total' AS disease_type,
					deaths_65_cerebrovascular_disease_total AS death_count
				FROM public.chronic_disease_growth_taipei
				UNION ALL
				SELECT year_minguo,
					'deaths_65_accidents_total' AS disease_type,
					deaths_65_accidents_total AS death_count
				FROM public.chronic_disease_growth_taipei
			) AS disease_data
		WHERE year_minguo >= '105'
		ORDER BY year_minguo,
			CASE
				disease_type
				WHEN 'deaths_65_cancer_total' THEN 1
				WHEN 'deaths_65_heart_disease_total' THEN 2
				WHEN 'deaths_65_cerebrovascular_disease_total' THEN 3
				WHEN 'deaths_65_accidents_total' THEN 4
			END;
$$,
NULL,
'taipei'
);
-- 步驟 6：建立索引以提升查詢效能
CREATE INDEX idx_chronic_disease_growth_year ON public.chronic_disease_growth_taipei(year_minguo);
-- 步驟 7：最後記得將組件加入到相關的 dashboard 中
-- 例如：
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 224, 11); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 記得調整 component_id (224) 確保不與現有組件衝突
-- 2. 查詢語句會產生類似你要求的格式，年份作為 x_axis (categories)，死因作為 y_axis (name)
-- 3. 可以根據需要調整年份範圍 (目前設定為105年以後)
-- 4. 圖表類型設定為 ColumnChart 和 BarChart
-- 5. 移除了平均餘命相關的查詢，專注於死亡人數統計