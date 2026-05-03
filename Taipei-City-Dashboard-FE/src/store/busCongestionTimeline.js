/**
 * 公車壅塞時序 — dashboard component block builder。
 *
 * Pipeline:BE cron → public.bus_congestion_history (dashboard DB) →
 *           matview public.bus_congestion_history_segments →
 *           BE /commute/bus-congestion/{routes,timeline} →
 *           BusCongestionTimeline.vue。
 *
 * 不走 virtual dashboard。改由 contentStore 在載入 dashboard 時,
 * 若 BE 回的 components 裡含「bus_congestion_layer」(公車 ETA 壅塞偵測),
 * 就在後面注入這個元件,跟它並排顯示。
 *
 * 用 component 判斷而非 dashboard index 名稱 — 因為 manager DB 裡
 * smart_commute_taipei 同時掛在 台北 / 雙北 兩個 group,單看 index
 * 沒法分辨當前 city。
 *
 * BusCongestionTimeline.vue 自己 fetch BE,所以 chart_data 給空 placeholder。
 * `_virtual: true` 旗標讓 contentStore 的 chart-fetch loop 跳過,避免
 * /component/9101/chart 打出 404 雜訊。
 */

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

export const BUS_CONGESTION_LAYER_INDEX = "bus_congestion_layer";
export const BUS_CONGESTION_TIMELINE_INDEX = "bus_congestion_timeline";

export function buildBusCongestionTimelineBlock(city) {
	return {
		id: 9101,
		index: BUS_CONGESTION_TIMELINE_INDEX,
		_virtual: true,
		city,
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
		chart_data: [],
	};
}

// 判斷此 dashboard 是否該注入 timeline 元件。
// 規則:BE 回的 components 裡含 bus_congestion_layer (id 4 / index 'bus_congestion_layer')。
export function shouldInjectBusTimeline(components) {
	if (!Array.isArray(components)) return false;
	return components.some((c) => c?.index === BUS_CONGESTION_LAYER_INDEX);
}
