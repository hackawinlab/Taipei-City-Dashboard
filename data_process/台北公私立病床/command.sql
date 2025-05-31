-- 步驟 1：新增元件
INSERT INTO public.components (id, index, name)
VALUES (221, 'bed_count_taipei_newtaipei', '雙北各區病床總數');

-- 步驟 2：設定圖表型態
INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
  'bed_count_taipei_newtaipei',
  '{#2E91E5,#E15F99}',
  '{DistrictChart,ColumnChart}',
  '床'
);

-- 步驟 2.1：新增新北資料表
-- 新北資料表，記得也要順便加上 newtaipei的 table
CREATE TABLE public.bed_count_taipei (
  year TEXT,
  district_code TEXT,
  district_name TEXT,
  hospital_count INTEGER,
  total_beds INTEGER,
  general_beds INTEGER,
  special_beds INTEGER,
  psychiatric_beds INTEGER,
  acute_beds INTEGER,
  chronic_beds INTEGER,
  acute_general_beds INTEGER,
  psychiatric_acute_general_beds INTEGER,
  chronic_general_beds INTEGER,
  psychiatric_chronic_general_beds INTEGER,
  chronic_tb_beds INTEGER,
  hansen_beds INTEGER,
  international_medical_beds INTEGER,
  icu_beds INTEGER,
  burn_beds INTEGER,
  infant_beds INTEGER,
  emergency_observation_beds INTEGER,
  other_observation_beds INTEGER,
  palliative_beds INTEGER,
  chronic_respiratory_care_beds INTEGER,
  subacute_respiratory_care_beds INTEGER,
  acute_tb_beds INTEGER,
  psychiatric_icu_beds INTEGER,
  post_surgery_recovery_beds INTEGER,
  infant_cots INTEGER,
  hemodialysis_beds INTEGER,
  burn_icu_beds INTEGER,
  general_isolation_beds INTEGER,
  positive_pressure_isolation_beds INTEGER,
  negative_pressure_isolation_beds INTEGER,
  bone_marrow_transplant_beds INTEGER,
  criminal_treatment_beds INTEGER,
  peritoneal_dialysis_beds INTEGER,
  post_acute_care_beds INTEGER,
  integrated_emergency_transfer_beds INTEGER,
  guarded_beds INTEGER,
  forensic_psychiatric_beds INTEGER
);

-- 步驟 3：新增新北資料
INSERT INTO public.bed_count_newtaipei (
  year, district_code, district_name, hospital_count, total_beds, general_beds, special_beds, psychiatric_beds, acute_beds, chronic_beds, acute_general_beds, psychiatric_acute_general_beds, chronic_general_beds, psychiatric_chronic_general_beds, chronic_tb_beds, hansen_beds, international_medical_beds, icu_beds, burn_beds, infant_beds, emergency_observation_beds, other_observation_beds, palliative_beds, chronic_respiratory_care_beds, subacute_respiratory_care_beds, acute_tb_beds, psychiatric_icu_beds, post_surgery_recovery_beds, infant_cots, hemodialysis_beds, burn_icu_beds, general_isolation_beds, positive_pressure_isolation_beds, negative_pressure_isolation_beds, bone_marrow_transplant_beds, criminal_treatment_beds, peritoneal_dialysis_beds, post_acute_care_beds, integrated_emergency_transfer_beds, guarded_beds, forensic_psychiatric_beds
) VALUES
	(data);

-- 步驟 4：新增台北資料
INSERT INTO public.bed_count_taipei (
  year, district_code, district_name, hospital_count, total_beds, general_beds, special_beds, psychiatric_beds, acute_beds, chronic_beds, acute_general_beds, psychiatric_acute_general_beds, chronic_general_beds, psychiatric_chronic_general_beds, chronic_tb_beds, hansen_beds, international_medical_beds, icu_beds, burn_beds, infant_beds, emergency_observation_beds, other_observation_beds, palliative_beds, chronic_respiratory_care_beds, subacute_respiratory_care_beds, acute_tb_beds, psychiatric_icu_beds, post_surgery_recovery_beds, infant_cots, hemodialysis_beds, burn_icu_beds, general_isolation_beds, positive_pressure_isolation_beds, negative_pressure_isolation_beds, bone_marrow_transplant_beds, criminal_treatment_beds, peritoneal_dialysis_beds, post_acute_care_beds, integrated_emergency_transfer_beds, guarded_beds, forensic_psychiatric_beds
) VALUES
	(data);

-- 步驟 5
-- 新增 query_charts 設定
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
) VALUES (
  'bed_count_taipei',
  NULL,
  '{}',
  '{}',
  'static',
  NULL,
  0,
  NULL,
  '衛生福利部統計處《醫療機構病床數統計》',
  '臺北市各行政區病床總數',
  '依年份與行政區呈現臺北市病床總數，數據來自衛福部《醫療機構病床數統計》，反映醫療資源分布。',
  '可用於瞭解各行政區醫療資源配置情形，支援政策規劃與民眾查詢。',
  '{https://dep.mohw.gov.tw/DOS/cp-6601-75361-113.html}',
  '{doit}',
  '2025-05-31 05:19:25',
  '2025-05-31 05:19:25',
  'three_d',
  $$ SELECT 
  year AS x_axis,
  district_name AS y_axis,
  total_beds AS data
FROM bed_count_taipei
WHERE year IS NOT NULL
ORDER BY year, district_name; $$,
  NULL,
  '臺北市'
);
