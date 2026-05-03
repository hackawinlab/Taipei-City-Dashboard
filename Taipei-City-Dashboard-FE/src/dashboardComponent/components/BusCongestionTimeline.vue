<!-- BusCongestionTimeline — DB-backed stacked-column timeseries of
     公車壅塞分布。Mirrors the YouBikeTimeMap pattern: a custom chart
     component that owns its own state and fetches from /commute/...,
     so we don't need to round-trip through manager DB query_charts. -->

<script setup>
import { computed, ref, watch } from "vue";
import VueApexCharts from "vue3-apexcharts";
import http from "../../router/axios";

const props = defineProps([
	"chart_config",
	"activeChart",
	"activeCity",
	"series",
	"map_config",
	"map_filter",
	"map_filter_on",
]);

// metrotaipei intentionally falls back to taipei in BE (matview only has 台北市
// edge history). Surface this in the dropdown UX so users aren't surprised.
const cityParam = computed(() => (props.activeCity === "metrotaipei" ? "metrotaipei" : "taipei"));
const showMetroNote = computed(() => props.activeCity === "metrotaipei");

const routes = ref([]);
const selectedRoute = ref("");
const categories = ref([]);
const series = ref([]);
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
	colors: series.value.map((s) => SEVERITY_COLORS[s.name] || "#888"),
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
			params: { city: cityParam.value },
		});
		routes.value = res.data.data || [];
	} catch (e) {
		routes.value = [];
	}
}

async function loadTimeline() {
	loading.value = true;
	errMsg.value = "";
	try {
		const res = await http.get("/commute/bus-congestion/timeline", {
			params: { city: cityParam.value, route_name: selectedRoute.value },
		});
		categories.value = res.data.categories || [];
		series.value = res.data.series || [];
	} catch (e) {
		errMsg.value = "載入失敗";
		categories.value = [];
		series.value = [];
	} finally {
		loading.value = false;
	}
}

watch(
	cityParam,
	() => {
		selectedRoute.value = "";
		loadRoutes();
		loadTimeline();
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
			<select v-model="selectedRoute" class="bus-timeline-route">
				<option value="">全市</option>
				<option v-for="r in routes" :key="r" :value="r">{{ r }}</option>
			</select>
			<span v-if="showMetroNote" class="bus-timeline-note">
				※ 目前歷史 matview 僅含臺北市,顯示資料為臺北市
			</span>
		</div>
		<div v-if="loading" class="bus-timeline-status">載入中…</div>
		<div v-else-if="errMsg" class="bus-timeline-status err">{{ errMsg }}</div>
		<div v-else-if="!categories.length" class="bus-timeline-status">無資料</div>
		<VueApexCharts
			v-else
			type="bar"
			height="100%"
			:options="chartOptions"
			:series="series"
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

.bus-timeline-note {
	font-size: 0.75rem;
	color: var(--color-secondary-text, #80868b);
}

.bus-timeline-status {
	flex: 1;
	display: flex;
	align-items: center;
	justify-content: center;
	color: var(--color-secondary-text, #80868b);
	font-size: 0.9rem;

	&.err {
		color: var(--color-warning, #ef4444);
	}
}
</style>
