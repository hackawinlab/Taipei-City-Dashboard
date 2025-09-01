-- 專任醫生人數統計完整設定檔
-- 參考 76_complete.sql 結構，為專任醫生人數數據建立完整的組件配置
-- 步驟 1：新增元件 - 專任醫生人數統計
INSERT INTO public.components (id, index, name)
VALUES (
		308,
		'hospital_specialist_stats',
		'專任醫生人數統計'
	);
-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
		'hospital_specialist_stats',
		'{#FF6B6B,#4ECDC4,#45B7D1,#96CEB4,#FFEAA7,#DDA0DD,#98FB98,#F0E68C,#FFB6C1,#87CEEB,#D2691E,#FF7F50,#6495ED,#20B2AA,#9370DB,#32CD32,#FF69B4,#1E90FF,#FF8C00,#8A2BE2}',
		'{BarChart,ColumnChart,DonutChart}',
		'人'
	);
-- 步驟 3：新增專任醫生人數統計資料表
CREATE TABLE public.hospital_specialist_stats (city TEXT, specialty TEXT, doctor_count INT);
-- 步驟 4：新增專任醫生人數統計資料（臺北市+新北市+雙北）
INSERT INTO public.hospital_specialist_stats (city, specialty, doctor_count)
VALUES -- 臺北市資料
	('臺北市', '家庭醫學科', 199),
	('臺北市', '內科', 1516),
	('臺北市', '外科', 553),
	('臺北市', '兒科', 343),
	('臺北市', '婦產科', 253),
	('臺北市', '骨科', 197),
	('臺北市', '神經科', 196),
	('臺北市', '神經外科', 120),
	('臺北市', '泌尿科', 159),
	('臺北市', '耳鼻喉科', 137),
	('臺北市', '眼科', 193),
	('臺北市', '皮膚科', 88),
	('臺北市', '精神科', 203),
	('臺北市', '復健科', 116),
	('臺北市', '整形外科', 59),
	('臺北市', '麻醉科', 230),
	('臺北市', '放射診斷科', 248),
	('臺北市', '放射腫瘤科', 79),
	('臺北市', '解剖病理科', 89),
	('臺北市', '臨床病理科', 26),
	('臺北市', '核子醫學科', 40),
	('臺北市', '急診醫學科', 257),
	('臺北市', '職業醫學科', 29),
	('臺北市', '口腔顎面外科', 52),
	('臺北市', '口腔病理科', 7),
	('臺北市', '齒顎矯正科', 26),
	('臺北市', '牙周病科', 42),
	('臺北市', '兒童牙科', 20),
	('臺北市', '牙髓病科', 25),
	('臺北市', '贋復補綴牙科', 46),
	('臺北市', '牙體復形科', 11),
	('臺北市', '家庭牙醫科', 28),
	('臺北市', '特殊需求者口腔醫學科', 2),
	-- 新北市資料
	('新北市', '家庭醫學科', 135),
	('新北市', '內科', 704),
	('新北市', '外科', 254),
	('新北市', '兒科', 144),
	('新北市', '婦產科', 116),
	('新北市', '骨科', 137),
	('新北市', '神經科', 114),
	('新北市', '神經外科', 74),
	('新北市', '泌尿科', 102),
	('新北市', '耳鼻喉科', 70),
	('新北市', '眼科', 73),
	('新北市', '皮膚科', 31),
	('新北市', '精神科', 116),
	('新北市', '復健科', 83),
	('新北市', '整形外科', 33),
	('新北市', '麻醉科', 117),
	('新北市', '放射診斷科', 115),
	('新北市', '放射腫瘤科', 39),
	('新北市', '解剖病理科', 45),
	('新北市', '臨床病理科', 9),
	('新北市', '核子醫學科', 22),
	('新北市', '急診醫學科', 213),
	('新北市', '職業醫學科', 12),
	('新北市', '口腔顎面外科', 21),
	('新北市', '口腔病理科', 1),
	('新北市', '齒顎矯正科', 9),
	('新北市', '牙周病科', 16),
	('新北市', '兒童牙科', 8),
	('新北市', '牙髓病科', 12),
	('新北市', '贋復補綴牙科', 9),
	('新北市', '牙體復形科', 0),
	('新北市', '家庭牙醫科', 21),
	('新北市', '特殊需求者口腔醫學科', 8),
	-- 雙北合計資料
	('雙北', '家庭醫學科', 334),
	('雙北', '內科', 2220),
	('雙北', '外科', 807),
	('雙北', '兒科', 487),
	('雙北', '婦產科', 369),
	('雙北', '骨科', 334),
	('雙北', '神經科', 310),
	('雙北', '神經外科', 194),
	('雙北', '泌尿科', 261),
	('雙北', '耳鼻喉科', 207),
	('雙北', '眼科', 266),
	('雙北', '皮膚科', 119),
	('雙北', '精神科', 319),
	('雙北', '復健科', 199),
	('雙北', '整形外科', 92),
	('雙北', '麻醉科', 347),
	('雙北', '放射診斷科', 363),
	('雙北', '放射腫瘤科', 118),
	('雙北', '解剖病理科', 134),
	('雙北', '臨床病理科', 35),
	('雙北', '核子醫學科', 62),
	('雙北', '急診醫學科', 470),
	('雙北', '職業醫學科', 41),
	('雙北', '口腔顎面外科', 73),
	('雙北', '口腔病理科', 8),
	('雙北', '齒顎矯正科', 35),
	('雙北', '牙周病科', 58),
	('雙北', '兒童牙科', 28),
	('雙北', '牙髓病科', 37),
	('雙北', '贋復補綴牙科', 55),
	('雙北', '牙體復形科', 11),
	('雙北', '家庭牙醫科', 49),
	('雙北', '特殊需求者口腔醫學科', 10);
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
		'hospital_specialist_stats',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'臺北市專任醫生人數統計',
		'顯示臺北市各醫學科別的專任醫生人數統計，包含內科、外科、兒科、婦產科等各專科醫師的人力分布情況。',
		'可用於了解臺北市醫療人力資源分布，支援醫療人力規劃、專科醫師培育政策制定及醫療服務品質提升。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT specialty AS x_axis,
			doctor_count AS data
		FROM public.hospital_specialist_stats
		WHERE city = '臺北市'
		ORDER BY doctor_count DESC;
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
		'hospital_specialist_stats',
		NULL,
		'{}',
		'{}',
		'static',
		NULL,
		1,
		'year',
		'衛生福利部統計處',
		'雙北專任醫生人數統計',
		'顯示雙北地區（臺北市與新北市）各醫學科別的專任醫生人數統計，包含內科、外科、兒科、婦產科等各專科醫師的人力分布情況。',
		'可用於了解雙北地區醫療人力資源分布，支援區域醫療人力規劃、專科醫師培育政策制定及醫療服務品質提升。',
		'{https://www.mohw.gov.tw/}',
		'{doit}',
		'2025-01-20 10:00:00',
		'2025-01-20 10:00:00',
		'two_d',
		$$
		SELECT specialty AS x_axis,
			doctor_count AS data
		FROM public.hospital_specialist_stats
		WHERE city = '雙北'
		ORDER BY doctor_count DESC;
