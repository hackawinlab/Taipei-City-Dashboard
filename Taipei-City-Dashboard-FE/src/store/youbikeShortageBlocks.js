/**
 * 從本地 JSON 載入 YouBike 缺車分析 dashboard 的 4 個 component config，
 * 包成符合 contentStore 既有資料結構（BE response.data.data）的 component 物件，
 * 讓 /dashboard 與 cityDashboard 流程不必走 BE API。
 */

const DASHBOARD_INDEX = "youbike-shortage-analysis";
const DASHBOARD_NAME = "YouBike 缺車成因分析（勞動節單日 demo）";
const DASHBOARD_ICON = "directions_bike";
const CITY = "metrotaipei";
const SOURCE = "YouBike 開放資料 ‧ 2026/05/01 02:00–21:00 單日快照（demo）";

// 所有 block 共用的 demo 警語，貼在 long_desc 開頭，info 按鈕點開即看到
const DEMO_PREFIX =
	"[資料樣本] 本指標僅根據 2026/05/01（勞動節 + 週五）02:00–21:00 共 20 小時的快照計算，**無法代表平日／週末／跨日結構**。\n\n本 dashboard 的定位是「分析框架的 demo」，現況觀測請以線上「YouBike 使用情況」（即時）、「見車率／見位率」（月度）為準。本 dashboard 的獨家價值在於 Block 4 的 imbalance 視角與 Block 2/4 的物種對照框架，方法論示範用。\n\n---\n\n";

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

