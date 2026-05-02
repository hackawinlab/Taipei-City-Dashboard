<!-- Food Safety Early Warning PoC — 違規統計摘要（ColumnChart 包裝） -->

<script setup>
import { computed, ref } from "vue";
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
		stacked: true,
		toolbar: { show: false },
		zoom: { allowMouseWheelZoom: false },
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
		horizontalAlign: "left",
		offsetX: 4,
	},
	plotOptions: {
		bar: {
			borderRadius: 4,
			dataLabels: { hideOverflowingLabels: false },
		},
	},
	stroke: {
		colors: ["#282a2c"],
		show: true,
		width: 2,
	},
	tooltip: {
		custom: function ({ series, seriesIndex, dataPointIndex, w }) {
			return (
				'<div class="chart-tooltip">' +
					"<h6>" +
						w.globals.labels[dataPointIndex] +
						" - " + w.globals.seriesNames[seriesIndex] +
					"</h6>" +
					"<span>" +
						series[seriesIndex][dataPointIndex] +
						" " + props.chart_config.unit +
					"</span>" +
				"</div>"
			);
		},
	},
	xaxis: {
		axisBorder: { show: false },
		axisTicks: { show: false },
		labels: { offsetY: 2 },
		type: "category",
	},
});

const selectedIndex = ref(null);

function handleDataSelection(_e, _chartContext, config) {
	if (!props.map_filter || !props.map_filter_on) return;

	const key = `${config.dataPointIndex}-${config.seriesIndex}`;
	if (key !== selectedIndex.value) {
		if (props.map_filter.mode === "byParam") {
			emits(
				"filterByParam",
				props.map_filter,
				props.map_config,
				config.w.globals.labels[config.dataPointIndex],
				config.w.globals.seriesNames[config.seriesIndex]
			);
		} else if (props.map_filter.mode === "byLayer") {
			emits(
				"filterByLayer",
				props.map_config,
				config.w.globals.labels[config.dataPointIndex]
			);
		}
		selectedIndex.value = key;
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
  <div
    v-if="activeChart === 'ColumnChart'"
    class="foodsafetyviolation"
  >
    <VueApexCharts
      type="bar"
      height="230px"
      width="100%"
      :options="chartOptions"
      :series="series"
      @data-point-selection="handleDataSelection"
    />
  </div>
</template>

<style scoped lang="scss">
.foodsafetyviolation {
	width: 100%;
	height: 100%;
	overflow: auto;
	position: relative;
}
</style>
