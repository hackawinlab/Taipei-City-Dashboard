/**
 * 從本地 JSON 載入 YouBike 缺車分析 dashboard 的 4 個 component config，
 * 包成符合 contentStore 既有資料結構（BE response.data.data）的 component 物件，
 * 讓 /dashboard 與 cityDashboard 流程不必走 BE API。
 *
 * 仿 production 命名：兩個 dashboard 各掛 SideBar 一個分區
 *   - youbike-shortage-analysis-taipei      → 「臺北儀表板」（只看臺北）
 *   - youbike-shortage-analysis-metrotaipei → 「雙北儀表板」（雙北合計）
 */

const DASHBOARD_ICON = "directions_bike";
const SOURCE = "YouBike 開放資料";

// Slice = 一個 city 的資料切片，多份 slice 組成單一 dashboard 的 cityDashboard.components。
// 「雙北」dashboard 帶兩份 slice（metrotaipei 合計 + taipei 單城），讓 component 下拉可以切換。
// 注意：兩切片同 index 共用同一個 id，仿 BE 設計（component id 跨 city 唯一），
// 否則 DashboardComponent 的 change-city handler 用 selectedData.id 比對會失敗。
const SLICES = {
	taipei: {
		city: "taipei",
		datasetKey: "Taipei",
	},
	metrotaipei: {
		city: "metrotaipei",
		datasetKey: "All",
	},
};

export const YOUBIKE_SHORTAGE_DASHBOARDS = [
	{
		index: "youbike-shortage-analysis-taipei",
		name: "YouBike 缺車成因分析",
		icon: DASHBOARD_ICON,
		city: "taipei",
		sliceCities: ["taipei"],
	},
	{
		index: "youbike-shortage-analysis-metrotaipei",
		name: "YouBike 缺車成因分析",
		icon: DASHBOARD_ICON,
		city: "metrotaipei",
		sliceCities: ["metrotaipei", "taipei"],
	},
];

const DASHBOARD_BY_INDEX = new Map(
	YOUBIKE_SHORTAGE_DASHBOARDS.map((d) => [d.index, d]),
);

export function isYoubikeShortageIndex(index) {
	return DASHBOARD_BY_INDEX.has(index);
}

export function getYoubikeShortageDashboard(index) {
	return DASHBOARD_BY_INDEX.get(index);
}

const TIME_META = {
	time_from: "static",
	time_to: null,
	update_freq: 1,
	update_freq_unit: "hour",
	history_data: false,
	links: null,
	tags: [],
	contributors: [],
	map_config: [],
	map_filter: null,
	history_config: null,
};

let cachedDataset = null;

async function loadDataset() {
	if (cachedDataset) return cachedDataset;
	const res = await fetch("/data/youbike_hourly_shortage.json", {
		cache: "no-store",
	});
	if (!res.ok) throw new Error(`HTTP ${res.status}`);
	cachedDataset = await res.json();
	return cachedDataset;
}

