-- BubbleChart 圖表測試資料
-- 此檔案提供測試用的泡泡圖資料，用於驗證 BubbleChart.vue 組件功能
-- 步驟 1：新增測試元件
INSERT INTO public.components (id, index, name)
VALUES (998, 'bubble_chart_sample', '泡泡圖測試圖表');
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'bubble_chart_sample',
		'{#2E91E5,#ff6b6b,#4CAF50,#FF9800,#9C27B0}',
		'{BubbleChart}',
		'分數'
	);
-- 步驟 3：建立測試資料表
CREATE TABLE public.bubble_chart_sample_data (
	x_value DECIMAL(10, 2),
	y_value DECIMAL(10, 2),
	size_value DECIMAL(10, 2),
	series_name TEXT
);
-- 步驟 4：插入測試資料 (模擬學生成績、學習時間與參與度的關係)
INSERT INTO public.bubble_chart_sample_data (x_value, y_value, size_value, series_name)
VALUES -- 數學成績與學習時間，泡泡大小代表課堂參與度 (分散分布)
	(1.2, 45, 25, '數學'),
	(3.8, 78, 45, '數學'),
	(6.5, 62, 18, '數學'),
	(9.2, 89, 65, '數學'),
	(12.1, 71, 32, '數學'),
	(2.5, 93, 55, '數學'),
	(7.8, 54, 28, '數學'),
	(11.3, 85, 42, '數學'),
	(4.7, 67, 38, '數學'),
	(8.9, 76, 51, '數學'),
	(14.2, 58, 22, '數學'),
	(5.1, 82, 47, '數學'),
	(10.6, 94, 68, '數學'),
	(1.8, 39, 15, '數學'),
	(13.7, 88, 59, '數學'),
	-- 英文成績與學習時間，泡泡大小代表課堂參與度 (更分散)
	(2.1, 52, 33, '英文'),
	(5.4, 84, 48, '英文'),
	(8.7, 41, 19, '英文'),
	(11.9, 73, 56, '英文'),
	(3.2, 96, 71, '英文'),
	(7.1, 65, 29, '英文'),
	(12.8, 79, 44, '英文'),
	(4.6, 38, 16, '英文'),
	(9.3, 87, 62, '英文'),
	(14.5, 56, 24, '英文'),
	(6.8, 91, 67, '英文'),
	(1.5, 74, 35, '英文'),
	(10.2, 49, 21, '英文'),
	(13.1, 82, 53, '英文'),
	(15.3, 68, 39, '英文'),
	(0.8, 95, 74, '英文'),
	-- 物理成績與學習時間，泡泡大小代表課堂參與度 (隨機分布)
	(3.5, 61, 27, '物理'),
	(7.2, 43, 14, '物理'),
	(10.8, 86, 58, '物理'),
	(1.9, 75, 41, '物理'),
	(13.4, 52, 23, '物理'),
	(5.7, 92, 66, '物理'),
	(9.1, 37, 12, '物理'),
	(12.6, 78, 49, '物理'),
	(4.3, 64, 31, '物理'),
	(8.5, 89, 63, '物理'),
	(14.8, 46, 18, '物理'),
	(2.7, 81, 52, '物理'),
	(11.4, 55, 26, '物理'),
	(6.9, 94, 69, '物理'),
	(15.1, 72, 37, '物理'),
	(0.5, 59, 20, '物理'),
	-- 化學成績與學習時間 (完全隨機分布)
	(4.1, 48, 30, '化學'),
	(8.3, 83, 57, '化學'),
	(12.7, 35, 11, '化學'),
	(2.4, 77, 43, '化學'),
	(6.6, 91, 65, '化學'),
	(11.2, 54, 25, '化學'),
	(15.6, 69, 38, '化學'),
	(3.8, 42, 17, '化學'),
	(7.5, 86, 60, '化學'),
	(13.9, 63, 34, '化學'),
	(1.3, 95, 72, '化學'),
	(9.7, 51, 22, '化學'),
	(14.3, 74, 46, '化學'),
	(5.2, 39, 13, '化學'),
	(10.5, 88, 61, '化學'),
	(16.0, 66, 36, '化學'),
	-- 生物成績與學習時間 (極度分散)
	(2.8, 57, 28, '生物'),
	(6.4, 34, 9, '生物'),
	(9.8, 81, 54, '生物'),
	(13.5, 47, 19, '生物'),
	(1.1, 93, 70, '生物'),
	(5.9, 65, 32, '生物'),
	(12.3, 29, 8, '生物'),
	(15.7, 76, 45, '生物'),
	(4.4, 84, 59, '生物'),
	(8.1, 53, 24, '生物'),
	(11.8, 97, 73, '生物'),
	(3.6, 41, 15, '生物'),
	(7.7, 72, 40, '生物'),
	(14.1, 58, 27, '生物'),
	(10.3, 85, 62, '生物'),
	(0.9, 44, 16, '生物');
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
		'bubble_chart_sample',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		0,
		NULL,
		'測試資料來源',
		'泡泡圖測試圖表',
		'此為測試用泡泡圖表，展示學生在五個科目（數學、英文、物理、化學、生物）的學習時間、成績與課堂參與度的複雜三維關係。資料為模擬數據，包含80個資料點，完全隨機分散分布，佔滿整個圖表區域，用於驗證 BubbleChart 組件的顯示效果和互動功能。泡泡大小代表課堂參與度，展現真實的非線性、無規律分布。',
		'用於測試 BubbleChart 圖表組件的功能，包括完全分散的泡泡資料顯示、工具提示中 X/Y/Z 軸數值的顯示、縮放互動、五個系列資料展示、泡泡大小變化等。開發者可使用此測試資料驗證圖表對隨機分散三維資料的正確處理和視覺化效果，資料點佔滿整個圖表區域，無明顯規律性。',
		'{https://example.com/bubble-chart-test}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'bubble',
		$$
		SELECT x_value AS x_axis,
			series_name AS y_axis,
			y_value AS data,
			size_value AS size
		FROM public.bubble_chart_sample_data
		ORDER BY series_name,
			x_value;
