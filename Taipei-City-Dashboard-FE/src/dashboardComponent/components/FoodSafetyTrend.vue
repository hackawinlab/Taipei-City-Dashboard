<!-- Food Safety Early Warning PoC — 食安貼文趨勢（TimelineSeparateChart 包裝） -->

<script setup>
import { ref, watch } from "vue";
import VueApexCharts from "vue3-apexcharts";

const props = defineProps([
	"chart_config",
	"activeChart",
	"series",
	"map_config",
	"map_filter",
	"map_filter_on",
]);

// 本地複製避免污染原始 series
const localSeries = ref(JSON.parse(JSON.stringify(props.series)));

const chartOptions = ref({
	chart: {
		toolbar: {
			show: false,
		},
		zoom: {
			enabled: false,
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
		show: props.series.length > 1,
	},
	markers: {
		hover: { size: 5 },
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
		custom: function ({ series, seriesIndex, dataPointIndex, w }) {
			return (
				'<div class="chart-tooltip">' +
					"<h6>" +
						w.globals.seriesNames[seriesIndex] +
					"</h6>" +
					"<h6>" +
						(w.globals.categoryLabels[dataPointIndex] || w.globals.labels[dataPointIndex]) +
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
		type: "datetime",
		labels: {
			datetimeFormatter: {
				year: "yyyy",
				month: "MM/dd",
				day: "MM/dd",
				hour: "HH:mm",
			},
		},
	},
	yaxis: {
		show: false,
	},
	annotations: {
		// 標示高峰預警區間
		xaxis: [
			{
				x: new Date("2026-04-28").getTime(),
				borderColor: "#E74C3C",
				label: {
					text: "大安區食安群聚",
					style: { color: "#fff", background: "#E74C3C", fontSize: "10px" },
				},
			},
		],
	},
});

watch(
	() => props.series,
	(newSeries) => {
		localSeries.value = JSON.parse(JSON.stringify(newSeries));
	}
);
</script>

<template>
  <div
    v-if="activeChart === 'TimelineSeparateChart'"
    class="foodsafetytrend"
  >
    <!-- 說明標籤 -->
    <div class="foodsafetytrend-labels">
      <span
        v-for="(s, i) in series"
        :key="s.name"
        class="foodsafetytrend-label"
        :style="{ borderLeftColor: chart_config.color[i] }"
      >
        {{ s.name }}
      </span>
    </div>

    <VueApexCharts
      type="line"
      height="190px"
      width="100%"
      :options="chartOptions"
      :series="localSeries"
    />
  </div>
</template>

<style scoped lang="scss">
.foodsafetytrend {
	width: 100%;
	height: 100%;
	display: flex;
	flex-direction: column;
	overflow: hidden;

	&-labels {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		margin-bottom: 4px;
	}

	&-label {
		color: var(--color-complement-text);
		font-size: var(--font-s);
		padding-left: 6px;
		border-left: 3px solid;
	}
}
</style>
