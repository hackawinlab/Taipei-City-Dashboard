<script setup>
import { computed, onMounted, ref } from "vue";
import DashboardComponent from "../dashboardComponent/DashboardComponent.vue";

const dataset = ref(null);
const error = ref(null);
const selectedCity = ref("All");

onMounted(async () => {
	try {
		const res = await fetch("/data/youbike_hourly_shortage.json", {
			cache: "no-store",
		});
		if (!res.ok) throw new Error(`HTTP ${res.status}`);
		dataset.value = await res.json();
	} catch (err) {
		error.value = err.message || String(err);
	}
});

const cities = computed(() => dataset.value?.cities ?? ["All"]);
const cityLabel = computed(() => {
	switch (selectedCity.value) {
	case "Taipei":
		return "臺北市";
	case "NewTaipei":
		return "新北市";
	default:
		return "雙北";
	}
});

function formatPct(v) {
	if (v == null || Number.isNaN(v)) return "—";
	return `${(v * 100).toFixed(1)}%`;
}

function pickHourlyRow(hour) {
	const h = dataset.value?.summary?.[hour];
	if (!h) return null;
	if (selectedCity.value !== "All") return h[selectedCity.value] ?? null;
	const tp = h.Taipei;
	const nt = h.NewTaipei;
	if (!tp && !nt) return null;
	const station_count = (tp?.station_count ?? 0) + (nt?.station_count ?? 0);
	const empty_stations = (tp?.empty_stations ?? 0) + (nt?.empty_stations ?? 0);
	const low_stations = (tp?.low_stations ?? 0) + (nt?.low_stations ?? 0);
	return {
		station_count,
		empty_stations,
		low_stations,
		empty_ratio: station_count ? empty_stations / station_count : 0,
		low_ratio: station_count ? low_stations / station_count : 0,
	};
}

function formatHour(iso) {
	// "2026-05-01 16:00" -> "16:00"
	return iso?.slice(11, 16) ?? "";
}

// 觀測時段內的高峰值（哪一小時、缺車站最多）
const peakSummary = computed(() => {
	const hours = dataset.value?.hours ?? [];
	if (!hours.length) return null;
	let stationCount = 0;
	let peakEmpty = { hour: "", count: 0, ratio: 0 };
	let peakLow = { hour: "", count: 0, ratio: 0 };
	for (const hour of hours) {
		const row = pickHourlyRow(hour);
		if (!row) continue;
		stationCount = row.station_count;
		if (row.empty_stations > peakEmpty.count) {
			peakEmpty = { hour, count: row.empty_stations, ratio: row.empty_ratio };
		}
		if (row.low_stations > peakLow.count) {
			peakLow = { hour, count: row.low_stations, ratio: row.low_ratio };
		}
	}
	return { stationCount, peakEmpty, peakLow };
});

// Block A：長期缺車站排行（empty_hours，整天有多少小時都缺車）
const blockPersistence = computed(() => {
	const rows = dataset.value?.bar_persistence?.[selectedCity.value] ?? [];
	const hoursObserved = rows[0]?.hours_observed ?? 20;
	const data = rows.slice(0, 20).map((s) => ({
		x: s.station_name,
		y: s.empty_hours,
	}));
	return {
		index: "youbike-shortage-persistence",
		name: `長期缺車站排行（${cityLabel.value}・小站／補不到型）`,
		source: "YouBike 開放資料 ‧ 2026/05/01 單日（demo）",
		time_from: "static",
		update_freq: 1,
		update_freq_unit: "hour",
		short_desc: `這天 ${hoursObserved} 小時中有多少小時平均可借車輛 < 1。前段集中在容量小（22–60 格）的觀光終點站，與下方 Block 4 三型構成 4 類缺車物種`,
		long_desc: "依據觀測時段內每小時的平均可借車輛，計算每站達到缺車門檻的小時數。前段集中在小站（觀光／郊區終點），其車量天花板低、整天都跌破 1 台車門檻最容易達成，因此屬於「補不到型」這個獨立物種。配合 Block 4 三型（黑洞 / 混合 / 冷終點）構成 4 類缺車框架。",
		chart_config: {
			color: ["#ff6b6b"],
			types: ["BarChart"],
			unit: "小時",
			label_max_length: 16,
			label_max_width: 200,
			categories: data.map((d) => d.x),
		},
		chart_data: [
			{
				name: `缺車時數（觀測 ${hoursObserved} 小時內）`,
				data,
			},
		],
		map_config: [],
		map_filter: null,
	};
});

