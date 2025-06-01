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
			type: "x",
		},
	},
	colors: [...props.chart_config.color],
	dataLabels: {
		enabled: false,
	},
	fill: {
		type: "gradient",
		gradient: {
			shadeIntensity: 1,
			opacityFrom: 0.7,
			opacityTo: 0.9,
			stops: [0, 100],
		},
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
		hover: {
			size: 5,
		},
		size: 3,
		strokeWidth: 0,
	},
	stroke: {
		colors: [...props.chart_config.color],
		curve: "smooth",
		show: true,
		width: 2,
	},
	tooltip: {
		// The class "chart-tooltip" could be edited in /assets/styles/chartStyles.css
		custom: function ({ series, seriesIndex, dataPointIndex, w }) {
			const dataPoint = w.config.series[seriesIndex].data[dataPointIndex];
			const isTimeSeries = typeof dataPoint === "object" && dataPoint.x;

			return (
				'<div class="chart-tooltip">' +
				"<h6>" +
				`${
					isTimeSeries
						? parseTime(dataPoint.x)
						: w.globals.labels[dataPointIndex]
				}` +
				`${
					props.series.length > 1
						? " - " + w.globals.seriesNames[seriesIndex]
						: ""
				}` +
				"</h6>" +
				"<span>" +
				`${
					isTimeSeries
						? dataPoint.y
						: series[seriesIndex][dataPointIndex]
				} ${props.chart_config.unit}` +
				"</span>" +
				"</div>"
			);
		},
		followCursor: true,
	},
	xaxis: {
		type: props.chart_config.categories ? "category" : "datetime",
		categories: props.chart_config.categories || [],
		title: {
			text: "時間",
			style: {
				color: "var(--color-complement-text)",
			},
		},
		labels: {
			style: {
				colors: "var(--color-complement-text)",
			},
			datetimeUTC: false,
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
			text: props.chart_config.unit || "數值",
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
			const xValue =
				typeof dataPoint === "object" && dataPoint.x
					? dataPoint.x
					: config.w.globals.labels[config.dataPointIndex];

			emits(
				"filterByParam",
				props.map_filter,
				props.map_config,
				xValue,
				config.w.globals.seriesNames[config.seriesIndex]
			);
		}
		// Supports filtering by xAxis
		else if (props.map_filter.mode === "byLayer") {
			const dataPoint =
				config.w.config.series[config.seriesIndex].data[
					config.dataPointIndex
				];
			const xValue =
				typeof dataPoint === "object" && dataPoint.x
					? dataPoint.x
					: config.w.globals.labels[config.dataPointIndex];

			emits("filterByLayer", props.map_config, xValue);
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

function parseTime(time) {
	return time
		.replace("T00:00:00+08:00", " ")
		.replace("T", " ")
		.replace("+08:00", "");
}
</script>

<template>
	<div v-if="activeChart === 'AreaChart'">
		<VueApexCharts
			width="100%"
			height="260px"
			type="area"
			:options="chartOptions"
			:series="series"
			@data-point-selection="handleDataSelection"
		/>
	</div>
</template>
