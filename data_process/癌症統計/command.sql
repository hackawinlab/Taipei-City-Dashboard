-- 步驟 1：新增元件
INSERT INTO public.components (id, index, name)
VALUES (222, 'cancer_statistics', '雙北癌症統計');
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'cancer_statistics',
		'{#4B96FA,#E15F99}',
		'{PopulationPyramid,ColumnChart,BarChart}',
		'人'
	);
-- 步驟 3：新增台北癌症統計資料表
CREATE TABLE public.cancer_statistics_taipei (
	diagnosis_year TEXT,
	gender TEXT,
	city TEXT,
	cancer_type TEXT,
	age_standardized_incidence_rate DECIMAL(10, 2),
	cancer_cases INTEGER,
	average_age DECIMAL(5, 2),
	median_age DECIMAL(5, 1),
	crude_rate DECIMAL(10, 2)
);
-- 步驟 4：新增新北癌症統計資料表
CREATE TABLE public.cancer_statistics_newtaipei (
	diagnosis_year TEXT,
	gender TEXT,
	city TEXT,
	cancer_type TEXT,
	age_standardized_incidence_rate DECIMAL(10, 2),
	cancer_cases INTEGER,
	average_age DECIMAL(5, 2),
	median_age DECIMAL(5, 1),
	crude_rate DECIMAL(10, 2)
);
-- 步驟 5：新增台北資料 (從 processed_cancer_data.csv 匯入)
-- 注意：這裡需要使用 COPY 命令或批量 INSERT 來匯入 CSV 資料
-- 範例 COPY 命令：
COPY public.cancer_statistics_taipei
FROM '/path/to/processed_cancer_data.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');
或者使用
INSERT 語句 （ 這裡只顯示結構 ， 實際資料需要從 CSV 匯入 ）
INSERT INTO public.cancer_statistics_taipei (
		diagnosis_year,
		gender,
		city,
		cancer_type,
		age_standardized_incidence_rate,
		cancer_cases,
		average_age,
		median_age,
		crude_rate
	)
VALUES (
		'1979年',
		'男',
		'台北市',
		'口腔、口咽及下咽',
		4.34,
		42,
		51.31,
		55.0,
		3.68
	),
...(其他資料) -- 步驟 6：新增 query_charts 設定
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
		'cancer_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'雙北市癌症統計資料',
		'顯示台北市與新北市歷年癌症發生率統計，包含不同性別、癌症類型的發生數據，數據來源為衛福部癌症登記資料庫。',
		'可用於了解雙北地區癌症發生趨勢，支援公共衛生政策制定與癌症防治規劃。',
		'{https://www.hpa.gov.tw/Pages/List.aspx?nodeid=119}',
		'{doit}',
		'2025-05-31 05:19:25',
		'2025-05-31 05:19:25',
		'three_d',
		$$
		SELECT cancer_type AS x_axis,
			diagnosis_year AS y_axis,
			cancer_cases AS data
		FROM public.cancer_statistics_taipei
		ORDER BY x_axis,
			y_axis;
$$,
NULL,
'taipei'
);
-- 步驟 7：新增新北市的 query_charts 設定
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
		'cancer_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'雙北市癌症統計資料',
		'顯示台北市與新北市歷年癌症發生率統計，包含不同性別、癌症類型的發生數據，數據來源為衛福部癌症登記資料庫。',
		'可用於了解雙北地區癌症發生趨勢，支援公共衛生政策制定與癌症防治規劃。',
		'{https://www.hpa.gov.tw/Pages/List.aspx?nodeid=119}',
		'{doit}',
		'2025-05-31 05:19:25',
		'2025-05-31 05:19:25',
		'three_d',
		$$
		SELECT cancer_type AS x_axis,
			diagnosis_year AS y_axis,
			cancer_cases AS data
		FROM public.cancer_statistics_taipei
		UNION ALL
		SELECT cancer_type AS x_axis,
			diagnosis_year AS y_axis,
			cancer_cases AS data
		FROM public.cancer_statistics_newtaipei
		ORDER BY x_axis,
			y_axis;
$$,
NULL,
'metrotaipei'
);
-- 步驟 8：資料匯入指令（需要在伺服器上執行）
-- 將處理後的 CSV 資料匯入到對應的資料表中
-- 
-- 台北市資料：
-- COPY public.cancer_statistics_taipei 
-- FROM '/path/to/processed_cancer_data.csv' 
-- WITH (FORMAT csv, HEADER true, DELIMITER ',')
-- WHERE city = '台北市';
--
-- 新北市資料：
-- COPY public.cancer_statistics_newtaipei 
-- FROM '/path/to/processed_cancer_data.csv' 
-- WITH (FORMAT csv, HEADER true, DELIMITER ',')
-- WHERE city = '新北市';
-- 步驟 9：建立索引以提升查詢效能
CREATE INDEX idx_cancer_taipei_year_gender ON public.cancer_statistics_taipei(diagnosis_year, gender);
CREATE INDEX idx_cancer_taipei_cancer_type ON public.cancer_statistics_taipei(cancer_type);
CREATE INDEX idx_cancer_newtaipei_year_gender ON public.cancer_statistics_newtaipei(diagnosis_year, gender);
CREATE INDEX idx_cancer_newtaipei_cancer_type ON public.cancer_statistics_newtaipei(cancer_type);
-- 步驟 10：最後記得將組件加入到相關的 dashboard 中
-- 例如：
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 222, 10); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 記得調整 component_id (222) 確保不與現有組件衝突
-- 2. 確認 CSV 資料路徑正確
-- 3. 根據實際需求調整查詢語句
-- 4. 可以根據需要添加更多圖表類型的查詢語句