// Block C：站 × 小時 熱力圖
const blockHeatmap = computed(() => {
	const h = dataset.value?.heatmap?.[selectedCity.value];
	const series = h?.series ?? [];
	const categories = h?.categories ?? [];
	return {
		index: "youbike-shortage-heatmap",
		name: `全日車量擺盪最大的 25 站 ‧ 時段分布（${cityLabel.value}）`,
		source: "YouBike 開放資料 ‧ 2026/05/01 單日（demo）",
		time_from: "static",
		update_freq: 1,
		update_freq_unit: "hour",
		short_desc: "示範用：同一站不同時段的擺盪節奏。跨站車流方向請以線上『YouBike2.0 週間／週末群像』OD 矩陣為準",
		chart_config: {
			// 由低 fill_ratio 為「冷紅」、高 fill_ratio 為「綠」漸層
			color: ["#7f1d1d", "#dc2626", "#f97316", "#facc15", "#84cc16", "#16a34a"],
			types: ["HeatmapChart"],
			unit: "%",
			categories,
			hide_summary: true,
			hide_data_labels: true,
		},
		chart_data: series,
		map_config: [],
		map_filter: null,
	};
});

// Block D：empty_ratio / low_ratio 隨時間
const blockTimeline = computed(() => {
	// 簡化為 2 條 low_ratio 線；empty_ratio 全天最高 ~7%、視覺對比小、已收進頂部 KPI 卡片
	const low = dataset.value?.timeline_low ?? [];
	const cityName = (n) =>
		n === "Taipei" ? "臺北市" : n === "NewTaipei" ? "新北市" : n;
	const filtered =
		selectedCity.value === "All"
			? low
			: low.filter((s) => s.name === selectedCity.value);
	const series = filtered.map((s) => ({
		...s,
		name:
			selectedCity.value === "All"
				? `${cityName(s.name)}：低於 20% 容量`
				: "低於 20% 容量",
	}));
	return {
		index: "youbike-shortage-timeline",
		name: `缺車站佔比 ‧ 雙北一日節奏（${cityLabel.value}）`,
		source: "YouBike 開放資料 ‧ 2026/05/01 單日（demo）",
		time_from: "static",
		update_freq: 1,
		update_freq_unit: "hour",
		short_desc: "提醒：勞動節單日樣本，可能反映出遊潮而非通勤潮",
		chart_config: {
			color: ["#ff6b6b", "#60a5fa"],
			types: ["TimelineSeparateChart"],
			unit: "%",
		},
		chart_data: series,
		map_config: [],
		map_filter: null,
	};
});

// Block E：全日借還不對稱排行 — 找出整段時間「流出 ≫ 歸還」的站，調度補車的固定客戶
function depTier(dep) {
	if (dep == null) return { mark: "", label: "未知" };
	if (dep >= 0.7) return { mark: "★ ", label: "黑洞型（卡車撐住）" };
	if (dep >= 0.4) return { mark: "◆ ", label: "混合型" };
	return { mark: "○ ", label: "冷終點型" };
}

