/**
 * 公車壅塞時序 — virtual dashboard 註冊。
 *
 * Pipeline：BE cron → public.bus_congestion_history (dashboard DB) →
 *            matview public.bus_congestion_history_segments →
 *            BE /commute/bus-congestion/{routes,timeline} →
 *            FE BusCongestionTimeline component。
 *
 * 仿 youbikeShortageBlocks 模式:不走 manager DB query_charts，直接由
 * FE store 組 dashboard component 物件。BusCongestionTimeline 元件自行
 * fetch API 並維護 route/state，所以 chart_data / chart_config 給空殼即可。
 */

const DASHBOARD_ICON = "directions_bus";
const SOURCE = "雙北公車 ETA / 路線 shape";

const TIME_META = {
	time_from: "static",
	time_to: null,
	update_freq: 30,
	update_freq_unit: "min",
	history_data: false,
	links: null,
	tags: [],
	contributors: [],
	map_config: [],
	map_filter: null,
	history_config: null,
};

export const BUS_CONGESTION_DASHBOARDS = [
	{
		index: "bus-congestion-timeline-taipei",
		name: "公車壅塞時序",
		icon: DASHBOARD_ICON,
		city: "taipei",
		sliceCities: ["taipei"],
	},
	{
		index: "bus-congestion-timeline-metrotaipei",
		name: "公車壅塞時序",
		icon: DASHBOARD_ICON,
		city: "metrotaipei",
		// metrotaipei: BE matview 僅含臺北市,UI 顯示資料其實是台北市,
		// 仍保留兩個 dashboard 入口以對齊 sidebar 雙北/臺北分區。
		sliceCities: ["metrotaipei"],
	},
];

const DASHBOARD_BY_INDEX = new Map(
	BUS_CONGESTION_DASHBOARDS.map((d) => [d.index, d]),
);

export function isBusCongestionTimelineIndex(index) {
	return DASHBOARD_BY_INDEX.has(index);
}

export function getBusCongestionTimelineDashboard(index) {
	return DASHBOARD_BY_INDEX.get(index);
}

function buildBlock(sliceCity) {
	return {
		id: 9101,
		index: "bus_congestion_timeline",
		city: sliceCity,
		name: "公車壅塞時序",
		source: SOURCE,
		short_desc:
			"以 30 分鐘間隔切片,顯示路段壅塞等級隨時間的分布變化。",
		long_desc:
			"資料源:`bus_congestion_history_segments` (dashboard DB)。BE 從 `bus_congestion_history` 與 `bus_congestion_segment_dim` join 出每個路段在每個 30 分鐘 snapshot 的壅塞 label,前端依等級堆疊呈現。Demo 範圍為 2026-05-02 12:30~19:30(台灣時間)共 15 個 snapshot。`無資料` 標籤已在 BE 排除。",
		use_case:
			"觀察特定時段哪段路線壅塞最嚴重、用於後續調度決策或路線優先級規劃。",
		...TIME_META,
		chart_config: {
			color: ["#22c55e", "#eab308", "#f97316", "#ef4444", "#7f1d1d"],
			types: ["BusCongestionTimeline"],
			unit: "段",
		},
		// chart_data 由 BusCongestionTimeline 元件內部 fetch，給空陣列當 placeholder
		chart_data: [],
	};
}

export async function loadBusCongestionTimelineComponents(index) {
	const dashboard = DASHBOARD_BY_INDEX.get(index);
	if (!dashboard) {
		throw new Error(`Unknown bus congestion dashboard index: ${index}`);
	}
	return dashboard.sliceCities.map((sliceCity) => buildBlock(sliceCity));
}
