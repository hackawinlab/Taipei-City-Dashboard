-- 步驟 1：新增元件
INSERT INTO public.components (id, index, name)
VALUES (
		223,
		'breast_screening_age_statistics',
		'台北市乳房檢查年齡統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'breast_screening_age_statistics',
		'{#4B96FA,#E15F99,#DDFF00FF,#08FF4AFF}',
		'{ColumnChart,BarChart}',
		'人'
	);
-- 步驟 3：新增台北市乳房檢查統計資料表
CREATE TABLE public.breast_screening_taipei (
	year_minguo TEXT,
	total_screening INTEGER,
	age_under_30 INTEGER,
	age_31_40 INTEGER,
	age_41_50 INTEGER,
	age_51_65 INTEGER,
	age_over_65 INTEGER,
	taipei_city_screening INTEGER
);
-- 步驟 4：新增台北市資料 (從 taipei_breast_screening_data.csv 匯入)
INSERT INTO public.breast_screening_taipei (
		year_minguo,
		total_screening,
		age_under_30,
		age_31_40,
		age_41_50,
		age_51_65,
		age_over_65,
		taipei_city_screening
	)
VALUES (
		'101',
		171713,
		1600,
		16788,
		59788,
		73622,
		19915,
		54009
	),
	(
		'102',
		177564,
		1478,
		17159,
		60430,
		76850,
		21647,
		56198
	),
	(
		'103',
		183098,
		1458,
		16668,
		59153,
		82260,
		23559,
		57415
	),
	(
		'104',
		188047,
		1491,
		16923,
		58620,
		84800,
		26213,
		58823
	),
	(
		'105',
		192088,
		1492,
		16827,
		57684,
		87738,
		28347,
		61617
	),
	(
		'106',
		210356,
		1688,
		17631,
		63143,
		94777,
		33117,
		67786
	),
	(
		'107',
		217494,
		1624,
		17235,
		63715,
		98045,
		36875,
		69968
	),
	(
		'108',
		223244,
		1538,
		16416,
		64128,
		100697,
		40465,
		71910
	),
	(
		'109',
		226730,
		1644,
		16183,
		64748,
		101392,
		42763,
		73243
	),
	(
		'110',
		223530,
		1569,
		15367,
		63533,
		99046,
		44015,
		70924
	),
	(
		'111',
		224584,
		1593,
		15439,
		63897,
		99489,
		44166,
		71048
	),
	(
		'112',
		277172,
		1749,
		17844,
		79411,
		119934,
		58234,
		89663
	);
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
		'breast_screening_age_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'台北市乳房檢查年齡統計',
		'顯示台北市歷年乳房檢查人數按年齡分組統計，包含30歲以下、31-40歲、41-50歲、51-65歲、65歲以上等年齡層的檢查數據。',
		'可用於了解台北市不同年齡層女性乳房檢查趨勢，支援公共衛生政策制定與癌症防治規劃。',
		'{https://www.hpa.gov.tw/Pages/List.aspx?nodeid=119}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'three_d',
		$$
		SELECT year_minguo AS x_axis,
			CASE
				WHEN age_group = 'age_under_30' THEN '30歲以下'
				WHEN age_group = 'age_31_40' THEN '31-40歲'
				WHEN age_group = 'age_41_50' THEN '41-50歲'
				WHEN age_group = 'age_51_65' THEN '51-65歲'
				WHEN age_group = 'age_over_65' THEN '65歲以上'
			END AS y_axis,
			'' AS icon,
			screening_count AS data
		FROM (
				SELECT year_minguo,
					'age_under_30' AS age_group,
					age_under_30 AS screening_count
				FROM public.breast_screening_taipei
				UNION ALL
				SELECT year_minguo,
					'age_31_40' AS age_group,
					age_31_40 AS screening_count
				FROM public.breast_screening_taipei
				UNION ALL
				SELECT year_minguo,
					'age_41_50' AS age_group,
					age_41_50 AS screening_count
				FROM public.breast_screening_taipei
				UNION ALL
				SELECT year_minguo,
					'age_51_65' AS age_group,
					age_51_65 AS screening_count
				FROM public.breast_screening_taipei
				UNION ALL
				SELECT year_minguo,
					'age_over_65' AS age_group,
					age_over_65 AS screening_count
				FROM public.breast_screening_taipei
			) AS age_data
		WHERE year_minguo >= '108'
		ORDER BY year_minguo,
			CASE
				age_group
				WHEN 'age_under_30' THEN 1
				WHEN 'age_31_40' THEN 2
				WHEN 'age_41_50' THEN 3
				WHEN 'age_51_65' THEN 4
				WHEN 'age_over_65' THEN 5
			END;
$$,
NULL,
'taipei'
);
-- 步驟 6：建立索引以提升查詢效能
CREATE INDEX idx_breast_screening_year ON public.breast_screening_taipei(year_minguo);
-- 步驟 7：最後記得將組件加入到相關的 dashboard 中
-- 例如：
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 223, 11); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 記得調整 component_id (223) 確保不與現有組件衝突
-- 2. 查詢語句會產生類似你要求的格式，年份作為 x_axis，年齡組作為 y_axis
-- 3. 可以根據需要調整年份範圍 (目前設定為108年以後)
-- 4. 圖表類型設定為 ColumnChart 和 BarChart