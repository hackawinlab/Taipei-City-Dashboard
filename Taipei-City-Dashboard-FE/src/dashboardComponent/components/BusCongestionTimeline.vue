<!-- BusCongestionTimeline — DB-backed stacked-column timeseries of
     公車壅塞分布。Mirrors the YouBikeTimeMap pattern: a custom chart
     component that owns its own state and fetches from /commute/...,
     so we don't need to round-trip through manager DB query_charts.

     The component owns a local 台北 / 雙北 toggle: sidebar entry sets
     the initial scope, but users can switch in-place without navigating
     dashboards. BE returns a `data_note` whenever the matview has no
     rows for the selected route (e.g. 新北 routes like 275 — they show
     up in the dropdown but have no edge history yet). -->

<script setup>
import { computed, ref, watch } from "vue";
import VueApexCharts from "vue3-apexcharts";
import http from "../../router/axios";

const props = defineProps([
	"chart_config",
	"activeChart",
	"activeCity",
	"map_config",
	"map_filter",
	"map_filter_on",
]);

const cityScope = ref(props.activeCity === "metrotaipei" ? "metrotaipei" : "taipei");

const routes = ref([]);
const selectedRoute = ref("");
const categories = ref([]);
const timelineSeries = ref([]);
const dataNote = ref("");
const loading = ref(false);
const errMsg = ref("");

const SEVERITY_COLORS = {
	"暢通": "#22c55e",
	"輕微": "#eab308",
	"中度": "#f97316",
	"嚴重": "#ef4444",
	"極嚴重": "#7f1d1d",
};

const chartOptions = computed(() => ({
	chart: {
		stacked: true,
		toolbar: { show: false },
		zoom: { allowMouseWheelZoom: false },
		background: "transparent",
	},
	colors: timelineSeries.value.map((s) => SEVERITY_COLORS[s.name] || "#888"),
	dataLabels: { enabled: false },
	grid: { show: false },
	legend: { show: true, position: "bottom" },
	plotOptions: { bar: { borderRadius: 3 } },
	stroke: { colors: ["#282a2c"], show: true, width: 1 },
	xaxis: {
		categories: categories.value,
		axisBorder: { show: false },
		axisTicks: { show: false },
		labels: { style: { colors: "#a1a5a9" } },
	},
	yaxis: {
		labels: { style: { colors: "#a1a5a9" } },
	},
	tooltip: {
		custom: ({ series: s, seriesIndex, dataPointIndex, w }) =>
			`<div class="chart-tooltip">` +
			`<h6>${w.globals.labels[dataPointIndex]} ・ ${w.globals.seriesNames[seriesIndex]}</h6>` +
			`<span>${s[seriesIndex][dataPointIndex]} 段</span>` +
			`</div>`,
	},
}));

async function loadRoutes() {
	try {
		const res = await http.get("/commute/bus-congestion/routes", {
			params: { city: cityScope.value },
		});
		routes.value = res.data.data || [];
	} catch {
		routes.value = [];
	}
}

async function loadTimeline() {
	loading.value = true;
	errMsg.value = "";
	try {
		const res = await http.get("/commute/bus-congestion/timeline", {
			params: { city: cityScope.value, route_name: selectedRoute.value },
		});
		categories.value = res.data.categories || [];
		timelineSeries.value = res.data.series || [];
		dataNote.value = res.data.data_note || "";
	} catch {
		errMsg.value = "載入失敗";
		categories.value = [];
		timelineSeries.value = [];
		dataNote.value = "";
	} finally {
		loading.value = false;
	}
}

// Reset selectedRoute on city change; the selectedRoute watcher then
// triggers the single loadTimeline call (avoids double-fetch on switch).
watch(
	cityScope,
	() => {
		loadRoutes();
		if (selectedRoute.value !== "") {
			selectedRoute.value = "";
		} else {
			loadTimeline();
		}
	},
	{ immediate: true },
);

watch(selectedRoute, () => {
	loadTimeline();
});
</script>

<template>
  <div class="bus-timeline">
    <div class="bus-timeline-header">
      <div
        class="bus-timeline-city"
        role="group"
        aria-label="城市範圍"
      >
        <button
          type="button"
          :class="{ active: cityScope === 'taipei' }"
          @click="cityScope = 'taipei'"
        >
          台北
        </button>
        <button
          type="button"
          :class="{ active: cityScope === 'metrotaipei' }"
          @click="cityScope = 'metrotaipei'"
        >
          雙北
        </button>
      </div>
      <select
        v-model="selectedRoute"
        class="bus-timeline-route"
      >
        <option value="">
          全市
        </option>
        <option
          v-for="r in routes"
          :key="r"
          :value="r"
        >
          {{ r }}
        </option>
      </select>
    </div>
    <div
      v-if="loading"
      class="bus-timeline-status"
    >
      載入中…
    </div>
    <div
      v-else-if="errMsg"
      class="bus-timeline-status err"
    >
      {{ errMsg }}
    </div>
    <div
      v-else-if="!categories.length"
      class="bus-timeline-status"
    >
      {{ dataNote || "無資料" }}
    </div>
    <VueApexCharts
      v-else
      type="bar"
      height="100%"
      :options="chartOptions"
      :series="timelineSeries"
    />
  </div>
</template>

<style scoped lang="scss">
.bus-timeline {
	display: flex;
	flex-direction: column;
	height: 100%;
	width: 100%;
}

.bus-timeline-header {
	display: flex;
	align-items: center;
	gap: 0.75rem;
	padding-bottom: 0.5rem;
}

.bus-timeline-city {
	display: inline-flex;
	border: 1px solid var(--color-border, #383a3c);
	border-radius: 4px;
	overflow: hidden;

	button {
		background: transparent;
		color: var(--color-secondary-text, #80868b);
		border: 0;
		padding: 0.25rem 0.7rem;
		font-size: 0.85rem;
		cursor: pointer;
		transition: background 0.15s, color 0.15s;

		& + button {
			border-left: 1px solid var(--color-border, #383a3c);
		}

		&.active {
			background: var(--color-highlight, #3b82f6);
			color: #fff;
		}

		&:not(.active):hover {
			background: var(--color-component-background, #1f2123);
			color: var(--color-normal-text, #c1c5c9);
		}
	}
}

.bus-timeline-route {
	background: var(--color-component-background, #1f2123);
	color: var(--color-normal-text, #c1c5c9);
	border: 1px solid var(--color-border, #383a3c);
	border-radius: 4px;
	padding: 0.25rem 0.5rem;
	font-size: 0.85rem;
	min-width: 140px;
	cursor: pointer;
}

.bus-timeline-status {
	flex: 1;
	display: flex;
	align-items: center;
	justify-content: center;
	color: var(--color-secondary-text, #80868b);
	font-size: 0.9rem;
	text-align: center;
	padding: 0 1rem;

	&.err {
		color: var(--color-warning, #ef4444);
	}
}
</style>