$$,
NULL,
'metrotaipei'
);
-- 步驟 6：建立索引以提升查詢效能
CREATE INDEX idx_bubble_chart_sample_series ON public.bubble_chart_sample_data(series_name);
CREATE INDEX idx_bubble_chart_sample_x ON public.bubble_chart_sample_data(x_value);
CREATE INDEX idx_bubble_chart_sample_composite ON public.bubble_chart_sample_data(series_name, x_value);
-- 步驟 7：將組件加入到測試 dashboard 中 (可選)
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 998, 98); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 此為測試資料，component_id 使用 998 避免與正式組件衝突
-- 2. 資料模擬學生在五個科目的學習時間(小時)、成績(分數)與課堂參與度(百分比)，完全隨機分散分布
-- 3. 使用 'bubble' query_type 以支援泡泡圖資料格式
-- 4. 查詢結果會產生 BubbleChart 組件所需的格式：x_axis(X軸數值)、y_axis(系列名稱)、data(Y軸數值)、size(泡泡大小)
-- 5. history_config 設為 NULL，因為這是靜態測試資料，不需要歷史資料功能
-- 6. 五個系列使用不同顏色：藍色、紅色、綠色、橙色、紫色
-- 7. 資料點完全隨機分散，佔滿整個圖表區域，無線性關係或明顯規律
-- 8. 支援縮放功能，可以放大查看特定區域的資料點
-- 9. 工具提示會顯示 X 軸(學習時間)、Y 軸(成績)和 Z 軸(參與度)的具體數值
-- 10. 泡泡大小變化範圍從8到74，提供明顯的視覺差異
-- 11. 包含80個資料點，X軸範圍0.5-16小時，Y軸範圍29-97分，完全分散分布
-- 12. 每個科目的資料點都隨機分布在圖表的不同區域，展現真實的泡泡圖效果
-- 13. 後端會將數據轉換為 ApexCharts 泡泡圖所需的格式：
--     {
--       "data": [
--         {
--           "name": "數學",
--           "data": [
--             { "x": 1.2, "y": 45, "z": 25 },
--             { "x": 3.8, "y": 78, "z": 45 },
--             { "x": 6.5, "y": 62, "z": 18 },
--             ...
--           ]
--         },
--         {
--           "name": "英文",
--           "data": [
--             { "x": 2.1, "y": 52, "z": 33 },
--             { "x": 5.4, "y": 84, "z": 48 },
--             ...
--           ]
--         },
--         ...
--       ]
--     }