$$,
NULL,
'metrotaipei'
);
-- 步驟 7：建立索引以提升查詢效能
CREATE INDEX idx_hospital_specialist_city ON public.hospital_specialist_stats(city);
CREATE INDEX idx_hospital_specialist_specialty ON public.hospital_specialist_stats(specialty);
-- 步驟 8：將組件加入到相關的 dashboard 中
-- 注意：實際執行時需要確認 dashboard_id 和調整 order_index
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (1, 308, 16); -- 臺北市專任醫生人數統計
-- INSERT INTO public.dashboard_components (dashboard_id, component_id, order_index)
-- VALUES (2, 308, 17); -- 雙北專任醫生人數統計
-- 備註：
-- 1. component_id 使用 308，請確保不與現有組件衝突
-- 2. 臺北市和雙北都使用 two_d 查詢類型，按醫生人數降序排列
-- 3. 數據來源為原始 66.sql 中的真實數據，已重新整理為標準化格式
-- 4. 臺北市組件屬於 'taipei' 城市，雙北組件屬於 'metrotaipei' 城市
-- 5. 使用 BarChart 作為主要圖表類型，適合比較不同科別的醫生人數
-- 6. 同時支援 ColumnChart 和 DonutChart，提供多種視覺化選擇
-- 7. 單位設定為 '人'，符合醫生人數的計量單位
-- 8. 雙北數據為臺北市和新北市的合計值
-- 9. 按醫生人數降序排列，讓人數最多的科別優先顯示
-- 10. 內科醫師人數最多，其次是外科、急診醫學科等
-- 11. 牙科相關科別醫師人數相對較少
-- 12. 支援 DonutChart 顯示各科別醫師人數的比例分布
-- 13. 數據反映了醫療體系中不同專科的人力配置情況
-- 14. 可用於醫療政策制定和醫師培育規劃參考