function buildBlocks(ds, slice) {
	const { datasetKey, city } = slice;

	// === 低車量站佔比時段分布 ===
	// timeline_low 永遠帶 Taipei + NewTaipei 兩條原始 series。
	// 「臺北儀表板」版本只取 Taipei 那條；「雙北儀表板」保留兩條。
	const low = ds.timeline_low ?? [];
	const cityNameZh = (n) =>
		n === "Taipei" ? "臺北市" : n === "NewTaipei" ? "新北市" : n;
	const filteredLow = datasetKey === "All"
		? low
		: low.filter((s) => s.name === datasetKey);
	const timelineSeries = filteredLow.map((s) => ({
		...s,
		name: cityNameZh(s.name),
	}));

	// === 長時段缺車站排行 ===
	const persistenceRows = (ds.bar_persistence?.[datasetKey] ?? []).slice(0, 20);
	const hoursObserved = persistenceRows[0]?.hours_observed ?? 20;
	const persistenceData = persistenceRows.map((s) => ({
		x: s.station_name,
		y: s.empty_hours,
	}));

	// === 站點時段填充率變化（熱力圖）===
	const heatmap = ds.heatmap?.[datasetKey] ?? { categories: [], series: [] };

	// === 站點淨流出量排行（含補車依賴度 dispatch_dependency 分類）===
	// imbalance 結構：{ absolute: [...], per_dock: [...] }（aggregator v2）
	// fallback 是舊結構（純 list），讓沒重跑 aggregator 的環境不至於 crash
	const imbalanceObj = ds.imbalance?.[datasetKey] ?? {};
	const imbalanceRows = Array.isArray(imbalanceObj)
		? imbalanceObj.slice(0, 15)
		: (imbalanceObj.absolute ?? []).slice(0, 15);
	function depTier(dep) {
		if (dep == null) return "未知";
		if (dep >= 0.7) return "高補車依賴";
		if (dep >= 0.4) return "中補車依賴";
		return "低補車依賴";
	}
	const imbalanceData = imbalanceRows.map((s) => ({
		x: s.station_name,
		y: -s.imbalance,
	}));
	const tierCounts = imbalanceRows.reduce((acc, s) => {
		const t = depTier(s.dispatch_dependency);
		acc[t] = (acc[t] || 0) + 1;
		return acc;
	}, {});

	return [
		{
			id: 9001,
			index: "youbike_rhythm",
			city,
			name: "YouBike 低車量站時段佔比",
			source: SOURCE,
			short_desc:
				"顯示一日各時段中可借車輛低於 20% 容量的站數佔比。",
			long_desc:
				"以每小時為單位，計算可借車輛數低於該站車柱數 20% 的站點佔全市站點的比率，呈現一日內缺車情況最集中的時段。資料採用 2026/05/01 02:00–21:00 之 30 分鐘間隔快照，由於樣本僅涵蓋單日，僅供時段分布觀察示範，平假日與長期趨勢分析需累積跨日資料後再行比較。",
			use_case:
				"作為調度時段規劃的初步參考，協助分析缺車尖峰時段並做為補車班次設計的輔助資訊。",
			...TIME_META,
			chart_config: {
				color: ["#ff6b6b", "#60a5fa"],
				types: ["TimelineSeparateChart"],
				unit: "%",
				fit: true,
			},
			chart_data: timelineSeries,
		},
		{
			id: 9002,
			index: "youbike_persistence",
			city,
			name: "YouBike 長時段缺車站排行",
			source: SOURCE,
			short_desc: `顯示觀測時段內每小時平均可借車輛低於 1 的小時數最多的前 20 站（觀測 ${hoursObserved} 小時）。`,
			long_desc:
				"以觀測時段中每小時的平均可借車輛數作為基準，當該時段平均可借車輛低於 1 時計入該站的缺車時數，並依累計時數由高至低排序。本指標反映站點長時間處於可借車輛不足之狀態，前段排名以站柱數較少的觀光與郊區終點型站為主，係因該類站點車量上限較低、達門檻所需流出量較少。資料採用 2026/05/01 之單日快照，與線上「YouBike 見車率」之月度統計相互對照可獲得較完整之長期趨勢。",
			use_case:
				"輔助辨識長時間缺車之站點，作為補給班次規劃、站點規模檢討及調度資源配置之參考。",
			...TIME_META,
			chart_config: {
				color: ["#ff6b6b"],
				types: ["BarChart"],
				unit: "小時",
				label_max_length: 16,
				label_max_width: 200,
				categories: persistenceData.map((d) => d.x),
			},
			chart_data: [
				{
					name: `缺車時數（觀測 ${hoursObserved} 小時內）`,
					data: persistenceData,
				},
			],
		},
		{
			id: 9004,
			index: "youbike_imbalance",
			city,
			name: "YouBike 站點淨流出量排行",
			source: SOURCE,
			short_desc: `顯示觀測時段內估計借出量與歸還量差距最大之前 15 站（補車依賴度分布：${
				Object.entries(tierCounts)
					.map(([k, v]) => `${k} ${v} 站`)
					.join("、") || "—"
			}）。`,
			long_desc:
				"以 30 分鐘間隔快照逐筆比對可借車輛數變化，將下降量加總作為估計借出量、上升量加總作為估計歸還量（含調度補車），兩者差值之絕對值最高者代表結構性流出顯著大於歸還之站點。歸還量並依單筆變化幅度區分為市民自然還車與調度補車，計算「補車依賴度」（dispatch_dependency = 估計補車量 ÷ 估計歸還量）；數值愈高代表該站之車量主要仰賴卡車調度補給維持，愈低則代表車量變化以自然流出與還車為主。資料採用 2026/05/01 之單日快照，連續多日累積後可進一步辨識結構性需求站點。",
			use_case:
				"作為補車班次優先序、調度路線規劃及站點需求結構分析之輔助資訊。",
			...TIME_META,
			chart_config: {
				color: ["#fb7185"],
				types: ["BarChart"],
				unit: "輛",
				label_max_length: 16,
				label_max_width: 200,
				categories: imbalanceData.map((d) => d.x),
			},
			chart_data: [{ name: "估計淨流出量", data: imbalanceData }],
		},
		{
			id: 9003,
			index: "youbike_heatmap",
			city,
			name: "YouBike 站點時段填充率變化",
			source: SOURCE,
			short_desc:
				"顯示一日填充率變化幅度最大之前 25 站於各時段之填充率，色階由紅至綠對應 0% 至 100%。",
			long_desc:
				"以 30 分鐘間隔快照計算每站於各時段之填充率（fill_ratio = 可借車輛 ÷ 車柱數），並依一日之最大值與最小值差距由高至低取前 25 站，呈現各站於不同時段之車量變化情形。色階由紅至綠對應填充率 0% 至 100%，可觀察單站之日間流動模式（如早晨車量充足、下午車量下降，或反之）。資料採用 2026/05/01 之單日快照，跨站之車流方向分析建議參考線上「YouBike2.0 週間群像」「YouBike2.0 週末群像」之 OD 矩陣資料。",
			use_case:
				"輔助觀察單一站點之日間車量變化模式，作為站點調度時段安排之參考。",
			...TIME_META,
			chart_config: {
				color: [
					"#7f1d1d",
					"#dc2626",
					"#f97316",
					"#facc15",
					"#84cc16",
					"#16a34a",
				],
				types: ["HeatmapChart"],
				unit: "%",
				categories: heatmap.categories,
				hide_summary: true,
				hide_data_labels: true,
				fit: true,
			},
			chart_data: heatmap.series,
		},
	];
}

export async function loadYoubikeShortageComponents(index) {
	const dashboard = DASHBOARD_BY_INDEX.get(index);
	if (!dashboard) {
		throw new Error(`Unknown YouBike shortage dashboard index: ${index}`);
	}
	const ds = await loadDataset();
	// Build a slice per city so that DashboardComponent's city dropdown can swap views.
	return dashboard.sliceCities.flatMap((sliceKey) =>
		buildBlocks(ds, SLICES[sliceKey]),
	);
}
