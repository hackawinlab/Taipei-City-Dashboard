--
-- Food Safety Early Warning PoC — DB Migration
-- 食安早期預警系統 DB 匯入腳本
--
-- 適用資料庫：PostgreSQL 14+
-- 說明：建立食安相關資料表、插入 fake data，並新增 4 個 dashboard 組件
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

-- ============================================================
-- 1. 建立食安資料表
-- ============================================================

-- 食安稽查紀錄（模擬衛生局稽查資料）
CREATE TABLE IF NOT EXISTS public.food_safety_inspections (
    id              SERIAL PRIMARY KEY,
    business_name   TEXT NOT NULL,
    address         TEXT NOT NULL,
    district        TEXT NOT NULL,
    city            TEXT NOT NULL DEFAULT 'taipei',
    inspection_date DATE NOT NULL,
    inspector_id    TEXT,
    violation_count INTEGER NOT NULL DEFAULT 0,
    result          TEXT NOT NULL CHECK (result IN ('合格', '不合格')),
    violation_items TEXT[],
    longitude       NUMERIC(10, 7),
    latitude        NUMERIC(10, 7),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 社群食安貼文偵測紀錄（PTT/Dcard 爬蟲結果）
CREATE TABLE IF NOT EXISTS public.food_safety_posts (
    id              SERIAL PRIMARY KEY,
    post_id         TEXT NOT NULL,
    platform        TEXT NOT NULL CHECK (platform IN ('ptt', 'dcard')),
    board           TEXT,
    title           TEXT NOT NULL,
    content         TEXT,
    author          TEXT,
    post_time       TIMESTAMPTZ NOT NULL,
    category        TEXT CHECK (category IN ('食物中毒', '異物混入', '衛生疑慮', '標示不符', '其他', NULL)),
    cluster_id      INTEGER,
    risk_score      NUMERIC(4, 2) DEFAULT 0,
    district        TEXT,
    city            TEXT DEFAULT 'taipei',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 群聚事件紀錄（偵測器輸出）
CREATE TABLE IF NOT EXISTS public.food_safety_clusters (
    id              SERIAL PRIMARY KEY,
    cluster_date    DATE NOT NULL,
    district        TEXT NOT NULL,
    city            TEXT NOT NULL DEFAULT 'taipei',
    post_count      INTEGER NOT NULL DEFAULT 0,
    category        TEXT,
    risk_level      TEXT CHECK (risk_level IN ('高風險', '中風險', '低風險')),
    keywords        TEXT[],
    resolved        BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 2. 插入 fake 稽查資料（台北市各行政區）
-- ============================================================

TRUNCATE TABLE public.food_safety_inspections RESTART IDENTITY CASCADE;
INSERT INTO public.food_safety_inspections
    (business_name, address, district, city, inspection_date, violation_count, result, violation_items, longitude, latitude)
VALUES
    ('好味道餐廳',         '南京東路二段88號',       '中山區', 'taipei', '2026-04-15', 0, '合格',   '{}',                           121.5319, 25.0478),
    ('幸福小廚房',         '忠孝東路四段216號',      '大安區', 'taipei', '2026-04-16', 2, '不合格', '{"未標示有效期限","廚房環境不潔"}', 121.5435, 25.0412),
    ('信義美食街便當',     '松高路12號',             '信義區', 'taipei', '2026-04-17', 1, '不合格', '{"食材未冷藏"}',                  121.5638, 25.0414),
    ('老台北麵食館',       '重慶南路一段55號',       '中正區', 'taipei', '2026-04-18', 0, '合格',   '{}',                           121.5193, 25.0446),
    ('松山快炒店',         '八德路三段300號',         '松山區', 'taipei', '2026-04-19', 3, '不合格', '{"油炸油未定期更換","砧板交叉污染","清洗設備不足"}', 121.5526, 25.0498),
    ('大同豆花甜品',       '迪化街一段156號',        '大同區', 'taipei', '2026-04-20', 0, '合格',   '{}',                           121.5280, 25.0540),
    ('文山有機農場直送',   '木柵路三段88號',          '文山區', 'taipei', '2026-04-21', 0, '合格',   '{}',                           121.5014, 25.0380),
    ('士林夜市蚵仔煎',     '基河路101號',             '士林區', 'taipei', '2026-04-22', 1, '不合格', '{"手部衛生不符規定"}',            121.5087, 25.0712),
    ('天母日式料理',       '天母東路25號',            '士林區', 'taipei', '2026-04-23', 0, '合格',   '{}',                           121.5152, 25.0783),
    ('北投溫泉御膳房',     '中山路5號',               '北投區', 'taipei', '2026-04-24', 5, '不合格', '{"食品原料過期","廚房蟑螂","排水溝未加蓋","員工無健康證明","食品添加物超標"}', 121.4930, 25.0622),
    ('內湖科技園區員工餐廳','內湖路一段91號',          '內湖區', 'taipei', '2026-04-25', 0, '合格',   '{}',                           121.5730, 25.0720),
    ('南港老街米粉',       '南港路一段200號',         '南港區', 'taipei', '2026-04-26', 0, '合格',   '{}',                           121.5978, 25.0548),
    ('萬華傳統市場熟食',   '西園路一段60號',          '萬華區', 'taipei', '2026-04-27', 2, '不合格', '{"攤位環境髒亂","食物暴露未覆蓋"}', 121.4987, 25.0340);

-- ============================================================
-- 3. 插入 fake 社群貼文偵測資料
-- ============================================================

TRUNCATE TABLE public.food_safety_posts RESTART IDENTITY CASCADE;
INSERT INTO public.food_safety_posts
    (post_id, platform, board, title, content, author, post_time, category, cluster_id, risk_score, district, city)
VALUES
    ('ptt_00001', 'ptt',   'Food',      '大安區某便當店吃完拉肚子', '昨天在忠孝東路買的便當，吃完之後嚴重腹瀉...', 'user_a1', '2026-04-28 10:23:00+08', '食物中毒', 1, 0.85, '大安區', 'taipei'),
    ('ptt_00002', 'ptt',   'Food',      '同一家便當店！我也中招了', '樓上說的那家嗎？我也買了他們的排骨便當...', 'user_b2', '2026-04-28 11:45:00+08', '食物中毒', 1, 0.82, '大安區', 'taipei'),
    ('ptt_00003', 'ptt',   'Gossiping', '大安區便當食物中毒事件', '群組裡有人說那一帶好幾個人都中鏢', 'user_c3', '2026-04-28 14:10:00+08', '食物中毒', 1, 0.78, '大安區', 'taipei'),
    ('dcard_001', 'dcard', NULL,         '松山區快炒店發現蟑螂！', '昨晚去吃飯，上菜的時候看到碗裡有蟑螂...', 'user_d4', '2026-04-29 19:30:00+08', '衛生疑慮', 2, 0.91, '松山區', 'taipei'),
    ('dcard_002', 'dcard', NULL,         '【警示】松山區某快炒店衛生堪憂', '這家店最近被爆料很多，建議大家避開', 'user_e5', '2026-04-29 20:15:00+08', '衛生疑慮', 2, 0.76, '松山區', 'taipei'),
    ('ptt_00004', 'ptt',   'food',      '信義區便利商店冷凍食品疑似過期', '買了一個關東煮，回家才發現已過期兩天', 'user_f6', '2026-04-30 08:00:00+08', '標示不符', 3, 0.55, '信義區', 'taipei'),
    ('ptt_00005', 'ptt',   'Food',      '中山區炸雞排異物（附圖）', '在南京東路那家排隊炸雞排，咬到一顆螺絲', 'user_g7', '2026-04-30 12:30:00+08', '異物混入', 4, 0.88, '中山區', 'taipei'),
    ('dcard_003', 'dcard', NULL,         '大安區麵包店疑用發霉食材', '買了兩個麵包，都有異味，同事說是發霉', 'user_h8', '2026-04-30 15:00:00+08', '衛生疑慮', 1, 0.62, '大安區', 'taipei'),
    ('ptt_00006', 'ptt',   'Food',      '北投區餐廳食安稽查消息', '聽說衛生局剛去稽查那一帶，罰了幾家', 'user_i9', '2026-05-01 09:00:00+08', '其他',     5, 0.40, '北投區', 'taipei'),
    ('dcard_004', 'dcard', NULL,         '大安區還是那家便當！第三個人中毒了', '我的室友今天也在那裡買，一樣拉肚子', 'user_j0', '2026-05-01 10:20:00+08', '食物中毒', 1, 0.89, '大安區', 'taipei');

-- ============================================================
-- 4. 插入 fake 群聚事件資料
-- ============================================================

TRUNCATE TABLE public.food_safety_clusters RESTART IDENTITY CASCADE;
INSERT INTO public.food_safety_clusters
    (cluster_date, district, city, post_count, category, risk_level, keywords, resolved)
VALUES
    ('2026-04-28', '大安區', 'taipei', 4, '食物中毒', '高風險', '{"便當","腹瀉","食物中毒","拉肚子"}', FALSE),
    ('2026-04-29', '松山區', 'taipei', 2, '衛生疑慮', '高風險', '{"快炒","蟑螂","衛生"}',               FALSE),
    ('2026-04-30', '信義區', 'taipei', 1, '標示不符', '低風險', '{"過期","便利商店"}',                   TRUE),
    ('2026-04-30', '中山區', 'taipei', 1, '異物混入', '中風險', '{"炸雞排","異物","螺絲"}',              FALSE),
    ('2026-05-01', '北投區', 'taipei', 1, '其他',     '低風險', '{"稽查","衛生局"}',                     TRUE);

-- ============================================================
-- 5. 插入 4 個 dashboard 組件
-- ============================================================

-- 5-1. component_charts（圖表設定）
-- 格式：COPY public.component_charts (index, color, types, unit) FROM stdin;
-- 使用 INSERT 語法，方便逐行執行

INSERT INTO public.component_charts (index, color, types, unit) VALUES
    ('food_safety_alert_map',        '{#E74C3C,#E67E22,#F1C40F}',         '{"MapLegend"}',                         '件'),
    ('food_safety_risk_layer',       '{#C0392B,#E74C3C,#E67E22,#F1C40F,#2ECC71}', '{"MapLegend"}',                  ''),
    ('food_safety_trend',            '{#E74C3C,#E67E22,#3498DB}',          '{"TimelineSeparateChart"}',              '則'),
    ('food_safety_violation_summary','{#E74C3C,#E67E22,#F1C40F,#2ECC71}', '{"ColumnChart"}',                        '件')
ON CONFLICT (index) DO UPDATE SET
    color  = EXCLUDED.color,
    types  = EXCLUDED.types,
    unit   = EXCLUDED.unit;

-- 5-2. component_maps（地圖圖層設定）
-- 使用次高可用 id（從 200 起，避免與現有 id 衝突）

INSERT INTO public.component_maps (id, index, title, type, source, size, icon, paint, property) VALUES
    (
        200,
        'food_safety_alert_map',
        '食安稽查點位',
        'symbol',
        'geojson',
        NULL,
        'cross_bold',
        '{}',
        '[{"key":"business_name","name":"商家名稱"},{"key":"address","name":"地址"},{"key":"district","name":"行政區"},{"key":"violation_count","name":"違規數"},{"key":"inspection_result","name":"稽查結果"}]'
    ),
    (
        201,
        'food_safety_risk_layer',
        '行政區食安風險',
        'fill',
        'geojson',
        NULL,
        NULL,
        '{"fill-color":["match",["get","risk_level"],"高風險","#C0392B","中風險","#E67E22","低風險","#2ECC71","#808080"],"fill-opacity":0.55}',
        '[{"key":"district","name":"行政區"},{"key":"risk_level","name":"風險等級"},{"key":"high_risk","name":"高風險案件"},{"key":"medium_risk","name":"中風險案件"},{"key":"low_risk","name":"低風險案件"},{"key":"violation_rate","name":"違規率"}]'
    )
ON CONFLICT (id) DO UPDATE SET
    index    = EXCLUDED.index,
    title    = EXCLUDED.title,
    type     = EXCLUDED.type,
    source   = EXCLUDED.source,
    icon     = EXCLUDED.icon,
    paint    = EXCLUDED.paint,
    property = EXCLUDED.property;

-- 5-3. components（組件基本資料）

INSERT INTO public.components (index, name) VALUES
    ('food_safety_alert_map',         '食安警報地圖'),
    ('food_safety_risk_layer',        '食安風險行政區塗層'),
    ('food_safety_trend',             '食安貼文趨勢'),
    ('food_safety_violation_summary', '違規統計摘要')
ON CONFLICT (index) DO UPDATE SET name = EXCLUDED.name;

-- 5-4. query_charts（查詢設定與組件描述）

INSERT INTO public.query_charts
    (index, history_config, map_config_ids, map_filter, time_from, time_to, update_freq, update_freq_unit,
     source, short_desc, long_desc, use_case, links, contributors,
     created_at, updated_at, query_type, query_chart, query_history, city)
VALUES
(
    'food_safety_alert_map',
    NULL,
    '{200}',
    '{}',
    'static',
    NULL,
    1,
    'day',
    '臺北市衛生局',
    '顯示台北市食安稽查點位與違規標示。',
    '整合臺北市衛生局食品安全稽查資料與社群食安貼文偵測結果，於地圖上標示各稽查點位、違規等級及事件摘要。使用者可點擊點位查看詳細稽查紀錄，並搭配社群群聚偵測警報，快速掌握潛在食安熱點。',
    '適用於食品安全管理人員監控轄區內稽查點位的合格狀況，以及即時追蹤社群反映的食安疑慮，提升主動稽查效率。',
    '{"https://data.taipei/dataset/detail?id=food-safety-inspection"}',
    '{"doit"}',
    NOW(),
    NOW(),
    'map_legend',
    'SELECT unnest(array[''不合格'', ''已警示'', ''合格'']) as name, ''symbol'' as type',
    NULL,
    'taipei'
),
(
    'food_safety_risk_layer',
    NULL,
    '{201}',
    '{"mode":"byLayer"}',
    'static',
    NULL,
    1,
    'day',
    '臺北市衛生局',
    '以行政區塗層顯示台北市食安風險熱區。',
    '以 Mapbox fill layer 將台北市各行政區依食安風險等級（高／中／低）塗色，風險等級由社群食安貼文群聚密度、近期稽查違規率與歷史違規紀錄綜合計算而來。使用者可點擊行政區查看細項數據，亦可依風險等級篩選地圖顯示範圍，協助衛生主管機關快速識別需優先介入的區域。',
    '適用於衛生政策決策者與稽查人力調度，透過視覺化的地圖塗層快速判斷資源應優先部署至哪些行政區，提升食安監管效能。',
    '{"https://data.taipei/dataset/detail?id=food-safety-inspection"}',
    '{"doit"}',
    NOW(),
    NOW(),
    'map_legend',
    'SELECT unnest(array[''高風險'', ''中風險'', ''低風險'']) as name, ''fill'' as type',
    NULL,
    'taipei'
),
(
    'food_safety_trend',
    NULL,
    '{}',
    '{}',
    'static',
    NULL,
    1,
    'hour',
    'PTT / Dcard 爬蟲',
    '顯示近 30 天食安相關社群貼文趨勢。',
    '從 PTT（Food、Gossiping 版）與 Dcard 爬取含食安關鍵字的貼文，經 NLP 分類後統計每日各類別（食物中毒、衛生疑慮、異物混入、標示不符）的貼文數量，呈現趨勢曲線。突發性峰值代表可能的食安群聚事件，可搭配群聚偵測系統觸發早期預警通知。',
    '適用於食安趨勢監測，透過社群輿情資料補充官方稽查盲點，早一步察覺民眾已開始反映的食安問題，縮短問題發現到主動介入的時間差。',
    '{"https://www.ptt.cc/bbs/Food/index.html","https://www.dcard.tw/f/food"}',
    '{"doit"}',
    NOW(),
    NOW(),
    'time',
    E'SELECT\n  DATE_TRUNC(''day'', post_time) AT TIME ZONE ''Asia/Taipei'' AS x_axis,\n  category AS y_axis,\n  COUNT(*) AS data\nFROM public.food_safety_posts\nWHERE post_time >= NOW() - INTERVAL ''30 days''\n  AND category IS NOT NULL\nGROUP BY x_axis, y_axis\nORDER BY x_axis',
    NULL,
    'taipei'
),
(
    'food_safety_violation_summary',
    NULL,
    '{}',
    '{}',
    'static',
    NULL,
    1,
    'day',
    '臺北市衛生局',
    '顯示台北市各行政區食安違規件數統計。',
    '彙整臺北市各行政區近期食品安全稽查違規件數，以直條圖呈現各區合格與不合格比例。資料來源為衛生局定期稽查紀錄，每日更新。顏色編碼對應違規嚴重程度，方便快速識別違規熱區，並可搭配地圖組件連動篩選，下鑽至特定行政區的稽查點位詳情。',
    '適用於衛生局月報彙整、稽查資源分配評估，以及對外公開的食安透明度揭露，讓市民了解所在行政區的整體食安水準。',
    '{"https://data.taipei/dataset/detail?id=food-safety-inspection"}',
    '{"doit"}',
    NOW(),
    NOW(),
    'two_d',
    E'SELECT\n  district AS x_axis,\n  result AS y_axis,\n  COUNT(*) AS data\nFROM public.food_safety_inspections\nWHERE city = ''taipei''\n  AND inspection_date >= NOW() - INTERVAL ''90 days''\nGROUP BY district, result\nORDER BY district',
    NULL,
    'taipei'
)
ON CONFLICT (index, city) DO UPDATE SET
    map_config_ids   = EXCLUDED.map_config_ids,
    map_filter       = EXCLUDED.map_filter,
    source           = EXCLUDED.source,
    short_desc       = EXCLUDED.short_desc,
    long_desc        = EXCLUDED.long_desc,
    use_case         = EXCLUDED.use_case,
    query_type       = EXCLUDED.query_type,
    query_chart      = EXCLUDED.query_chart,
    updated_at       = NOW();

-- ============================================================
-- 6. 建立食安 dashboard（將 4 個組件加入）
-- ============================================================

-- 取得 4 個組件的 id（以 index 查詢）
-- INSERT INTO public.dashboards (index, name, components, icon, updated_at, created_at)
-- 注意：components 欄位為 integer array，需在 components 表有資料後才能正確填入
-- 此處先以 subquery 動態取得 id

DO $$
DECLARE
    v_alert_map_id   INTEGER;
    v_risk_layer_id  INTEGER;
    v_trend_id       INTEGER;
    v_summary_id     INTEGER;
BEGIN
    SELECT id INTO v_alert_map_id   FROM public.components WHERE index = 'food_safety_alert_map';
    SELECT id INTO v_risk_layer_id  FROM public.components WHERE index = 'food_safety_risk_layer';
    SELECT id INTO v_trend_id       FROM public.components WHERE index = 'food_safety_trend';
    SELECT id INTO v_summary_id     FROM public.components WHERE index = 'food_safety_violation_summary';

    INSERT INTO public.dashboards (index, name, components, icon, updated_at, created_at)
    VALUES (
        'food_safety_taipei',
        '食安早期預警',
        ARRAY[v_alert_map_id, v_risk_layer_id, v_trend_id, v_summary_id],
        'restaurant',
        NOW(),
        NOW()
    )
    ON CONFLICT (index) DO UPDATE SET
        name       = EXCLUDED.name,
        components = EXCLUDED.components,
        updated_at = NOW();
END$$;

-- ============================================================
-- 完成
-- ============================================================
-- 建立完成後可執行以下查詢確認：
--   SELECT * FROM public.food_safety_inspections LIMIT 5;
--   SELECT * FROM public.food_safety_posts LIMIT 5;
--   SELECT index, name FROM public.components WHERE index LIKE 'food_safety%';
--   SELECT index, short_desc, city FROM public.query_charts WHERE index LIKE 'food_safety%';
