<script setup>
import { computed } from "vue";
import VueApexCharts from "vue3-apexcharts";

const props = defineProps([
	"chart_config",
	"activeChart",
	"series",
	"map_config",
	"map_filter",
	"map_filter_on",
]);

const chartOptions = computed(() => ({
	chart: {
		offsetY: 8,
		toolbar: { show: false },
		zoom: { enabled: true, type: "xy" },
	},
	colors: [...(props.chart_config.color || ["#ff6b6b", "#ffd166"])],
	dataLabels: { enabled: false },
	grid: { show: true, borderColor: "#3a3a3a", strokeDashArray: 3 },
	legend: {
		show: (props.series || []).length > 1,
		labels: { colors: "#bbbbbb" },
	},
	markers: {
		strokeWidth: 0,
		hover: { sizeOffset: 2 },
	},
	tooltip: {
		custom: function ({ seriesIndex, dataPointIndex, w }) {
			const point = w.config.series[seriesIndex].data[dataPointIndex];
			const meta = point?.meta || {};
			const name = meta.name ?? `${point.x}, ${point.y}`;
			const fill = meta.fill_ratio != null
				? `${(meta.fill_ratio * 100).toFixed(0)}%`
				: "—";
			const docks = meta.total_docks ?? "—";
			return (
				'<div class="chart-tooltip">' +
				`<h6>${name}</h6>` +
				`<span>填充率 ${fill} ‧ 車格 ${docks}</span>` +
				"</div>"
			);
		},
	},
	xaxis: {
		type: "numeric",
		tickAmount: 6,
		decimalsInFloat: 3,
		min: props.chart_config.x_range?.[0],
		max: props.chart_config.x_range?.[1],
		labels: { style: { colors: "#888" } },
		title: { text: "經度", style: { color: "#888" } },
	},
	yaxis: {
		tickAmount: 6,
		decimalsInFloat: 3,
		min: props.chart_config.y_range?.[0],
		max: props.chart_config.y_range?.[1],
		labels: { style: { colors: "#888" } },
		title: { text: "緯度", style: { color: "#888" } },
	},
}));

</script>

<template>
  <div v-if="activeChart === 'ScatterChart'">
    <VueApexCharts
      width="100%"
      height="360px"
      type="scatter"
      :options="chartOptions"
      :series="series"
    />
  </div>
</template>
