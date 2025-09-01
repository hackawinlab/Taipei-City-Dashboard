-- 113年疫苗接種統計完整設定檔
-- 參考 85_complete.sql 結構，為疫苗接種數據建立完整的組件配置
-- 步驟 1：新增元件 - 113年疫苗接種統計
INSERT INTO public.components (id, index, name)
VALUES (
		306,
		'vaccine_statistics_2024',
		'113年疫苗接種統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'vaccine_statistics_2024',
		'{#FF6B6B,#4ECDC4,#45B7D1,#96CEB4,#FFEAA7,#DDA0DD,#98FB98,#F0E68C,#FFB6C1,#87CEEB,#D2691E,#FF7F50,#6495ED}',
		'{ColumnChart,BarChart,DonutChart}',
		'人次'
	);
-- 步驟 3：新增疫苗接種統計資料表
CREATE TABLE public.vaccine_statistics_2024 (
	city TEXT,
	vaccine_type TEXT,
	vaccination_count INT
);
-- 步驟 4：新增疫苗接種統計資料（臺北市+新北市+雙北總計）
INSERT INTO public.vaccine_statistics_2024 (city, vaccine_type, vaccination_count)
VALUES -- 臺北市資料
	('臺北市', 'B型肝炎免疫球蛋白(HBIG)', 394),
	('臺北市', 'B型肝炎疫苗(Hepatitis B)', 16769),
	('臺北市', '五合一疫苗(DTaP-Hib-IPV)', 13381),
	('臺北市', '13價結合型肺炎鏈球菌疫苗(PCV13)', 15938),
	('臺北市', '卡介苗(BCG)', 16239),
	('臺北市', '麻疹、腮腺炎、德國麻疹混合疫苗(MMR)', 16239),
	('臺北市', '水痘疫苗(Varicella)', 14211),
	('臺北市', 'A型肝炎疫苗(Hepatitis A)', 13362),
	('臺北市', '日本腦炎疫苗(JE)', 14420),
	(
		'臺北市',
		'白喉破傷風非細胞性百日咳及不活化小兒麻痺混合疫苗(DTaP-IPV/Tdap-IPV)',
		16408
	),
	-- 新北市資料
	('新北市', 'B型肝炎免疫球蛋白(HBIG)', 350),
	('新北市', 'B型肝炎疫苗(Hepatitis B)', 16728),
	('新北市', '五合一疫苗(DTaP-Hib-IPV)', 16859),
	('新北市', '13價結合型肺炎鏈球菌疫苗(PCV13)', 16355),
	('新北市', '卡介苗(BCG)', 21267),
	('新北市', '麻疹、腮腺炎、德國麻疹混合疫苗(MMR)', 29507),
	('新北市', '水痘疫苗(Varicella)', 18845),
	('新北市', 'A型肝炎疫苗(Hepatitis A)', 21351),
	('新北市', '日本腦炎疫苗(JE)', 20146),
	(
		'新北市',
		'白喉破傷風非細胞性百日咳及不活化小兒麻痺混合疫苗(DTaP-IPV/Tdap-IPV)',
		29525
	),
	-- 雙北總計
	('雙北', 'B型肝炎免疫球蛋白(HBIG)', 744),
	('雙北', 'B型肝炎疫苗(Hepatitis B)', 33497),
	('雙北', '五合一疫苗(DTaP-Hib-IPV)', 30240),
	('雙北', '13價結合型肺炎鏈球菌疫苗(PCV13)', 32293),
	('雙北', '卡介苗(BCG)', 37506),
	('雙北', '麻疹、腮腺炎、德國麻疹混合疫苗(MMR)', 45746),
	('雙北', '水痘疫苗(Varicella)', 33056),
	('雙北', 'A型肝炎疫苗(Hepatitis A)', 34713),
	('雙北', '日本腦炎疫苗(JE)', 34566),
	(
		'雙北',
		'白喉破傷風非細胞性百日咳及不活化小兒麻痺混合疫苗(DTaP-IPV/Tdap-IPV)',
		45933
	);
-- 步驟 5：新增 query_charts 設定 - 臺北市
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
		'vaccine_statistics_2024',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部疾病管制署',
		'113年臺北市疫苗接種統計',
		'顯示113年臺北市各類疫苗接種人次統計，包含B型肝炎疫苗、五合一疫苗、肺炎鏈球菌疫苗、卡介苗、MMR疫苗、水痘疫苗、A型肝炎疫苗、日本腦炎疫苗等常規疫苗接種情況。',
		'可用於了解臺北市疫苗接種覆蓋率、疫苗政策執行成效評估、公共衛生防疫規劃，以及疫苗供應需求分析。',
		'{https://www.cdc.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT vaccine_type AS x_axis,
			vaccination_count AS data
		FROM public.vaccine_statistics_2024
		WHERE city = '臺北市'
		ORDER BY vaccination_count DESC;
$$,
NULL,
'taipei'
);
-- 步驟 6：新增 query_charts 設定 - 雙北
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
		'vaccine_statistics_2024',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部疾病管制署',
		'113年雙北疫苗接種統計比較',
		'顯示113年雙北地區（臺北市與新北市）各類疫苗接種人次統計比較，包含B型肝炎疫苗、五合一疫苗、肺炎鏈球菌疫苗、卡介苗、MMR疫苗、水痘疫苗、A型肝炎疫苗、日本腦炎疫苗等常規疫苗接種情況。',
		'可用於比較雙北地區疫苗接種差異、區域疫苗政策執行成效評估、跨縣市公共衛生防疫規劃，以及區域疫苗供應需求分析。',
		'{https://www.cdc.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'three_d',
		$$
		SELECT vaccine_type AS x_axis,
			city AS y_axis,
			vaccination_count AS data
		FROM public.vaccine_statistics_2024
		WHERE city IN ('臺北市', '新北市')
		ORDER BY vaccine_type,
			city;
$$,
NULL,
'metrotaipei'
);
-- 步驟 7：建立索引以提升查詢效能
CREATE INDEX idx_vaccine_statistics_2024_city ON public.vaccine_statistics_2024(city);
CREATE INDEX idx_vaccine_statistics_2024_vaccine_type ON public.vaccine_statistics_2024(vaccine_type);
CREATE INDEX idx_vaccine_statistics_2024_composite ON public.vaccine_statistics_2024(city, vaccine_type);
-- 步驟 8：將組件加入到相關的 dashboard 中
-- 注意：實際執行時需要確認 dashboard_id 和調整 order_index
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 306, 15); -- 臺北市疫苗接種統計
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (2, 306, 16); -- 雙北疫苗接種統計
-- 備註：
-- 1. component_id 使用 306，請確保不與現有組件衝突
-- 2. 臺北市使用 two_d 查詢類型，顯示單一城市的各項疫苗接種量
-- 3. 雙北使用 three_d 查詢類型，比較兩個城市的各項疫苗接種量
-- 4. 數據來源為113年疫苗接種統計真實數據
-- 5. 臺北市組件屬於 'taipei' 城市，雙北組件屬於 'metrotaipei' 城市
-- 6. 使用 ColumnChart 作為主要圖表類型，適合比較不同疫苗類型的接種量
-- 7. 單位設定為 '人次'，符合疫苗接種統計的計量單位
-- 8. 顏色配置支援多種疫苗類型的視覺區分
-- 9. 疫苗名稱包含中英文對照，便於識別
-- 10. 數據包含雙北總計，方便進行區域性分析