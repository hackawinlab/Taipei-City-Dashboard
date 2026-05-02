<!-- Food Safety Early Warning PoC — 食安風險行政區塗層（fill layer） -->

<script setup>
import { ref } from "vue";

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

// fill layer 色階對應
const riskLevels = [
	{ label: "高風險",  color: "#C0392B", desc: "違規率 ≥ 25%" },
	{ label: "中風險",  color: "#E67E22", desc: "違規率 10–24%" },
	{ label: "低風險",  color: "#2ECC71", desc: "違規率 < 10%" },
	{ label: "無資料",  color: "#808080", desc: "尚未統計" },
];

const selectedIndex = ref(null);

function handleLayerFilter(index) {
	if (!props.map_filter || !props.map_filter_on) return;

	if (index !== selectedIndex.value) {
		if (props.map_filter.mode === "byLayer") {
			emits(
				"filterByLayer",
				props.map_config,
				riskLevels[index].label
			);
		} else if (props.map_filter.mode === "byParam") {
			emits(
				"filterByParam",
				props.map_filter,
				props.map_config,
				riskLevels[index].label,
				null
			);
		}
		selectedIndex.value = index;
	} else {
		if (props.map_filter.mode === "byLayer") {
			emits("clearByLayerFilter", props.map_config);
		} else if (props.map_filter.mode === "byParam") {
			emits("clearByParamFilter", props.map_config);
		}
		selectedIndex.value = null;
	}
}
</script>

<template>
  <div class="foodsafetyrisklayer">
    <!-- 說明文字 -->
    <p class="foodsafetyrisklayer-desc">
      依行政區違規率計算食安風險等級，以塗層呈現分布熱區
    </p>

    <!-- 色階圖例（fill layer 對應色） -->
    <div class="foodsafetyrisklayer-legend">
      <button
        v-for="(level, index) in riskLevels"
        :key="level.label"
        :class="{
          'foodsafetyrisklayer-legend-item': true,
          'foodsafetyrisklayer-filter': map_filter_on && map_filter,
          'foodsafetyrisklayer-selected': map_filter_on && selectedIndex === index,
        }"
        @click="handleLayerFilter(index)"
      >
        <div
          class="foodsafetyrisklayer-legend-block"
          :style="{ backgroundColor: level.color }"
        />
        <div class="foodsafetyrisklayer-legend-text">
          <h6>{{ level.label }}</h6>
          <p>{{ level.desc }}</p>
        </div>
      </button>
    </div>

    <!-- 漸層色階尺 -->
    <div class="foodsafetyrisklayer-scale">
      <div class="foodsafetyrisklayer-scale-bar" />
      <div class="foodsafetyrisklayer-scale-labels">
        <span>低</span>
        <span>中</span>
        <span>高</span>
      </div>
    </div>

    <!-- 統計摘要 -->
    <div class="foodsafetyrisklayer-summary">
      <div
        v-for="level in riskLevels.slice(0, 3)"
        :key="level.label"
        class="foodsafetyrisklayer-summary-item"
      >
        <div
          class="foodsafetyrisklayer-summary-dot"
          :style="{ backgroundColor: level.color }"
        />
        <span class="foodsafetyrisklayer-summary-label">{{ level.label }}</span>
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
	cursor: auto;
}

.foodsafetyrisklayer {
	width: 100%;
	height: 100%;
	display: flex;
	flex-direction: column;
	gap: 0.6rem;
	overflow: visible;

	&-desc {
		color: var(--color-complement-text);
		font-size: var(--font-s);
		line-height: 1.4;
	}

	&-legend {
		display: grid;
		grid-template-columns: 1fr 1fr;
		column-gap: 0.5rem;
		row-gap: 0.4rem;
		overflow: visible;

		&-item {
			display: flex;
			align-items: center;
			padding: 5px 8px 5px 5px;
			border: 1px solid transparent;
			border-radius: 5px;
			transition: box-shadow 0.2s;
		}

		&-block {
			width: 1rem;
			height: 1rem;
			border-radius: 2px;
			margin-right: 0.6rem;
			flex-shrink: 0;
			opacity: 0.85;
		}

		&-text {
			h6 {
				color: var(--color-normal-text);
				font-size: var(--font-ms);
				font-weight: 600;
				text-align: left;
			}

			p {
				color: var(--color-complement-text);
				font-size: var(--font-s);
				text-align: left;
			}
		}
	}

	&-filter {
		border: 1px solid var(--color-border);
		cursor: pointer !important;

		&:hover {
			box-shadow: 0px 0px 5px black;
		}
	}

	&-selected {
		box-shadow: 0px 0px 5px black;
	}

	// 色階漸層尺
	&-scale {
		margin-top: 0.2rem;

		&-bar {
			width: 100%;
			height: 0.5rem;
			border-radius: 3px;
			background: linear-gradient(to right, #2ECC71, #E67E22, #C0392B);
		}

		&-labels {
			display: flex;
			justify-content: space-between;
			margin-top: 2px;

			span {
				color: var(--color-complement-text);
				font-size: var(--font-s);
			}
		}
	}

	&-summary {
		display: flex;
		gap: 0.8rem;
		margin-top: 0.2rem;

		&-item {
			display: flex;
			align-items: center;
			gap: 4px;
		}

		&-dot {
			width: 0.7rem;
			height: 0.7rem;
			border-radius: 50%;
		}

		&-label {
			color: var(--color-complement-text);
			font-size: var(--font-s);
		}
	}
}
</style>
