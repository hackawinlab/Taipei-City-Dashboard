<!-- Developed by Taipei Urban Intelligence Center 2023-2024-->

<script setup>
import { ref, computed } from "vue";
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

// Parse series data for population pyramid (negative values for male)
const parsedSeries = computed(() => {
	if (!props.series || props.series.length < 2) return [];

	// 直接使用所有數據，不需要選擇特定年份
	const maleData = props.series[0].data || [];
	const femaleData = props.series[1].data || [];

	return [
		{
			name: props.series[0].name, // Male
			data: maleData.map((value) => -Math.abs(value)), // Negative values for left side
		},
		{
			name: props.series[1].name, // Female
			data: femaleData, // Positive values for right side
		},
	];
});

const chartOptions = ref({
	chart: {
		type: "bar",
		stacked: true,
		toolbar: {
			show: false,
		},
	},
	colors: [...props.chart_config.color],
	dataLabels: {
		enabled: false,
	},
	grid: {
		show: false,
	},
	legend: {
		show: true,
		position: "top",
		horizontalAlign: "center",
		offsetY: 10,
	},
	plotOptions: {
		bar: {
			borderRadius: 2,
			horizontal: true,
			barHeight: "80%",
		},
	},
	stroke: {
		colors: ["#282a2c"],
		show: true,
		width: 1,
	},
	tooltip: {
		custom: function ({ series, seriesIndex, dataPointIndex, w }) {
			const value = Math.abs(series[seriesIndex][dataPointIndex]);
			const seriesName = w.globals.seriesNames[seriesIndex];
			const category = props.chart_config.categories[dataPointIndex];

			return (
				'<div class="chart-tooltip">' +
				"<h6>" +
				category +
				" - " +
				seriesName +
				"</h6>" +
				"<span>" +
				value +
				` ${props.chart_config.unit}` +
				"</span>" +
				"</div>"
			);
		},
		followCursor: true,
	},
	xaxis: {
		type: "numeric",
		labels: {
			formatter: function (val) {
				return Math.abs(val).toLocaleString();
			},
		},
		axisBorder: {
			show: false,
		},
		axisTicks: {
			show: false,
		},
	},
	yaxis: {
		labels: {
			show: true,
		},
		categories: props.chart_config.categories || [], // 使用所有類別
	},
});

const chartHeight = computed(() => {
	// 根據數據量動態調整高度
	const dataLength = props.chart_config.categories?.length || 1;
	return `${Math.max(200, dataLength * 30)}px`;
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
			emits(
				"filterByParam",
				props.map_filter,
				props.map_config,
				config.w.globals.labels[config.dataPointIndex],
				config.w.globals.seriesNames[config.seriesIndex]
			);
		}
		// Supports filtering by xAxis
		else if (props.map_filter.mode === "byLayer") {
			emits(
				"filterByLayer",
				props.map_config,
				config.w.globals.labels[config.dataPointIndex]
			);
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
	<div v-if="activeChart === 'PopulationPyramid'" class="populationPyramid">
		<!-- Population Pyramid Chart -->
		<VueApexCharts
			type="bar"
			width="100%"
			:height="chartHeight"
			:options="chartOptions"
			:series="parsedSeries"
			@data-point-selection="handleDataSelection"
		/>
	</div>
</template>

<style scoped lang="scss">
.populationPyramid {
	position: relative;
	max-height: 100%;
	color: var(--color-normal-text);
	overflow-y: auto;
}
</style>
