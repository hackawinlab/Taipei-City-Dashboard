<!-- Developed by Taipei Urban Intelligence Center 2023-2024-->

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
	"fly"
]);

const heatmapData = computed(() => {
	let output = {};
	let highest = 0;
	let sum = 0;
	let count = 0;
	if (props.series.length === 1) {
		props.series[0].data.forEach((item) => {
			output[item.x] = item.y;
			if (item.y > highest) {
				highest = item.y;
			}
			sum += item.y;
			count += 1;
		});
	} else {
		props.series.forEach((serie) => {
			for (let i = 0; i < props.chart_config.categories.length; i++) {
				if (!output[props.chart_config.categories[i]]) {
					output[props.chart_config.categories[i]] = 0;
				}
				const raw = serie.data[i];
				const value = +(raw && typeof raw === "object" ? raw.y : raw);
				if (Number.isNaN(value)) continue;
				output[props.chart_config.categories[i]] += value;
				count += 1;
				if (value > highest) highest = value;
			}
		});
		sum = Object.values(output).reduce(
			(partialSum, a) => partialSum + a,
			0
		);
	}

	output.highest = highest;
	output.sum = sum;
	output.mean = count > 0 ? sum / count : 0;
	return output;
});

const showSummary = computed(() => !props.chart_config.hide_summary);
const summaryLabel = computed(
	() => props.chart_config.summary_label ?? "總合"
);
const summaryValue = computed(() => {
	if (props.chart_config.summary_text) {
		return props.chart_config.summary_text;
	}
	const mode = props.chart_config.summary_aggregate ?? "sum";
	const value = mode === "mean" ? heatmapData.value.mean : heatmapData.value.sum;
	if (!Number.isFinite(value)) return "—";
	const decimals = props.chart_config.summary_decimals ?? (mode === "mean" ? 1 : 0);
	return value.toFixed(decimals);
});
const summaryUnit = computed(() => {
	if (props.chart_config.summary_text) return "";
	return props.chart_config.unit;
});

const colorScale = computed(() => {
	const ranges = props.chart_config.color.map(
		(el, index) => ({
			to: Math.floor(
				(heatmapData.value.highest / props.chart_config.color.length) *
					(props.chart_config.color.length - index)
			),
			from:
				Math.floor(
					(heatmapData.value.highest /
						props.chart_config.color.length) *
						(props.chart_config.color.length - index - 1)
				) + 1,
			color: el,
		})
	);
	ranges.unshift({
		to: 0,
		from: 0,
		color: "#444444",
	});
	return ranges;
});

const chartOptions = ref({
	chart: {
		stacked: true,
		toolbar: {
			show: false,
		},
	},
	dataLabels: {
		enabled: !props.chart_config.hide_data_labels,
		distributed: true,
		style: {
			fontSize: props.chart_config.data_label_font_size ?? "12px",
			fontWeight: "normal",
		},
	},
	grid: {
		show: false,
	},
	legend: {
		show: false,
	},
	markers: {
		size: 3,
		strokeWidth: 0,
	},
	plotOptions: {
		heatmap: {
			enableShades: false,
			radius: 4,
			colorScale: {
				ranges: colorScale.value,
			},
		},
	},
	stroke: {
		show: true,
		width: 2,
		colors: ["#282a2c"],
	},
	tooltip: {
		custom: function ({
			series,
			seriesIndex,
			dataPointIndex,
			w,
		}) {
			// The class "chart-tooltip" could be edited in /assets/styles/chartStyles.css
			return (
				'<div class="chart-tooltip">' +
				"<h6>" +
				`${w.globals.labels[dataPointIndex]}-${w.globals.seriesNames[seriesIndex]}` +
				"</h6>" +
				"<span>" +
				`${series[seriesIndex][dataPointIndex]}` +
				`${props.chart_config.unit}` +
				"</span>" +
				"</div>"
			);
		},
	},
	xaxis: {
		axisBorder: {
			show: false,
		},
		axisTicks: {
			show: false,
		},
		categories: props.chart_config.categories
			? props.chart_config.categories
			: [],
		labels: {
			offsetY: 5,
			formatter: function (value) {
				return value.length > 7 ? value.slice(0, 6) + "..." : value;
			},
		},
		tooltip: {
			enabled: false,
		},
		type: "category",
	},
	yaxis: {
		max: function (max) {
			if (!props.chart_config.categories) {
				return max;
			}
			return heatmapData.value.highest;
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
  <div
    v-if="activeChart === 'HeatmapChart'"
    :class="['heatmapchart', { 'heatmapchart-fit': chart_config?.fit }]"
  >
    <div
      v-if="showSummary"
      class="heatmapchart-title"
    >
      <h5>{{ summaryLabel }}</h5>
      <h6>{{ summaryValue }} {{ summaryUnit }}</h6>
    </div>
    <VueApexCharts
      width="100%"
      :height="chart_config?.fit ? '100%' : '360px'"
      type="heatmap"
      :options="chartOptions"
      :series="series"
      @data-point-selection="handleDataSelection"
    />
  </div>
</template>

<style scoped lang="scss">
.heatmapchart-fit {
	height: 100%;
	overflow: hidden;
}

.heatmapchart {
	&-title {
		display: flex;
		justify-content: center;
		flex-direction: column;
		margin: -0.2rem 0 -1.5rem;

		h5 {
			margin: 0;
			color: var(--color-complement-text);
		}

		h6 {
			margin: 0;
			color: var(--color-complement-text);
			font-size: var(--font-m);
			font-weight: 400;
		}
	}
}
</style>