const blockImbalance = computed(() => {
	// imbalance 結構升級：{ absolute: [...], per_dock: [...] }；fallback 為舊 list
	const cityImb = dataset.value?.imbalance?.[selectedCity.value] ?? {};
	const rows = Array.isArray(cityImb)
		? cityImb
		: (cityImb.absolute ?? []);
	const sliced = rows.slice(0, 15);
	const data = sliced.map((s) => ({
		x: `${depTier(s.dispatch_dependency).mark}${s.station_name}`,
		y: -s.imbalance,
	}));
	const tierCounts = sliced.reduce((acc, s) => {
		const t = depTier(s.dispatch_dependency).label;
		acc[t] = (acc[t] || 0) + 1;
		return acc;
	}, {});
	const tierBreakdown = Object.entries(tierCounts)
		.map(([k, v]) => `${k} ${v}`)
		.join("、");
	return {
		index: "youbike-shortage-imbalance",
		name: `車一去不返排行 × 補車依賴度（${cityLabel.value}）`,
		source: "YouBike 開放資料 ‧ 2026/05/01 單日（demo）",
		time_from: "static",
		update_freq: 1,
		update_freq_unit: "hour",
		short_desc: `★ 黑洞型 / ◆ 混合型 / ○ 冷終點型 三類分群，配合 Block 2 補不到型構成 4 類缺車物種框架 [本榜單分布：${tierBreakdown || "—"}]`,
		long_desc:
			"成因面（本 dashboard 獨家）：逐筆 snapshot 比對 available_bikes 變化，把 est_return（含調度補車）拆 burst (delta ≥ 5 / 30min) 與 steady，計算 dispatch_dependency = burst / est_return。\n\n• ★ 黑洞型 (dep ≥ 0.7)：靠卡車補車撐住、撤補車就崩\n• ◆ 混合型 (dep 0.4–0.7)：人為補 + 自然回流並存\n• ○ 冷終點型 (dep < 0.4)：沒人補也沒人還、可能已被放棄\n\n本榜單 + Block 2「補不到型」共 4 類缺車物種，各自不同處方。",
		chart_config: {
			color: ["#fb7185"],
			types: ["BarChart"],
			unit: "輛",
			label_max_length: 18,
			label_max_width: 220,
			categories: data.map((d) => d.x),
		},
		chart_data: [{ name: "淨流出量（借出 − 歸還）", data }],
		map_config: [],
		map_filter: null,
	};
});
</script>

<template>
  <div class="shortage-view">
    <div
      v-if="error"
      class="shortage-view-banner shortage-view-error"
    >
      <span>error</span>
      <p>無法載入缺車資料：{{ error }}</p>
    </div>
    <div
      v-else-if="!dataset"
      class="shortage-view-banner shortage-view-loading"
    >
      <div class="spinner" />
      <p>載入缺車資料中…</p>
    </div>
    <template v-else>
      <div class="shortage-view-banner shortage-view-demo">
        <strong>分析框架 demo</strong>
        <p>
          資料樣本：<b>2026/05/01（勞動節 + 週五）02:00–21:00 共 20 小時</b>，無法代表平日／週末／跨日結構。本頁示範方法論，請勿當作現況依據；
          現況請以線上「YouBike 使用情況」「見車率／見位率」為準。獨家價值在 Block「車一去不返」與「兩種缺車物種」對照框架。
        </p>
      </div>
      <header class="shortage-view-header">
        <div class="shortage-view-header-row">
          <label>城市</label>
          <select v-model="selectedCity">
            <option
              v-for="c in cities"
              :key="c"
              :value="c"
            >
              {{ c === "All" ? "雙北合計" : c === "Taipei" ? "臺北市" : "新北市" }}
            </option>
          </select>
        </div>
        <div
          v-if="peakSummary"
          class="shortage-view-header-summary"
        >
          <div>
            <p>觀測站數</p>
            <h3>{{ peakSummary.stationCount }}</h3>
          </div>
          <div>
            <p>高峰無車站（avg &lt; 1）</p>
            <h3>{{ peakSummary.peakEmpty.count }}</h3>
            <small>{{ formatPct(peakSummary.peakEmpty.ratio) }} ‧ {{ formatHour(peakSummary.peakEmpty.hour) }}</small>
          </div>
          <div>
            <p>高峰低於 20% 容量</p>
            <h3>{{ peakSummary.peakLow.count }}</h3>
            <small>{{ formatPct(peakSummary.peakLow.ratio) }} ‧ {{ formatHour(peakSummary.peakLow.hour) }}</small>
          </div>
        </div>
      </header>
      <div class="shortage-view-grid">
        <DashboardComponent
          mode="default"
          :config="blockTimeline"
          :info-btn="false"
          :footer="true"
        />
        <DashboardComponent
          mode="default"
          :config="blockPersistence"
          :info-btn="false"
          :footer="true"
        />
        <DashboardComponent
          mode="default"
          :config="blockHeatmap"
          :info-btn="false"
          :footer="true"
        />
        <DashboardComponent
          mode="default"
          :config="blockImbalance"
          :info-btn="false"
          :footer="true"
        />
      </div>
    </template>
  </div>
