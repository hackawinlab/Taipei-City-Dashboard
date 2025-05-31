-- ScatterChart 圖表測試資料
-- 此檔案提供測試用的散點圖資料，用於驗證 ScatterChart.vue 組件功能
-- 步驟 1：新增測試元件
INSERT INTO public.components (id, index, name)
VALUES (999, 'scatter_chart_sample', '散點圖測試圖表');
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'scatter_chart_sample',
		'{#2E91E5,#ff6b6b,#4CAF50}',
		'{ScatterChart}',
		'分數'
	);
-- 步驟 3：建立測試資料表
CREATE TABLE public.scatter_chart_sample_data (
	x_value DECIMAL(10, 2),
	y_value DECIMAL(10, 2),
	series_name TEXT
);
-- 步驟 4：插入測試資料 (模擬學生成績與學習時間的關係)
INSERT INTO public.scatter_chart_sample_data (x_value, y_value, series_name)
VALUES -- 數學成績與學習時間
	(2.5, 65, '數學'),
	(3.0, 70, '數學'),
	(4.5, 78, '數學'),
	(5.0, 82, '數學'),
	(6.5, 85, '數學'),
	(7.0, 88, '數學'),
	(8.5, 92, '數學'),
	(9.0, 95, '數學'),
	(10.5, 98, '數學'),
	(12.0, 99, '數學'),
	-- 英文成績與學習時間
	(2.0, 60, '英文'),
	(3.5, 68, '英文'),
	(4.0, 72, '英文'),
	(5.5, 76, '英文'),
	(6.0, 80, '英文'),
	(7.5, 84, '英文'),
	(8.0, 87, '英文'),
	(9.5, 90, '英文'),
	(10.0, 93, '英文'),
	(11.5, 96, '英文'),
	-- 物理成績與學習時間
	(3.0, 62, '物理'),
	(4.0, 69, '物理'),
	(5.0, 74, '物理'),
	(6.0, 79, '物理'),
	(7.0, 83, '物理'),
	(8.0, 86, '物理'),
	(9.0, 89, '物理'),
	(10.0, 92, '物理'),
	(11.0, 94, '物理'),
	(12.5, 97, '物理');
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
		'scatter_chart_sample',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		0,
		NULL,
		'測試資料來源',
		'散點圖測試圖表',
		'此為測試用散點圖表，展示學生學習時間與成績的相關性。資料為模擬數據，用於驗證 ScatterChart 組件的顯示效果和互動功能，包括多系列資料展示、工具提示、縮放功能等。',
		'用於測試 ScatterChart 圖表組件的功能，包括散點資料顯示、工具提示中 X/Y 軸數值的顯示、縮放互動、多系列資料展示等。開發者可使用此測試資料驗證圖表對散點資料的正確處理和視覺化效果。',
		'{https://example.com/scatter-chart-test}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'scatter',
		$$
		SELECT x_value AS x_axis,
			series_name AS y_axis,
			y_value AS data
		FROM public.scatter_chart_sample_data
		ORDER BY series_name,
			x_value;
$$,
NULL,
'metrotaipei'
);
-- 步驟 6：建立索引以提升查詢效能
CREATE INDEX idx_scatter_chart_sample_series ON public.scatter_chart_sample_data(series_name);
CREATE INDEX idx_scatter_chart_sample_x ON public.scatter_chart_sample_data(x_value);
CREATE INDEX idx_scatter_chart_sample_composite ON public.scatter_chart_sample_data(series_name, x_value);
-- 步驟 7：將組件加入到測試 dashboard 中 (可選)
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 999, 99); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 此為測試資料，component_id 使用 999 避免與正式組件衝突
-- 2. 資料模擬學生學習時間(小時)與成績(分數)的正相關關係
-- 3. 使用 'scatter' query_type 以支援散點圖資料格式
-- 4. 查詢結果會產生 ScatterChart 組件所需的格式：x_axis(X軸數值)、y_axis(系列名稱)、data(Y軸數值)
-- 5. history_config 設為 NULL，因為這是靜態測試資料，不需要歷史資料功能
-- 6. 三個系列使用不同顏色：藍色、紅色、綠色
-- 7. 資料展示學習時間與成績的線性關係，適合散點圖視覺化
-- 8. 支援縮放功能，可以放大查看特定區域的資料點
-- 9. 工具提示會顯示 X 軸(學習時間)和 Y 軸(成績)的具體數值
-- 10. 後端會將數據轉換為 ApexCharts 散點圖所需的格式：
--     {
--       "data": [
--         {
--           "name": "數學",
--           "data": [
--             { "x": 2.5, "y": 65 },
--             { "x": 3.0, "y": 70 },
--             ...
--           ]
--         },
--         ...
--       ]
--     }