-- 步驟 1：新增元件
INSERT INTO public.components (id, index, name)
VALUES (
		224,
		'mortality_rate_statistics',
		'台北市死亡機率統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'mortality_rate_statistics',
		'{#FF6B6B,#4ECDC4,#45B7D1}',
		'{TimelineSeparateChart,TimelineStackedChart}',
		'機率'
	);
-- 步驟 3：新增台北市死亡機率統計資料表
CREATE TABLE public.mortality_rate_taipei (
	year_western INTEGER,
	age_group TEXT,
	mortality_rate DECIMAL(10, 8)
);
-- 步驟 4：新增台北市資料 (從 死亡機率_整合.csv 匯入)
INSERT INTO public.mortality_rate_taipei (year_western, age_group, mortality_rate)
VALUES -- 2025年數據
	(2025, '30歲以下', 0.00038867),
	(2025, '30-60歲', 0.00266867),
	(2025, '60歲以上', 0.09010317),
	-- 2026年數據
	(2026, '30歲以下', 0.00036400),
	(2026, '30-60歲', 0.00255500),
	(2026, '60歲以上', 0.08910951),
	-- 2027年數據
	(2027, '30歲以下', 0.00035767),
	(2027, '30-60歲', 0.00251733),
	(2027, '60歲以上', 0.08854122),
	-- 2028年數據
	(2028, '30歲以下', 0.00035267),
	(2028, '30-60歲', 0.00248100),
	(2028, '60歲以上', 0.08797829),
	-- 2029年數據
	(2029, '30歲以下', 0.00034600),
	(2029, '30-60歲', 0.00244500),
	(2029, '60歲以上', 0.08742098),
	-- 2030年數據
	(2030, '30歲以下', 0.00034000),
	(2030, '30-60歲', 0.00241000),
	(2030, '60歲以上', 0.08686878),
	-- 2031年數據
	(2031, '30歲以下', 0.00033500),
	(2031, '30-60歲', 0.00237467),
	(2031, '60歲以上', 0.08632049),
	-- 2032年數據
	(2032, '30歲以下', 0.00032900),
	(2032, '30-60歲', 0.00234133),
	(2032, '60歲以上', 0.08577756),
	-- 2033年數據
	(2033, '30歲以下', 0.00032433),
	(2033, '30-60歲', 0.00230667),
	(2033, '60歲以上', 0.08523951),
	-- 2034年數據
	(2034, '30歲以下', 0.00031867),
	(2034, '30-60歲', 0.00227500),
	(2034, '60歲以上', 0.08470707),
	-- 2035年數據
	(2035, '30歲以下', 0.00031333),
	(2035, '30-60歲', 0.00224100),
	(2035, '60歲以上', 0.08417829);
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
		'mortality_rate_statistics',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'內政部統計處',
		'台北市死亡機率統計',
		'顯示台北市未來10年(2025-2035)死亡機率預測，按年齡分組統計，包含30歲以下、30-60歲、60歲以上等年齡層的死亡機率數據。',
		'可用於了解台北市不同年齡層死亡機率趨勢，支援公共衛生政策制定、保險精算與人口政策規劃。',
		'{https://www.ris.gov.tw/app/portal/346}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'time',
		$$
		SELECT (year_western || '-12-31T23:59:59+08:00')::timestamp with time zone AS x_axis,
			age_group AS y_axis,
			mortality_rate AS data
		FROM public.mortality_rate_taipei
		ORDER BY year_western,
			CASE
				age_group
				WHEN '30歲以下' THEN 1
				WHEN '30-60歲' THEN 2
				WHEN '60歲以上' THEN 3
			END;
$$,
NULL,
'taipei'
);
-- 步驟 6：建立索引以提升查詢效能
CREATE INDEX idx_mortality_rate_year ON public.mortality_rate_taipei(year_western);
CREATE INDEX idx_mortality_rate_age_group ON public.mortality_rate_taipei(age_group);
-- 步驟 7：最後記得將組件加入到相關的 dashboard 中
-- 例如：
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 224, 12); -- 假設 dashboard_id 為 1
-- 備註：
-- 1. 記得調整 component_id (224) 確保不與現有組件衝突
-- 2. 圖表類型設定為 TimelineSeparateChart 和 TimelineStackedChart 以支持折線圖
-- 3. 查詢語句現在返回多系列數據：x_axis (時間), y_axis (年齡組), data (死亡機率)
-- 4. 後端會根據 y_axis 自動分組成多條線，每個年齡組一條線
-- 5. 數據範圍為 2025-2035 年，包含三個年齡組
-- 6. 顏色配置支持三條線：#FF6B6B (30歲以下), #4ECDC4 (30-60歲), #45B7D1 (60歲以上)