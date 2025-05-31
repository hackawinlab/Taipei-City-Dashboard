INSERT INTO public.components (id, index, name)
VALUES (220, 'renewable_bar', '再生能源發電佔比（百分比）');
INSERT INTO public.component_charts (index, types, color, unit)
VALUES (
		'renewable_bar',
		'{BarPercentChart}',
		'{#24B0DD, #56B96D, #F8CF58, #ED6A45}',
		-- 水力、沼氣、焚化、太陽光電
		'%'
	);
-- 這個是寫 data database 的資料表
CREATE TABLE public.renewable_energy_tpe (
	year TEXT,
	total_kwh INTEGER,
	hydro_kwh INTEGER,
	incineration_kwh INTEGER,
	biogas_kwh INTEGER,
	solar_kwh INTEGER
);
-- 這個是寫 data database 的資料表
INSERT INTO public.renewable_energy_tpe (
		year,
		total_kwh,
		hydro_kwh,
		incineration_kwh,
		biogas_kwh,
		solar_kwh
	)
VALUES (data);
-- 這邊的部分已經回到 manager 的 database 了
INSERT INTO public.query_charts (
  index,
  history_config,
  map_config_ids,
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
  'renewable_bar',
  NULL,
  NULL,
  'static',
  NULL,
  0,
  NULL,
  '台北市再生能源資料（假資料）',
  '年度再生能源類型佔比',
  '依年份顯示太陽光電、水力、垃圾焚化、沼氣等再生能源在總發電中的比例。',
  '用於觀察能源結構變化趨勢。',
  '{https://example.com/fake-renewables}',
  '{you}',
  NOW(),
  NOW(),
  'three_d',
  $$
  SELECT 
    x_axis,
    y_axis,
    SUM(data)::int AS data
  FROM (
    SELECT 
      year AS x_axis,
      '水力發電' AS y_axis,
      ROUND(100.0 * hydro_kwh / NULLIF(total_kwh, 0))::int AS data
    FROM renewable_energy_tpe
    WHERE year >= '107年'

    UNION ALL

    SELECT 
      year,
      '垃圾焚化',
      ROUND(100.0 * incineration_kwh / NULLIF(total_kwh, 0))::int
    FROM renewable_energy_tpe
    WHERE year >= '107年'

    UNION ALL

    SELECT 
      year,
      '沼氣發電',
      ROUND(100.0 * biogas_kwh / NULLIF(total_kwh, 0))::int
    FROM renewable_energy_tpe
    WHERE year >= '107年'

    UNION ALL

    SELECT 
      year,
      '太陽光電',
      ROUND(100.0 * solar_kwh / NULLIF(total_kwh, 0))::int
    FROM renewable_energy_tpe
    WHERE year >= '107年'
  ) sub
  GROUP BY x_axis, y_axis
  ORDER BY x_axis, y_axis
  $$,
  NULL,
  'metrotaipei'
);
-- 最後記得加進去 dashboard 的資料表