<!-- Food Safety Early Warning PoC — 食安警報地圖 (symbol layer) -->

<script setup>
import { ref } from "vue";
import cross_bold from "../assets/map/cross_bold.png";

const props = defineProps([
	"chart_config",
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

// 違規數對應顏色
function getRiskColor(violationCount) {
	if (violationCount === 0) return "#2ECC71";
	if (violationCount <= 2) return "#E67E22";
	return "#E74C3C";
}

// 違規數對應標籤
function getRiskLabel(violationCount) {
	if (violationCount === 0) return "合格";
	if (violationCount <= 2) return "輕微違規";
	return "重大違規";
}

const selectedIndex = ref(null);

function handleDataSelection(index) {
	if (!props.map_filter || !props.map_filter_on) {
		return;
	}
	if (index !== selectedIndex.value) {
		if (props.map_filter.mode === "byParam") {
			emits(
				"filterByParam",
				props.map_filter,
				props.map_config,
				props.series[index].name,
				null
			);
		} else if (props.map_filter.mode === "byLayer") {
			emits("filterByLayer", props.map_config, props.series[index].name);
		}
		selectedIndex.value = index;
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
  <div class="foodsafetyalertmap">
    <div class="foodsafetyalertmap-header">
      <p class="foodsafetyalertmap-subtitle">
        整合稽查記錄與社群預警訊號
      </p>
    </div>
    <div class="foodsafetyalertmap-legend">
      <button
        v-for="(item, index) in series"
        :key="item.name"
        :class="{
          'foodsafetyalertmap-legend-item': true,
          'foodsafetyalertmap-filter': map_filter_on && map_filter,
          'foodsafetyalertmap-selected': map_filter_on && selectedIndex === index,
        }"
        @click="handleDataSelection(index)"
      >
        <div
          class="foodsafetyalertmap-legend-dot"
          :style="{ backgroundColor: chart_config.color[index] }"
        />
        <div>
          <h6>{{ item.name }}</h6>
          <p
            v-if="item.value"
            class="foodsafetyalertmap-value"
          >
            {{ item.value }} {{ chart_config.unit }}
          </p>
        </div>
      </button>
    </div>
    <div class="foodsafetyalertmap-stats">
      <div class="foodsafetyalertmap-stats-row">
        <span class="foodsafetyalertmap-stats-label">今日警報</span>
        <span class="foodsafetyalertmap-stats-value alert">3 件</span>
      </div>
      <div class="foodsafetyalertmap-stats-row">
        <span class="foodsafetyalertmap-stats-label">本週稽查</span>
        <span class="foodsafetyalertmap-stats-value">13 點</span>
      </div>
      <div class="foodsafetyalertmap-stats-row">
        "
        <span class="foodsafetyalertmap-stats-label">違規率</span>
        <span class="foodsafetyalertmap-stats-value warn">38.5%</span>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
* {
	margin: 0;
	padding: 0;
	font-family: "微軟正黑體", "Microsoft JhengHei", "Droid Sans", "Open Sans",
		"Helvetica";
	overflow: hidden;
}

button {
	border: none;
	background-color: transparent;
}

.foodsafetyalertmap {
	width: 100%;
	height: 100%;
	display: flex;
	flex-direction: column;
	gap: 0.5rem;
	overflow: visible;

	&-subtitle {
		color: var(--color-complement-text);
		font-size: var(--font-s);
	}

	&-legend {
		width: 100%;
		display: grid;
		grid-template-columns: 1fr 1fr;
		column-gap: 0.5rem;
		row-gap: 0.4rem;
		overflow: visible;

		&-item {
			display: flex;
			align-items: center;
			padding: 5px 10px 5px 5px;
			border: 1px solid transparent;
			border-radius: 5px;
			transition: box-shadow 0.2s;
			cursor: auto;
		}

		&-dot {
			width: 0.8rem;
			height: 0.8rem;
			border-radius: 50%;
			margin-right: 0.6rem;
			flex-shrink: 0;
		}

		h6 {
			color: var(--color-normal-text);
			font-size: var(--font-ms);
			font-weight: 400;
			text-align: left;
		}
	}

	&-value {
		color: var(--color-complement-text);
		font-size: var(--font-s);
	}

	&-filter {
		border: 1px solid var(--color-border);
		cursor: pointer;

		&:hover {
			box-shadow: 0px 0px 5px black;
		}
	}

	&-selected {
		box-shadow: 0px 0px 5px black;
	}

	&-stats {
		margin-top: 0.5rem;
		padding: 0.5rem;
		border-radius: 5px;
		background-color: rgba(255, 255, 255, 0.05);

		&-row {
			display: flex;
			justify-content: space-between;
			align-items: center;
			padding: 3px 0;
		}

		&-label {
			color: var(--color-complement-text);
			font-size: var(--font-s);
		}

		&-value {
			color: var(--color-normal-text);
			font-size: var(--font-ms);
			font-weight: 600;

			&.alert {
				color: #e74c3c;
			}

			&.warn {
				color: #e67e22;
			}
		}
	}
}
</style>
