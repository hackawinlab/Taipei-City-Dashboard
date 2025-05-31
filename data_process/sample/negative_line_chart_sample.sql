-- NegativeLineChart 圖表測試資料
-- 此檔案提供測試用的負值折線圖資料，用於驗證 NegativeLineChart.vue 組件功能
-- 步驟 1：新增測試元件
INSERT INTO public.components (id, index, name)
VALUES (998, 'negative_line_chart_sample', '負值折線圖測試圖表');
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'negative_line_chart_sample',
		'{#2E91E5,#ff6b6b,#4CAF50}',
		'{NegativeLineChart}',
		'%'
	);
-- 步驟 3：建立測試資料表
CREATE TABLE public.negative_line_chart_sample_data (
	date_time TIMESTAMP WITH TIME ZONE,
	series_name TEXT,
	value DECIMAL(10, 2)
);
-- 步驟 4：插入測試資料 (模擬經濟指標變化，包含正負值)
INSERT INTO public.negative_line_chart_sample_data (date_time, series_name, value)
VALUES -- GDP成長率 (可能為負值)
	('2023-01-01T00:00:00+08:00', 'GDP成長率', 2.5),
	('2023-02-01T00:00:00+08:00', 'GDP成長率', 1.8),
	('2023-03-01T00:00:00+08:00', 'GDP成長率', -0.5),
	('2023-04-01T00:00:00+08:00', 'GDP成長率', -1.2),
	('2023-05-01T00:00:00+08:00', 'GDP成長率', -0.8),
	('2023-06-01T00:00:00+08:00', 'GDP成長率', 0.3),
	('2023-07-01T00:00:00+08:00', 'GDP成長率', 1.1),
	('2023-08-01T00:00:00+08:00', 'GDP成長率', 2.2),
	('2023-09-01T00:00:00+08:00', 'GDP成長率', 2.8),
	('2023-10-01T00:00:00+08:00', 'GDP成長率', 3.1),
	('2023-11-01T00:00:00+08:00', 'GDP成長率', 2.9),
	('2023-12-01T00:00:00+08:00', 'GDP成長率', 3.2),
	-- 通膨率 (可能為負值，即通縮)
	('2023-01-01T00:00:00+08:00', '通膨率', 1.5),
	('2023-02-01T00:00:00+08:00', '通膨率', 0.8),
	('2023-03-01T00:00:00+08:00', '通膨率', -0.2),
	('2023-04-01T00:00:00+08:00', '通膨率', -0.7),
	('2023-05-01T00:00:00+08:00', '通膨率', -0.3),
	('2023-06-01T00:00:00+08:00', '通膨率', 0.1),
	('2023-07-01T00:00:00+08:00', '通膨率', 0.6),
	('2023-08-01T00:00:00+08:00', '通膨率', 1.2),
	('2023-09-01T00:00:00+08:00', '通膨率', 1.8),
	('2023-10-01T00:00:00+08:00', '通膨率', 2.1),
	('2023-11-01T00:00:00+08:00', '通膨率', 1.9),
	('2023-12-01T00:00:00+08:00', '通膨率', 2.3),
	-- 失業率變化 (相對於前期，可能為負值表示改善)
	('2023-01-01T00:00:00+08:00', '失業率變化', 0.2),
	('2023-02-01T00:00:00+08:00', '失業率變化', 0.5),
	('2023-03-01T00:00:00+08:00', '失業率變化', 0.8),
	('2023-04-01T00:00:00+08:00', '失業率變化', 0.3),
	('2023-05-01T00:00:00+08:00', '失業率變化', -0.1),
	('2023-06-01T00:00:00+08:00', '失業率變化', -0.4),
	('2023-07-01T00:00:00+08:00', '失業率變化', -0.6),
	('2023-08-01T00:00:00+08:00', '失業率變化', -0.8),
	('2023-09-01T00:00:00+08:00', '失業率變化', -0.5),
	('2023-10-01T00:00:00+08:00', '失業率變化', -0.3),
	('2023-11-01T00:00:00+08:00', '失業率變化', -0.2),
	('2023-12-01T00:00:00+08:00', '失業率變化', -0.1);
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
		'negative_line_chart_sample',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		0,
		NULL,
		'測試資料來源',
		'負值折線圖測試圖表',
		'此為測試用負值折線圖表，展示經濟指標的時間序列變化，包含正值和負值數據。資料為模擬數據，用於驗證 NegativeLineChart 組件的顯示效果和互動功能，特別是負值的視覺化處理。',
		'用於測試 NegativeLineChart 圖表組件的功能，包括正負值資料顯示、工具提示中負值的特殊標示、時間軸處理、多系列資料展示等。開發者可使用此測試資料驗證圖表對負值的正確處理。',
		'{https://example.com/negative-line-chart-test}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'time',
		$$
		SELECT date_time AS x_axis,
			series_name AS y_axis,
			value AS data
		FROM public.negative_line_chart_sample_data
		ORDER BY series_name,
			date_time;
$$,
NULL,
'metrotaipei'
);
-- 步驟 6：建立索引以提升查詢效能
CREATE INDEX idx_negative_line_chart_sample_date ON public.negative_line_chart_sample_data(date_time);
CREATE INDEX idx_negative_line_chart_sample_series ON public.negative_line_chart_sample_data(series_name);
CREATE INDEX idx_negative_line_chart_sample_composite ON public.negative_line_chart_sample_data(series_name, date_time);
-- 步驟 7：將組件加入到測試 dashboard 中 (可選)
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 998, 98); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 此為測試資料，component_id 使用 998 避免與正式組件衝突
-- 2. 資料模擬真實經濟指標變化：包含經濟衰退期(負值)和復甦期(正值)
-- 3. 使用 'time' query_type 以支援時間序列資料格式
-- 4. 查詢結果會產生 NegativeLineChart 組件所需的時間序列格式：x_axis(時間)、y_axis(系列名稱)、data(數值)
-- 5. history_config 設為 NULL，因為這是靜態測試資料，不需要歷史資料功能
-- 6. 移除了時間範圍參數，因為這是固定的測試資料集
-- 7. 負值在工具提示中會以紅色顯示，正值保持預設顏色
-- 8. 三個系列使用不同顏色：藍色、紅色、綠色
-- 9. 資料涵蓋2023年全年，展示完整的趨勢變化