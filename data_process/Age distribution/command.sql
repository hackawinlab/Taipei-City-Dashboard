-- 步驟 1：新增元件
INSERT INTO public.components (id, index, name)
VALUES (230, 'age_distribution', '雙北年齡分布');
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'age_distribution',
		'{#E15F99,#2E91E5}',
		'{PopulationPyramid}',
		'人'
	);
-- 步驟 2.1：新增台北資料表
CREATE TABLE public.age_distribution_taipei (
	age_group TEXT,
	male_count INTEGER,
	female_count INTEGER
);
-- 步驟 2.2：新增新北資料表
CREATE TABLE public.age_distribution_newtaipei (
	age_group TEXT,
	male_count INTEGER,
	female_count INTEGER
);
-- 步驟 3：新增台北資料
INSERT INTO public.age_distribution_taipei (age_group, male_count, female_count)
VALUES ('0~9歲', 95472, 89810),
	('10~19歲', 111625, 104073),
	('20~29歲', 122866, 118001),
	('30~39歲', 149336, 162384),
	('40~49歲', 189229, 217634),
	('50~59歲', 167828, 196676),
	('60~69歲', 168875, 203669),
	('70~79歲', 117812, 146479),
	('80~89歲', 40373, 61693),
	('90~99歲', 9446, 14266),
	('100歲以上', 512, 621);
-- 步驟 4：新增新北資料
INSERT INTO public.age_distribution_newtaipei (age_group, male_count, female_count)
VALUES ('0~9歲', 237445, 223257),
	('10~19歲', 287126, 266672),
	('20~29歲', 361857, 338714),
	('30~39歲', 434766, 434716),
	('40~49歲', 532789, 577846),
	('50~59歲', 462504, 526694),
	('60~69歲', 442928, 531251),
	('70~79歲', 275370, 341466),
	('80~89歲', 84978, 128525),
	('90~99歲', 17687, 26543),
	('100歲以上', 991, 1119);
-- 步驟 5.1：新增台北市 query_charts 設定
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
		'age_distribution',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		0,
		NULL,
		'臺北市政府主計處',
		'臺北市年齡分布人口金字塔',
		'以人口金字塔圖表呈現臺北市各年齡層男女人口分布，反映人口結構特徵與老化趨勢。',
		'可用於分析人口結構、性別比例、老化程度等人口統計特徵，支援社會政策規劃與資源配置。',
		'{https://www.dbas.taipei.gov.tw/}',
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
				FROM public.age_distribution_taipei
				UNION ALL
				SELECT age_group AS x_axis,
					'女性' AS y_axis,
					female_count AS data
				FROM public.age_distribution_taipei
			) AS combined_data
		ORDER BY CASE
				x_axis
				WHEN '0~9歲' THEN 11
				WHEN '10~19歲' THEN 10
				WHEN '20~29歲' THEN 9
				WHEN '30~39歲' THEN 8
				WHEN '40~49歲' THEN 7
				WHEN '50~59歲' THEN 6
				WHEN '60~69歲' THEN 5
				WHEN '70~79歲' THEN 4
				WHEN '80~89歲' THEN 3
				WHEN '90~99歲' THEN 2
				WHEN '100歲以上' THEN 1
			END,
			y_axis;
$$,
NULL,
'taipei'
);
-- 步驟 5.2：新增新北市 query_charts 設定
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
		'age_distribution',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		0,
		NULL,
		'新北市政府主計處',
		'新北市年齡分布人口金字塔',
		'以人口金字塔圖表呈現新北市各年齡層男女人口分布，反映人口結構特徵與老化趨勢。',
		'可用於分析人口結構、性別比例、老化程度等人口統計特徵，支援社會政策規劃與資源配置。',
		'{https://www.ntpc.gov.tw/}',
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
				FROM public.age_distribution_newtaipei
				UNION ALL
				SELECT age_group AS x_axis,
					'女性' AS y_axis,
					female_count AS data
				FROM public.age_distribution_newtaipei
			) AS combined_data
		ORDER BY CASE
				x_axis
				WHEN '0~9歲' THEN 11
				WHEN '10~19歲' THEN 10
				WHEN '20~29歲' THEN 9
				WHEN '30~39歲' THEN 8
				WHEN '40~49歲' THEN 7
				WHEN '50~59歲' THEN 6
				WHEN '60~69歲' THEN 5
				WHEN '70~79歲' THEN 4
				WHEN '80~89歲' THEN 3
				WHEN '90~99歲' THEN 2
				WHEN '100歲以上' THEN 1
			END,
			y_axis;
$$,
NULL,
'metrotaipei'
);
-- 最後記得加到 dashboard 裡面