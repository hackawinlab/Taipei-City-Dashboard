<script setup>
import { ref, onMounted } from "vue";
import VueApexCharts from "vue3-apexcharts";
import http from "../../router/axios";

const props = defineProps({
	stationUid: { type: String, required: true },
	stationName: { type: String, default: "" },
	city: { type: String, default: "" },
});

const loading = ref(true);
const error = ref(null);
const stationName = ref(props.stationName);

const series = ref([{ name: "可借車輛", data: Array(24).fill(0) }]);

const chartOptions = ref({
	chart: {
		type: "bar",
		toolbar: { show: false },
		zoom: { allowMouseWheelZoom: false },
		animations: { enabled: false },
		fontFamily: "inherit",
		background: "transparent",
	},
	theme: { mode: "dark" },
	colors: ["#22c55e"],
	plotOptions: {
		bar: { horizontal: false, columnWidth: "70%", borderRadius: 2 },
	},
	dataLabels: { enabled: false },
	stroke: { show: false },
	grid: {
		show: true,
		borderColor: "rgba(255,255,255,0.08)",
		strokeDashArray: 3,
		padding: { left: 10, right: 10 },
		xaxis: { lines: { show: false } },
	},
	xaxis: {
		categories: Array.from({ length: 24 }, (_, h) =>
			h % 3 === 0 ? `${String(h).padStart(2, "0")}` : "",
		),
		title: {
			text: "小時 (Asia/Taipei)",
			style: { color: "#9ca3af", fontSize: "10px", fontWeight: 400 },
		},
		labels: { style: { colors: "#9ca3af", fontSize: "10px" } },
		axisBorder: { show: false },
		axisTicks: { show: false },
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
	legend: { show: false },
	tooltip: {
		theme: "dark",
		x: { formatter: (_, { dataPointIndex }) => `${dataPointIndex}:00` },
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
		const available = d.available_bikes ?? Array(24).fill(0);
		const total = d.total_docks ?? [];
		const capacity = total.length ? Math.max(...total) : 0;

		series.value = [{ name: "可借車輛", data: available }];

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
			<span
				v-if="city"
				class="station-city"
			>
				{{ city === "Taipei" ? "台北市" : "新北市" }}
			</span>
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
			height="220"
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
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		margin: 6px 4px 8px 12px;
		gap: 8px;

		.station-name {
			font-weight: 600;
			font-size: 14px;
			color: var(--color-highlight, #22c55e);
		}
		.station-city {
			font-size: 11px;
			color: var(--color-complement-text, #9ca3af);
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