</template>

<style scoped lang="scss">
.shortage-view {
	max-height: calc(100vh - 127px);
	max-height: calc(var(--vh) * 100 - 127px);
	overflow-y: auto;
	padding: var(--font-m);

	&-banner {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-height: 50vh;
		color: var(--color-complement-text);

		span {
			font-family: var(--font-icon);
			font-size: 2rem;
			margin-bottom: var(--font-ms);
		}

		.spinner {
			width: 2rem;
			height: 2rem;
			border-radius: 50%;
			border: solid 4px var(--color-border);
			border-top: solid 4px var(--color-highlight);
			animation: spin 0.7s ease-in-out infinite;
			margin-bottom: var(--font-ms);
		}
	}

	&-demo {
		min-height: 0;
		padding: var(--font-ms) var(--font-m);
		margin-bottom: var(--font-m);
		border: 1px solid #f59e0b;
		border-left: 4px solid #f59e0b;
		background-color: rgba(245, 158, 11, 0.08);
		border-radius: 4px;
		align-items: flex-start;
		text-align: left;

		strong {
			color: #f59e0b;
			font-size: var(--font-m);
			margin-bottom: 4px;
		}

		p {
			color: var(--color-normal-text);
			font-size: var(--font-s);
			line-height: 1.5;
			margin: 0;
		}

		b {
			color: #fbbf24;
		}
	}

	&-header {
		background-color: var(--color-component-background);
		border-radius: 5px;
		padding: var(--font-m);
		display: flex;
		flex-direction: column;
		gap: var(--font-ms);
		margin-bottom: var(--font-m);

		&-row {
			display: flex;
			align-items: center;
			gap: 8px;
			color: var(--color-normal-text);
			font-size: var(--font-s);

			select {
				background-color: var(--color-component-background);
				color: var(--color-normal-text);
				border: 1px solid var(--color-border);
				padding: 2px 6px;
				border-radius: 4px;
			}

			input[type="range"] {
				flex: 1;
				accent-color: var(--color-highlight);
			}
		}

		&-spacer {
			margin-left: var(--font-m);
		}

		&-hour {
			color: var(--color-highlight);
			font-variant-numeric: tabular-nums;
			min-width: 7.5rem;
			text-align: right;
		}

		&-summary {
			display: grid;
			grid-template-columns: repeat(3, 1fr);
			gap: 8px;

			div {
				background-color: rgba(255, 255, 255, 0.04);
				border-radius: 4px;
				padding: 8px;
				display: flex;
				flex-direction: column;
				align-items: flex-start;

				p {
					color: var(--color-complement-text);
					font-size: var(--font-s);
					margin-bottom: 2px;
				}

				h3 {
					color: var(--color-normal-text);
					font-size: var(--font-l);
				}

				small {
					color: var(--color-highlight);
					font-size: var(--font-s);
				}
			}
		}
	}

	&-grid {
		display: grid;
		grid-template-columns: 1fr;
		gap: var(--font-s);

		@media (min-width: 1100px) {
			grid-template-columns: 1fr 1fr;
		}
	}
}

@keyframes spin {
	to {
		transform: rotate(360deg);
	}
}
</style>