function buildBlocks(ds) {
	// === Block 1：缺車站佔比 ‧ 全市一日節奏 ===
	// 原本有 4 條線（雙北 × empty/low ratio）、視覺密度高；empty_ratio 全天最高僅 ~7%、
	// 主要對比訊號在 low_ratio。簡化為 2 條 low_ratio 線，故事重點集中在「整天節奏」上。
	const low = ds.timeline_low ?? [];
	const cityLabel = (n) =>
		n === "Taipei" ? "臺北市" : n === "NewTaipei" ? "新北市" : n;
	const timelineSeries = low.map((s) => ({
		...s,
		name: `${cityLabel(s.name)}：低於 20% 容量`,
	}));

	// === Block 2：長期缺車站排行 ===
	const persistenceRows = (ds.bar_persistence?.All ?? []).slice(0, 20);
	const hoursObserved = persistenceRows[0]?.hours_observed ?? 20;
	const persistenceData = persistenceRows.map((s) => ({
		x: s.station_name,
		y: s.empty_hours,
	}));

	// === Block 3：這些常客的時段分布（熱力圖）===
	const heatmap = ds.heatmap?.All ?? { categories: [], series: [] };

	// === Block 4：車一去不返排行（含補車依賴度 dispatch_dependency 分類）===
	// imbalance 結構：{ absolute: [...], per_dock: [...] }（aggregator v2）
	// fallback 是舊結構（純 list），讓沒重跑 aggregator 的環境不至於 crash
	const imbalanceObj = ds.imbalance?.All ?? {};
	const imbalanceRows = Array.isArray(imbalanceObj)
		? imbalanceObj.slice(0, 15)
		: (imbalanceObj.absolute ?? []).slice(0, 15);
	// 依 dispatch_dependency 分三類，標記在站名前面、視覺上一眼可辨
	function depTier(dep) {
		if (dep == null) return { mark: "", label: "未知" };
		if (dep >= 0.7) return { mark: "★ ", label: "黑洞型（卡車撐住）" };
		if (dep >= 0.4) return { mark: "◆ ", label: "混合型" };
		return { mark: "○ ", label: "冷終點型（沒人補也沒人還）" };
	}
	const imbalanceData = imbalanceRows.map((s) => {
		const tier = depTier(s.dispatch_dependency);
		return {
			x: `${tier.mark}${s.station_name}`,
			y: -s.imbalance,
		};
	});
	// 三類佔比，給 long_desc 動態填上
	const tierCounts = imbalanceRows.reduce(
		(acc, s) => {
			const t = depTier(s.dispatch_dependency).label;
			acc[t] = (acc[t] || 0) + 1;
			return acc;
		},
		{},
	);

	return [
		{
			id: 9001,
			index: "youbike_rhythm",
			city: CITY,
			name: "缺車站佔比 ‧ 雙北一日節奏",
			source: SOURCE,
			short_desc:
				"雙北一日「缺車尖峰」曲線：每小時可借車輛 < 20% 容量的站佔比。提醒：本曲線為勞動節單日樣本、可能反映出遊潮而非通勤潮",
			long_desc:
				DEMO_PREFIX +
				"圖中兩條線為臺北市與新北市的「低於 20% 容量站佔比」隨時間的變化。觀察一日節奏可看出尖峰時段與城市差異。\n\n**重要警示**：2026/05/01 是勞動節（也是週五）。當天的下午尖峰可能反映「假日出遊潮」而非「下班通勤潮」，請勿把本曲線當作典型工作日的通勤節奏。實際結構性結論需要累積 7–14 天涵蓋平日／週末／雨晴的資料才有信心。\n\n簡化說明：原本另有兩條「完全無車站佔比」線，因全天最高僅 ~7% 視覺對比小，已併入下方 KPI 卡片呈現，避免線過密、模糊主視覺。",
			use_case: "示範 demo：跨日資料累積後可辨識尖峰時段、規劃補車班次、做節假日／天氣對照。",
			...TIME_META,
			chart_config: {
				color: ["#ff6b6b", "#60a5fa"],
				types: ["TimelineSeparateChart"],
				unit: "%",
			},
			chart_data: timelineSeries,
		},
		{
			id: 9002,
			index: "youbike_persistence",
			city: CITY,
			name: "長期缺車站排行（小站／補不到型）",
			source: SOURCE,
			short_desc: `這天 ${hoursObserved} 小時中有多少小時平均可借車輛 < 1。前段集中在容量小（22–60 格）的觀光終點站 — 對照下方 Block 4「大站／補不夠型」`,
			long_desc:
				DEMO_PREFIX +
				"**症狀面**：哪些站整天都缺車？依觀測時段內每小時的平均可借車輛 < 1 為門檻，計算每站達標的小時數。\n\n**先天的偏向（非常重要）**：本榜單前段集中在容量小（22–60 格）的觀光／郊區終點型站，因為它們的車量天花板低、整天都跌破 1 台車門檻最容易達成。本榜單與 Block 4「車一去不返」**因 docks 大小先天 disjoint**（大站不會整天 < 1、小站絕對流出量也達不到 -50），所以是「**補不到型**」這種獨立的物種、和 Block 4 的三型構成本 dashboard 的 4 類缺車框架（見 Block 4 long_desc 詳解）：\n\n• 本榜單 → **補不到型**（小站、流量小、調度成本高的觀光／郊區終點）\n• Block 4 拆三型 → **黑洞型 / 混合型 / 冷終點型**\n\n**處方**：本榜單站點通常需要重新評估合理性、設計觀光接駁專車補給、或承認這站是觀光交通預算養而非通勤預算養（如坪林旅遊服務中心案例）。\n\n**與線上儀表板的關係**：本指標 ≈ 線上「YouBike 見車率」（`youbike_avail_pct`）的反向，且對方是月度資料、品質較佳。本 block 在這個 dashboard 的角色是 4 類框架中的一類、提供方法論示範。",
			use_case: "鎖定「補不到型」站作為補給策略起點。配合 Block 4 三型，組成 4 類缺車物種框架。",
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
			city: CITY,
			name: "車一去不返排行 × 補車依賴度 ★ 獨家觀點",
			source: SOURCE,
			short_desc:
				`線上儀表板無此指標。淨流出量排行 + 補車依賴度（dispatch_dependency）三類分群：★ 黑洞型／◆ 混合型／○ 冷終點型 [本榜單分布：${
					Object.entries(tierCounts)
						.map(([k, v]) => `${k} ${v}`)
						.join("、") || "—"
				}]`,
			long_desc:
				DEMO_PREFIX +
				"**成因面（本 dashboard 的核心獨家觀點）**：逐筆 snapshot 比對 available_bikes 變化：下降量加總視為借出估計（est_borrow）、上升量視為歸還估計 est_return（含調度卡車補車）。淨流出 = est_return − est_borrow，最負代表「結構性流出 ≫ 歸還」。\n\n**「補車依賴度」分類**（est_return 拆 burst vs steady）：\n• 把每筆 30 分鐘 snapshot 內 +5 以上的回車視為卡車補車特徵（burst）、+5 以下視為市民自然還車（steady）\n• `dispatch_dependency = est_return_burst / est_return`\n• 同樣是「淨流出大」的站，dispatch_dependency 高低代表完全不同的營運狀態：\n\n  ★ **黑洞型** (dep ≥ 0.7)：靠卡車補車撐住、撤補車就崩。例：捷運公館站(3號出口) 0.87、百齡國小 0.86、三張犁 0.78。**處方**：核心通勤動線、應確保補車優先順序，但同時設計返車誘因紓緩根本壓力。\n  ◆ **混合型** (dep 0.4–0.7)：人為補 + 自然回流並存。例：北投運動中心 0.53、市圖總館 0.54、河堤國小 0.61。**處方**：可以微調補車頻次、觀察自然回流是否能擴大。\n  ○ **冷終點型** (dep < 0.4)：沒人補也沒人還、可能已被放棄。例：蘭興公園 0.23、板橋和平公園 0.29。**處方**：不要再加補車預算，重新評估該站存廢、或改為觀光接駁定點補。\n\n**Block 2 vs Block 4 物種對照（誠實版）**：原本想主張「Block 2 ∩ Block 4 對照能找出三類站」，但實證上兩個榜單前 15 名先天 disjoint（小站絕對流出量必然小、無法上 Block 4；大站車量天花板高、無法上 Block 2）。改良後的真正框架是：**Block 2 是一個 universe（補不到型）；Block 4 內部再用 dispatch_dependency 切出黑洞／混合／冷終點三型**，總共 4 種缺車物種、各自不同處方。",
			use_case: "獨家：靠 dispatch_dependency 把『淨流出大』的大站再切成黑洞／混合／冷終點三型，分別對應補車優先、觀察、撤站三種完全不同的營運處方。",
			...TIME_META,
			chart_config: {
				color: ["#fb7185"],
				types: ["BarChart"],
				unit: "輛",
				label_max_length: 16,
				label_max_width: 200,
				categories: imbalanceData.map((d) => d.x),
			},
			chart_data: [{ name: "淨流出量（借出 − 歸還）", data: imbalanceData }],
		},
		{
			id: 9003,
			index: "youbike_heatmap",
			city: CITY,
			name: "全日車量擺盪最大的 25 站 ‧ 時段分布",
			source: SOURCE,
			short_desc: "示範用：全日填充率變化最大的 25 站，看單站「早綠晚紅」或「早紅晚綠」的日間擺盪。跨站車流方向請以線上「YouBike2.0 週間／週末群像」為準",
			long_desc:
				DEMO_PREFIX +
				"色階紅→綠對應 fill_ratio 0%→100%，由上而下排序為「全日 max − min fill_ratio」最大的 25 站。可以看到每站的「日間流動節奏」（早上滿、下午被借空、晚上回流；或反過來）。\n\n**已知方法論瑕疵（誠實揭露）**：cohort 用 max − min fill_ratio 選會偏向小站（22 格站從滿到空 = 100%→0% 的視覺極端值；99 格大站再怎麼借也不容易出現極端），所以實際被選中的站與 Block 2／Block 4 都零重疊。改進方向是改用按 docks 歸一化的指標（std of fill_ratio、IQR）或直接以高流量站（imbalance 前 N 並集）作為 cohort，這項已列入下一步技術債。\n\n**請以線上版為主**：跨站／跨行政區的車流方向，線上「YouBike2.0 週間群像」「YouBike2.0 週末群像」用的是真正的 OD 矩陣交易資料，解析度與穩定性都遠勝本 block。本 block 補的是「**同一站不同時段**」的維度，作為框架示範。",
			use_case: "示範用：辨識單站「早綠晚紅 / 早紅晚綠」的日間擺盪。線上 OD 群像才是看跨站車流方向的權威來源。",
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
			},
			chart_data: heatmap.series,
		},
	];
}

export const YOUBIKE_SHORTAGE_DASHBOARD = {
	index: DASHBOARD_INDEX,
	name: DASHBOARD_NAME,
	icon: DASHBOARD_ICON,
	city: CITY,
};

export async function loadYoubikeShortageComponents() {
	const ds = await loadDataset();
	return buildBlocks(ds);
}
