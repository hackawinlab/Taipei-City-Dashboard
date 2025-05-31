<!-- Developed by Taipei Urban Intelligence Center 2023-2024-->

<script setup>
import { ref } from "vue";
import VueApexCharts from "vue3-apexcharts";

const props = defineProps([
	"chart_config",
	"activeChart",
	"series",
	"map_config",
	"map_filter",
	"map_filter_on",
]);

const emits = defineEmits([
	"filterByParam",
	"filterByLayer",
	"clearByParamFilter",
	"clearByLayerFilter",
	"fly",
]);

const chartOptions = ref({
	chart: {
		toolbar: {
			show: false,
		},
		zoom: {
			enabled: true,
			type: "xy",
		},
	},
	colors: [...props.chart_config.color],
	dataLabels: {
		enabled: false,
	},
	grid: {
		show: true,
		borderColor: "#444",
		strokeDashArray: 3,
		xaxis: {
			lines: {
				show: true,
			},
		},
		yaxis: {
			lines: {
				show: true,
			},
		},
	},
	legend: {
		show: props.series.length > 1 ? true : false,
	},
	markers: {
		size: 6,
		strokeWidth: 2,
		strokeColors: ["#282a2c"],
		hover: {
			size: 8,
		},
	},
	stroke: {
		show: false,
	},
	tooltip: {
		// The class "chart-tooltip" could be edited in /assets/styles/chartStyles.css
		custom: function ({ seriesIndex, dataPointIndex, w }) {
			const dataPoint = w.config.series[seriesIndex].data[dataPointIndex];
			return (
				'<div class="chart-tooltip">' +
				"<h6>" +
				`${
					props.series.length > 1
						? w.globals.seriesNames[seriesIndex]
						: "數據點"
				}` +
				"</h6>" +
				"<span>" +
				`X: ${dataPoint.x}` +
				"</span><br>" +
				"<span>" +
				`Y: ${dataPoint.y} ${props.chart_config.unit}` +
				"</span>" +
				"</div>"
			);
		},
		followCursor: true,
	},
	xaxis: {
		type: "numeric",
		title: {
			text: "X軸",
			style: {
				color: "var(--color-complement-text)",
			},
		},
		labels: {
			style: {
				colors: "var(--color-complement-text)",
			},
		},
		axisBorder: {
			color: "#555",
		},
		axisTicks: {
			color: "#555",
		},
	},
	yaxis: {
		title: {
			text: props.chart_config.unit || "Y軸",
			style: {
				color: "var(--color-complement-text)",
			},
		},
		labels: {
			style: {
				colors: "var(--color-complement-text)",
			},
			formatter: function (val) {
				return val.toFixed(1);
			},
		},
	},
});

const selectedIndex = ref(null);

function handleDataSelection(_e, _chartContext, config) {
	if (!props.map_filter || !props.map_filter_on) {
		return;
	}
	if (
		`${config.dataPointIndex}-${config.seriesIndex}` !== selectedIndex.value
	) {
		// Supports filtering by xAxis + yAxis
		if (props.map_filter.mode === "byParam") {
			const dataPoint =
				config.w.config.series[config.seriesIndex].data[
					config.dataPointIndex
				];
			emits(
				"filterByParam",
				props.map_filter,
				props.map_config,
				dataPoint.x,
				config.w.globals.seriesNames[config.seriesIndex]
			);
		}
		// Supports filtering by xAxis
		else if (props.map_filter.mode === "byLayer") {
			const dataPoint =
				config.w.config.series[config.seriesIndex].data[
					config.dataPointIndex
				];
			emits("filterByLayer", props.map_config, dataPoint.x);
		}
		selectedIndex.value = `${config.dataPointIndex}-${config.seriesIndex}`;
	} else {
		if (props.map_filter.mode === "byParam") {
			emits("clearByParamFilter", props.map_config);
		} else if (props.map_filter.mode === "byLayer") {
			emits("clearByLayerFilter", props.map_config);
		}
		selectedIndex.value = null;
	}
}
</script>

<template>
	<div v-if="activeChart === 'ScatterChart'">
		<VueApexCharts
			width="100%"
			height="260px"
			type="scatter"
			:options="chartOptions"
			:series="series"
			@data-point-selection="handleDataSelection"
		/>
	</div>
</template>
