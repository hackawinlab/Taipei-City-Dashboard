<script setup>
import { ref, onMounted } from "vue";
import VueApexCharts from "vue3-apexcharts";
import http from "../../router/axios";

const props = defineProps({
	stationUid: { type: String, required: true },
	stationName: { type: String, default: "" },
	city: { type: String, default: "" },
});

const SLOT_COUNT = 96;

const loading = ref(true);
const error = ref(null);
const stationName = ref(props.stationName);

const series = ref([
	{ name: "一般車", data: Array(SLOT_COUNT).fill(0) },
	{ name: "電輔車", data: Array(SLOT_COUNT).fill(0) },
]);

const xCategories = Array.from({ length: SLOT_COUNT }, (_, s) => {
	const h = Math.floor(s / 4);
	const m = (s % 4) * 15;
	return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
});

const chartOptions = ref({
	chart: {
		type: "bar",
		stacked: true,
		toolbar: { show: false },
		zoom: { allowMouseWheelZoom: false },
		animations: { enabled: false },
		fontFamily: "inherit",
		background: "transparent",
		offsetY: 0,
	},
	theme: { mode: "dark" },
	colors: ["#22c55e", "#38bdf8"],
	plotOptions: {
		bar: { horizontal: false, columnWidth: "95%", borderRadius: 0 },
	},
	dataLabels: { enabled: false },
	stroke: { show: false },
	grid: {
		show: true,
		borderColor: "rgba(255,255,255,0.08)",
		strokeDashArray: 3,
		// Top: room for the "車位上限" annotation label that sits above the bars.
		// Bottom: 0 to keep the popup compact between the x-axis title and tail.
		padding: { top: 12, bottom: 0, left: 10, right: 10 },
		xaxis: { lines: { show: false } },
	},
	xaxis: {
		categories: xCategories,
		title: {
			text: "時間 (Asia/Taipei，每 15 分鐘)",
			style: { color: "#9ca3af", fontSize: "10px", fontWeight: 400 },
		},
		labels: {
			style: { colors: "#9ca3af", fontSize: "10px" },
			rotate: 0,
			hideOverlappingLabels: false,
			showDuplicates: false,
			formatter: (val, _, opts) => {
				const idx = opts?.i ?? -1;
				// 96 slots, label every 6 hours: idx 0, 24, 48, 72.
				if (idx === 0) return "00:00";
				if (idx === 24) return "06:00";
				if (idx === 48) return "12:00";
				if (idx === 72) return "18:00";
				return "";
			},
		},
		axisBorder: { show: false },
		axisTicks: { show: false },
		tickPlacement: "between",
	},
	yaxis: {
		title: {
			text: "可借車輛數",
			style: { color: "#9ca3af", fontSize: "10px", fontWeight: 400 },
		},
		labels: {
			style: { colors: "#9ca3af", fontSize: "10px" },
			formatter: (v) => Math.round(v),
		},
	},
	legend: {
		show: true,
		position: "top",
		horizontalAlign: "right",
		labels: { colors: "#d1d5db" },
		markers: { width: 10, height: 10, radius: 2 },
		fontSize: "11px",
		offsetY: -2,
	},
	tooltip: {
		theme: "dark",
		shared: true,
		intersect: false,
		x: { formatter: (_, { dataPointIndex }) => xCategories[dataPointIndex] },
		y: { formatter: (v) => `${v.toFixed(1)} 輛` },
	},
	annotations: { yaxis: [] },
});

onMounted(async () => {
	try {
		const res = await http.get(
			`/commute/youbike/station/${encodeURIComponent(props.stationUid)}/hourly`,
		);
		const d = res.data?.data ?? {};
		stationName.value = d.station_name || stationName.value;
		const available = d.available_bikes ?? Array(SLOT_COUNT).fill(0);
		const electric = d.electric_bikes ?? Array(SLOT_COUNT).fill(0);
		const total = d.total_docks ?? [];
		// Regular = available - electric (clamp to >= 0 to guard against rounding)
		const regular = available.map((a, i) =>
			Math.max(0, +(a - (electric[i] || 0)).toFixed(1)),
		);
		const capacity = total.length ? Math.max(...total) : 0;

		series.value = [
			{ name: "一般車", data: regular },
			{ name: "電輔車", data: electric },
		];

		if (capacity > 0) {
			chartOptions.value = {
				...chartOptions.value,
				annotations: {
					yaxis: [
						{
							y: capacity,
							borderColor: "#f97316",
							strokeDashArray: 4,
							borderWidth: 1.5,
							label: {
								borderWidth: 0,
								style: {
									background: "transparent",
									color: "#f97316",
									fontSize: "10px",
								},
								text: `車位上限 ${capacity}`,
								position: "right",
								offsetX: -8,
								offsetY: -2,
							},
						},
					],
				},
				yaxis: {
					...chartOptions.value.yaxis,
					max: Math.ceil(capacity * 1.15),
				},
			};
		}
	} catch (e) {
		error.value = e?.message || "載入失敗";
	} finally {
		loading.value = false;
	}
});
</script>

<template>
	<div class="youbike-station-popup">
		<div class="youbike-station-popup-header">
			<span class="station-name">{{ stationName || "YouBike 站點" }}</span>
		</div>
		<div
			v-if="loading"
			class="youbike-station-popup-status"
		>
			載入中…
		</div>
		<div
			v-else-if="error"
			class="youbike-station-popup-status error"
		>
			{{ error }}
		</div>
		<VueApexCharts
			v-else
			type="bar"
			height="200"
			width="100%"
			:options="chartOptions"
			:series="series"
		/>
	</div>
</template>

<style scoped lang="scss">
.youbike-station-popup {
	width: 320px;
	max-width: 100%;
	color: var(--color-normal-text, #e5e7eb);
	font-size: var(--font-s, 12px);

	&-header {
		margin: 2px 4px 0 12px;

		.station-name {
			font-weight: 600;
			font-size: 14px;
			color: var(--color-highlight, #22c55e);
		}
	}

	&-status {
		padding: 24px 0;
		text-align: center;
		color: var(--color-complement-text, #9ca3af);

		&.error {
			color: #ef4444;
		}
	}
}
</style>
