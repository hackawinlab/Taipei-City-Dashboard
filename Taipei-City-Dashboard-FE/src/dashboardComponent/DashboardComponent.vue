<script setup>
import { computed, nextTick, ref } from "vue";
// import "./styles/chartStyles.css";
// import "./styles/toggleswitch.css";
import "material-icons/iconfont/material-icons.css";
import { getComponentDataTimeframe } from "./utilities/dataTimeframe";
import { timeTerms } from "./utilities/AllTimes";
import { chartTypes } from "./utilities/chartTypes";
import http from "../router/axios";

import ComponentTag from "./components/ComponentTag.vue";
import TagTooltip from "./components/TagTooltip.vue";
import DistrictChart from "./components/DistrictChart.vue";
import DonutChart from "./components/DonutChart.vue";
import BarChart from "./components/BarChart.vue";
import TreemapChart from "./components/TreemapChart.vue";
import ColumnChart from "./components/ColumnChart.vue";
import BarPercentChart from "./components/BarPercentChart.vue";
import GuageChart from "./components/GuageChart.vue";
import RadarChart from "./components/RadarChart.vue";
import TimelineSeparateChart from "./components/TimelineSeparateChart.vue";
import TimelineStackedChart from "./components/TimelineStackedChart.vue";
import MapLegend from "./components/MapLegend.vue";
import MetroChart from "./components/MetroChart.vue";
import HeatmapChart from "./components/HeatmapChart.vue";
import PolarAreaChart from "./components/PolarAreaChart.vue";
import ColumnLineChart from "./components/ColumnLineChart.vue";
import BarChartWithGoal from "./components/BarChartWithGoal.vue";
import IconPercentChart from "./components/IconPercentChart.vue";
import IndicatorChart from "./components/IndicatorChart.vue";
import TextUnitChart from "./components/TextUnitChart.vue";
import YouBikeTimeMap from "./components/YouBikeTimeMap.vue";
import BusCongestionTimeline from "./components/BusCongestionTimeline.vue";
import ScatterChart from "./components/ScatterChart.vue";

import MapLegendSvg from "./assets/chart/MapLegend.svg";
import DistrictChartSvg from "./assets/chart/DistrictChart.svg";
import TimelineStackedChartSvg from "./assets/chart/TimelineStackedChart.svg";
import BarChartSvg from "./assets/chart/BarChart.svg";
import BarPercentChartSvg from "./assets/chart/BarPercentChart.svg";
import ColumnChartSvg from "./assets/chart/ColumnChart.svg";
import ColumnLineChartSvg from "./assets/chart/ColumnLineChart.svg";
import DonutChartSvg from "./assets/chart/DonutChart.svg";
import GuageChartSvg from "./assets/chart/GuageChart.svg";
import HeatmapChartSvg from "./assets/chart/HeatmapChart.svg";
import IconPercentChartSvg from "./assets/chart/IconPercentChart.svg";
import MetroChartSvg from "./assets/chart/MetroChart.svg";
import PolarAreaChartSvg from "./assets/chart/PolarAreaChart.svg";
import RadarChartSvg from "./assets/chart/RadarChart.svg";
import TimelineSeparateChartSvg from "./assets/chart/TimelineSeparateChart.svg";
import BarChartWithGoalSvg from "./assets/chart/BarChartWithGoal.svg";
import TreemapChartSvg from "./assets/chart/TreemapChart.svg";
import IndicatorChartSvg from "./assets/chart/IndicatorChart.svg";
import TextUnitChartSvg from "./assets/chart/TextUnitChart.svg";


const props = defineProps({
	style: { type: Object, default: () => ({}) },
	mode: {
		type: String,
		default: "default",
		validator: (value) =>
			["default", "large", "map", "half", "halfmap", "preview"].includes(
				value
			),
	},
	config: { type: Object, required: true },
	selectBtn: { type: Boolean, default: false },
	selectBtnDisabled: { type: Boolean, default: false },
	selectBtnList: { type: Array, default: () => ([])  },
	cityTag: { type: Array, default: () => ([]) },
	favoriteBtn: { type: Boolean, default: false },
	isFavorite: { type: Boolean, default: false },
	deleteBtn: { type: Boolean, default: false },
	addBtn: { type: Boolean, default: false },
	infoBtn: { type: Boolean, default: false },
	infoBtnText: { type: String, default: "組件資訊" },
	toggleDisable: { type: Boolean, default: false },
	footer: { type: Boolean, default: true },
	activeCity: { type: String, default: '' },
	toggleOn: { type: Boolean, default: false },
});

const emits = defineEmits([
	"favorite",
	"delete",
	"add",
	"info",
	"toggle",
	"filterByParam",
	"filterByLayer",
	"clearByParamFilter",
	"clearByLayerFilter",
	"fly",
	"changeCity"
]);

const activeChart = ref(props.config.chart_config.types[0]);
const activeCity = computed({
	get: () => props.activeCity,
	set: (value) => {
		if (toggleOn.value === false) {
			toggleOn.value = true;
		}
		emits("changeCity", value);
	},
});

const toggleOn = computed({
	get: () => props.toggleOn,
	set: (value) => {
		emits("toggle", value, props.config.map_config);
	},
});

const mousePosition = ref({ x: null, y: null });
const showTagTooltip = ref(false);

// --- Component AI Action (currently only for YouBikeTimeMap) ---
const showAI = computed(
	() =>
		activeChart.value === "YouBikeTimeMap" && props.mode !== "preview"
);
const aiPanelOpen = ref(false);
const aiPrompt = ref("");
const aiLoading = ref(false);
const aiError = ref("");
const aiResult = ref(null);
const chartRef = ref(null);
const suggestedPrompts = ref([]);
const aiAnchor = ref({ top: 80, left: 24 });
const aiPanelStyle = computed(() => {
	if (!props.mode.includes("map")) return null;
	return {
		top: `${aiAnchor.value.top}px`,
		left: `${aiAnchor.value.left}px`,
		right: "auto",
	};
});

function setChartRef(el, item) {
	if (item === activeChart.value) chartRef.value = el;
}

function followupLabel(fu) {
	if (typeof fu === "string") return fu;
	return fu?.label || fu?.quick_action || "";
}

function followupAction(fu) {
	if (typeof fu === "string") return fu;
	return fu?.quick_action || fu?.label || "";
}

function areaInsightOf(result) {
	const list = result?.insights || [];
	return list.find((i) => i?.kind === "area_availability") || null;
}

async function loadStarterPrompts() {
	if (suggestedPrompts.value.length > 0) return;
	try {
		const res = await http.post("/ai/component-action", {
			component_id: "youbike_timemap",
			user_message: "",
		});
		const fus = res.data?.followups || [];
		suggestedPrompts.value = fus
			.map((fu) => followupAction(fu))
			.filter(Boolean);
	} catch {
		// Silent; panel still works, suggestion chips just stay empty.
	}
}

function onAIClick(event) {
	if (props.mode.includes("map") && !toggleOn.value) {
		toggleOn.value = true;
	}
	if (props.mode.includes("map") && event?.currentTarget) {
		const rect = event.currentTarget.getBoundingClientRect();
		const PANEL_WIDTH = 300;
		const GAP = 8;
		const margin = 16;
		// Pop the panel out to the RIGHT of the button (into the map
		// area) and align its top with the button's top — this keeps
		// the card's time slider, 組件資訊 link, and other controls
		// uncovered. Fall back to "left of button" if the right side
		// would clip; clamp top so it fits in the viewport.
		let left = rect.right + GAP;
		if (left + PANEL_WIDTH > window.innerWidth - margin) {
			left = Math.max(margin, rect.left - PANEL_WIDTH - GAP);
		}
		const top = Math.max(
			margin,
			Math.min(rect.top, window.innerHeight - 200)
		);
		aiAnchor.value = { top, left };
	}
	aiPanelOpen.value = !aiPanelOpen.value;
	if (aiPanelOpen.value) loadStarterPrompts();
}

async function submitAIAction(prompt = aiPrompt.value) {
	const message = String(prompt || "").trim();
	if (!message || aiLoading.value) return;
	aiPrompt.value = message;
	aiLoading.value = true;
	aiError.value = "";
	try {
		if (props.mode.includes("map") && !toggleOn.value) {
			toggleOn.value = true;
		}
		await nextTick();
		const componentState =
			chartRef.value?.getComponentState?.() ?? {};
		const res = await http.post("/ai/component-action", {
			component_id: "youbike_timemap",
			user_message: message,
			component_state: componentState,
		});
		aiResult.value = res.data;
		await nextTick();
		(res.data.ui_events || []).forEach((ev) =>
			chartRef.value?.applyAIEvent?.(ev)
		);
	} catch (e) {
		aiError.value =
			e?.response?.data?.message ||
			"AI 操作暫時無法執行，請稍後再試。";
	} finally {
		aiLoading.value = false;
	}
}

// Parses time data into display format
const dataTime = computed(() => {
	if (props.config.time_from === "static") {
		return "固定資料";
	} else if (props.config.time_from === "current") {
		return "即時資料";
	} else if (props.config.time_from === "demo") {
		return "示範靜態資料";
	} else if (props.config.time_from === "maintain") {
		return "維護修復中";
	}
	const { timefrom, timeto } = getComponentDataTimeframe(
		props.config.time_from,
		props.config.time_to,
		true
	);
	if (props.config.time_from === "day_start") {
		return `${timefrom.slice(0, 16)} ~ ${timeto.slice(11, 14)}00`;
	}
	return `${timefrom.slice(0, 10)} ~ ${timeto.slice(0, 10)}`;
});
// Parses update frequency data into display format
const updateFreq = computed(() => {
	if (props.config.update_freq && props.config.update_freq_unit) {
		return `每${props.config.update_freq}${
			timeTerms[props.config.update_freq_unit]
		}更新`;
	} else {
		return "不定期更新";
	}
});

// The style for the tag tooltip
const tooltipPosition = computed(() => {
	if (!mousePosition.value.x || !mousePosition.value.y) {
		return {
			left: "-1000px",
			top: "-1000px",
		};
	}
	return {
		left: `${mousePosition.value.x - 40}px`,
		top: `${mousePosition.value.y - 110}px`,
	};
});

function changeActiveChart(chartName) {
	if (
		props.mode === "map" &&
		props.config.map_config &&
		props.config.map_config[0] &&
		props.config.map_filter
	) {
		if (props.config.map_filter.mode === "byParam") {
			emits("clearByParamFilter", props.config.map_config);
		} else if (props.config.map_filter.mode === "byLayer") {
			emits("clearByLayerFilter", props.config.map_config);
		}
	}
	activeChart.value = chartName;
}
// Updates the location for the tag tooltip
function updateMouseLocation(e) {
	mousePosition.value.x = e.pageX;
	mousePosition.value.y = e.pageY;
}
// Updates whether to show the tag tooltip
function changeShowTagTooltipState(state) {
	showTagTooltip.value = state;
}
function returnChartComponent(name, svg) {
	switch (name) {
	case "DistrictChart":
		return svg ? DistrictChartSvg : DistrictChart;
	case "BarChart":
		return svg ? BarChartSvg : BarChart;
	case "MapLegend":
		return svg ? MapLegendSvg : MapLegend;
	case "MetroChart":
		return svg ? MetroChartSvg : MetroChart;
	case "TimelineSeparateChart":
		return svg ? TimelineSeparateChartSvg : TimelineSeparateChart;
	case "TimelineStackedChart":
		return svg ? TimelineStackedChartSvg : TimelineStackedChart;
	case "PolarAreaChart":
		return svg ? PolarAreaChartSvg : PolarAreaChart;
	case "IconPercentChart":
		return svg ? IconPercentChartSvg : IconPercentChart;
	case "ColumnChart":
		return svg ? ColumnChartSvg : ColumnChart;
	case "DonutChart":
		return svg ? DonutChartSvg : DonutChart;
	case "TreemapChart":
		return svg ? TreemapChartSvg : TreemapChart;
	case "BarPercentChart":
		return svg ? BarPercentChartSvg : BarPercentChart;
	case "GuageChart":
		return svg ? GuageChartSvg : GuageChart;
	case "RadarChart":
		return svg ? RadarChartSvg : RadarChart;
	case "HeatmapChart":
		return svg ? HeatmapChartSvg : HeatmapChart;
	case "ColumnLineChart":
		return svg ? ColumnLineChartSvg : ColumnLineChart;
	case "BarChartWithGoal":
		return svg ? BarChartWithGoalSvg : BarChartWithGoal;
	case "IndicatorChart":
		return svg ? IndicatorChartSvg : IndicatorChart;
	case "TextUnitChart":
		return svg ? TextUnitChartSvg : TextUnitChart;
	case "YouBikeTimeMap":
		return svg ? MapLegendSvg : YouBikeTimeMap;
	case "BusCongestionTimeline":
		return svg ? TimelineStackedChartSvg : BusCongestionTimeline;
	case "ScatterChart":
		return svg ? HeatmapChartSvg : ScatterChart;
	default:
		return svg ? MapLegendSvg : MapLegend;
	}
}
</script>

<template>
  <div
    :class="[
      {
        dashboardcomponent: true,
        mapclosed: mode.includes('map') && !toggleOn,
        mapopen: mode === 'map' && toggleOn,
        halfmapopen: mode === 'halfmap' && toggleOn,
        half: mode === 'half',
        large: mode === 'large',
        preview: mode === 'preview',
        compact: activeChart === 'YouBikeTimeMap',
      },
    ]"
    :style="style"
  >
    <!-- Header -->
    <div class="dashboardcomponent-header">
      <!-- Upper Left Corner -->
      <div>
        <h3>
          {{ config.name }}
          <ComponentTag
            v-if="!mode.includes('map')"
            icon=""
            :text="updateFreq"
            mode="small"
          />
          <div
            v-else
            @mouseenter="changeShowTagTooltipState(true)"
            @mousemove="updateMouseLocation"
            @mouseleave="changeShowTagTooltipState(false)"
          >
            <span v-if="config.map_filter && config.map_config">tune</span>
            <span v-if="config.map_config && config.map_config[0]">map</span>
            <span v-if="config.history_config?.range">insights</span>
          </div>
        </h3>
        <p v-if="mode === 'preview'">
          {{ props.config.short_desc }}
        </p>
        <div v-if="!mode.includes('map') || toggleOn">
          <h4 v-if="dataTime === '維護修復中'">
            {{ `${config.source} | ` }}<span>warning</span>
            <h4>{{ `${dataTime}` }}</h4>
            <span>warning</span>
          </h4>
          <h4 v-else>
            {{ `${config.source} | ${dataTime}` }}
          </h4>
          <div
            v-if="mode !== 'preview'"
            class="city-tag-container"
          >
            <ComponentTag
              v-for=" city in props.cityTag"
              :key="city"
              :icon="''"
              :text="city.name"
              :mode="'small'"
              :class="`city-tag-item ${city.value}`"
            />
          </div>
        </div>
      </div>
      <!-- Upper Right Corner -->
      <div
        v-if="['default', 'half', 'preview'].includes(mode)"
        class="dashboardcomponent-header-button"
      >
        <button
          v-if="showAI"
          class="ai-btn"
          :class="{ active: aiPanelOpen }"
          title="AI 操作這張圖"
          @click="onAIClick"
        >
          <span>auto_awesome</span>
        </button>
        <button
          v-if="addBtn"
          @click="$emit('add', config.id, config.name)"
        >
          <span>add_circle</span>
        </button>
        <button
          v-if="favoriteBtn"
          :class="{
            isfavorite: isFavorite,
          }"
          @click="$emit('favorite', config.id)"
        >
          <span>favorite</span>
        </button>
        <button
          v-if="deleteBtn"
          class="isDelete"
          @click="$emit('delete', config.id)"
        >
          <span>delete</span>
        </button>
      </div>
      <div
        v-else-if="mode.includes('map')"
        class="dashboardcomponent-header-toggle"
      >
        <button
          v-if="showAI"
          class="ai-btn ai-btn-map"
          :class="{ active: aiPanelOpen }"
          title="AI 操作這張圖"
          @click="onAIClick"
        >
          <span>auto_awesome</span>
        </button>
        <label class="toggleswitch">
          <input
            v-model="toggleOn"
            type="checkbox"
            :disabled="toggleDisable"
          >
          <span class="toggleswitch-slider" />
        </label>
      </div>
    </div>
    <!-- Component AI Action panel (teleport to body in map mode to escape overflow:hidden) -->
    <Teleport
      to="body"
      :disabled="!mode.includes('map')"
    >
      <div
        v-if="showAI && aiPanelOpen"
        class="dashboardcomponent-ai-panel"
        :class="{ 'ai-panel-floating': mode.includes('map') }"
        :style="aiPanelStyle"
      >
        <div class="dashboardcomponent-ai-panel-title">
          <span>AI 操作這張地圖</span>
          <button @click="aiPanelOpen = false">
            <span>close</span>
          </button>
        </div>
        <div class="dashboardcomponent-ai-suggestions">
          <button
            v-for="prompt in suggestedPrompts"
            :key="prompt"
            :disabled="aiLoading"
            @click="submitAIAction(prompt)"
          >
            {{ prompt }}
          </button>
        </div>
        <form
          class="dashboardcomponent-ai-input"
          @submit.prevent="submitAIAction()"
        >
          <input
            v-model="aiPrompt"
            :disabled="aiLoading"
            placeholder="例如：幫我看公館晚高峰"
          >
          <button
            type="submit"
            :disabled="aiLoading"
          >
            <span>{{ aiLoading ? "hourglass_top" : "send" }}</span>
          </button>
        </form>
        <p
          v-if="aiError"
          class="dashboardcomponent-ai-error"
        >
          {{ aiError }}
        </p>
        <div
          v-if="aiResult"
          class="dashboardcomponent-ai-result"
          :class="{ 'is-clarify': aiResult.mode === 'clarify' }"
        >
          <p>{{ aiResult.summary }}</p>
          <ul v-if="aiResult.ui_events?.length">
            <li
              v-for="(event, idx) in aiResult.ui_events"
              :key="`${event.action}-${idx}`"
            >
              {{ event.action === "set_time_slot"
                ? `切到 ${event.payload.label}`
                : `移到 ${event.payload.place}` }}
            </li>
          </ul>
          <div
            v-if="areaInsightOf(aiResult)"
            class="dashboardcomponent-ai-insight"
            :class="`verdict-${areaInsightOf(aiResult).verdict}`"
          >
            <span class="verdict-dot" />
            <span>{{ areaInsightOf(aiResult).phrasing }}</span>
          </div>
          <div
            v-if="aiResult.followups?.length"
            class="dashboardcomponent-ai-followups"
          >
            <button
              v-for="(fu, i) in aiResult.followups"
              :key="`fu-${i}`"
              :disabled="aiLoading"
              @click="submitAIAction(followupAction(fu))"
            >
              {{ followupLabel(fu) }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
    <!-- Control Buttons -->
    <div
      v-if="
        (!mode.includes('map') || toggleOn) &&
          mode !== 'preview'
      "
      class="dashboardcomponent-control"
    >
      <select
        v-if="selectBtn && !selectBtnDisabled"
        v-model="activeCity"
        name="city"
        class="selectBtn"
        :class="{'selectBtn-disabled': selectBtnDisabled}"
      >
        <template
          v-for="city in props.selectBtnList"
          :key="city.value"
        >
          <option :value="city.value">
            {{ city.name }}
          </option>
        </template>
      </select>
      <div
        v-if="config.chart_config.types.length > 1"
        class="dashboardcomponent-control-group"
      >
        <button
          v-for="item in config.chart_config.types"
          :key="`${config.index}-${item}-button`"
          :class="{
            'dashboardcomponent-control-group-button': true,
            'dashboardcomponent-control-group-active': activeChart === item,
          }"
          @click="changeActiveChart(item)"
        >
          {{ chartTypes[item] }}
        </button>
      </div>
    </div>
    <!-- Main Content -->
    <div
      v-if="mode === 'preview'"
      class="preview-content"
    >
      <div
        class="preview-content-id"
      >
        <div
          v-if="mode === 'preview'"
          class="city-tag-container-preview"
        >
          <ComponentTag
            v-for="city in props.cityTag"
            :key="city.value"
            :icon="''"
            :text="city.name"
            :mode="'small'"
            :class="`city-tag-item ${city.value}`"
          />
        </div>
        <p :title="props.config.index">
          Index: {{ props.config.index }}
        </p>
      </div>
      <div class="preview-content-charts">
        <img
          v-for="chart in props.config.chart_config.types"
          :key="`${props.config.index} - ${chart}`"
          :src="returnChartComponent(chart, true).toString()"
        >
      </div>
    </div>
    <div
      v-else-if="config.chart_data && (toggleOn || !mode.includes('map'))"
      :class="{
        'dashboardcomponent-chart': true,
        'half-chart': mode === 'half',
        'mapopen-chart': mode === 'map',
        'halfmapopen-chart': mode === 'halfmap',
      }"
    >
      <component
        :is="returnChartComponent(item)"
        v-for="item in config.chart_config.types"
        :ref="(el) => setChartRef(el, item)"
        :key="`${props.config.index}-${item}-chart-${item.city}`"
        :active-chart="activeChart"
        :active-city="activeCity"
        :chart_config="config.chart_config"
        :series="config.chart_data"
        :map_config="config.map_config"
        :map_filter="config.map_filter"
        :map_filter_on="mode.includes('map')"
        @filter-by-param="
          (map_filter, map_config, x, y) =>
            $emit('filterByParam', map_filter, map_config, x, y)
        "
        @filter-by-layer="
          (map_config, x) => $emit('filterByLayer', map_config, x)
        "
        @clear-by-param-filter="
          (map_config) => $emit('clearByParamFilter', map_config)
        "
        @clear-by-layer-filter="
          (map_config) => $emit('clearByLayerFilter', map_config)
        "
        @fly="(location) => $emit('fly', location)"
      />
    </div>
    <div
      v-else-if="
        config.chart_data === null &&
          (toggleOn || !mode.includes('map'))
      "
      :class="{
        'dashboardcomponent-error': true,
        'half-loading': mode === 'half',
        'mapopen-loading': mode.includes('map'),
      }"
    >
      <span>error</span>
      <p>組件資料異常</p>
    </div>
    <div
      v-else-if="toggleOn || !mode.includes('map')"
      :class="{
        'dashboardcomponent-loading': true,
        'mapopen-loading': mode.includes('map'),
        'half-loading': mode === 'half',
      }"
    >
      <div />
    </div>
    <!-- Footer -->
    <div
      v-if="footer && (!mode.includes('map') || toggleOn)"
      class="dashboardcomponent-footer"
    >
      <div
        v-if="!mode.includes('map')"
        @mouseenter="changeShowTagTooltipState(true)"
        @mousemove="updateMouseLocation"
        @mouseleave="changeShowTagTooltipState(false)"
      >
        <ComponentTag
          v-if="config.map_filter && config.map_config?.length > 0"
          :icon="mode === 'preview' ? '' : 'tune'"
          text="篩選地圖"
          class="hide-if-mobile"
        />
        <ComponentTag
          v-if="config.map_config && config.map_config[0] !== null && config.map_config?.length > 0"
          :icon="mode === 'preview' ? '' : 'map'"
          text="空間資料"
          class="hide-if-mobile"
        />
        <ComponentTag
          v-if="config.history_config?.range"
          :icon="mode === 'preview' ? '' : 'insights'"
          text="歷史資料"
          class="history-tag"
        />
      </div>
      <div v-else />
      <button
        v-if="infoBtn"
        @click="$emit('info', config)"
      >
        <p>{{ infoBtnText }}</p>
        <span>arrow_circle_right</span>
      </button>
    </div>
    <div
      v-else-if="!mode.includes('map')"
      class="dashboardcomponent-footer"
    />
  </div>
  <Teleport to="body">
    <!-- The class "chart-tooltip" could be edited in /assets/styles/chartStyles.css -->
    <TagTooltip
      v-if="showTagTooltip"
      :position="tooltipPosition"
      :has-filter="config.map_filter ? true : false"
      :has-map-layer="
        config.map_config && config.map_config[0] ? true : false
      "
      :has-history="config.history_config?.range ? true : false"
    />
  </Teleport>
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

button:hover {
	cursor: pointer;
}

::-webkit-scrollbar {
	width: 0px;
}

.dashboardcomponent {
	height: 330px;
	max-height: 330px;
	width: calc(100% - var(--font-m) * 2);
	max-width: calc(100% - var(--font-m) * 2);
	display: flex;
	flex-direction: column;
	justify-content: space-between;
	position: relative;
	padding: var(--font-m);
	border-radius: 5px;
	background-color: var(--color-component-background);

	@media (min-width: 1050px) {
		height: 370px;
		max-height: 370px;
	}

	@media (min-width: 1650px) {
		height: 400px;
		max-height: 400px;
	}

	@media (min-width: 2200px) {
		height: 500px;
		max-height: 500px;
	}

	&-header {
		display: flex;
		justify-content: space-between;
		overflow: visible;

		h3 {
			display: flex;
			font-size: var(--font-m);
			color: var(--color-normal-text);

			.componenttag {
				flex-shrink: 0;
				margin-top: 4px;
			}
		}

		h4 {
			display: flex;
			align-items: center;
			color: var(--color-complement-text);
			font-size: var(--font-s);
			font-weight: 400;
			overflow: visible;

			span {
				margin-left: 4px !important;
				margin: 0 4px;
				color: rgb(237, 90, 90) !important;
				font-size: 1rem;
				font-family: var(--font-icon);
				user-select: none;
			}

			h4 {
				color: rgb(237, 90, 90);
			}
		}

		p {
			color: var(--color-normal-text);
			font-size: var(--font-s);
			font-weight: 400;
		}

		div:first-child {
			div {
				display: flex;
				align-items: center;
			}

			span {
				margin-left: 8px;
				color: var(--color-complement-text);
				font-family: var(--font-icon);
				user-select: none;
			}
		}
		&-button {
			min-width: 48px;
			display: flex;
			justify-content: flex-end;
			align-items: flex-start;

			button span {
				color: var(--color-complement-text);
				font-family: var(--font-icon);
				font-size: calc(
					var(--font-l) *
						var(--font-to-icon)
				);
				transition: color 0.2s;

				&:hover {
					color: white;
				}
			}

			button.isfavorite span {
				color: rgb(255, 65, 44);

				&:hover {
					color: rgb(160, 112, 106);
				}
			}
		}

		&-toggle {
			min-height: var(--font-ms);
			min-width: 2rem;
			margin-top: 4px;
			display: flex;
			align-items: center;
			column-gap: 6px;
		}

		.ai-btn {
			display: flex;
			align-items: center;
			padding: 2px 6px;
			border: 1px solid var(--color-border);
			border-radius: 999px;
			background: transparent;
			color: var(--color-complement-text);
			cursor: pointer;
			transition: background 0.2s, color 0.2s, border-color 0.2s;

			span {
				color: var(--color-complement-text);
				font-family: var(--font-icon);
				font-size: 1rem;
				transition: color 0.2s;
			}

			&:hover,
			&.active {
				background: var(--color-highlight);
				border-color: var(--color-highlight);

				span {
					color: white;
				}
			}
		}

		@media (max-width: 760px) {
			button.isDelete {
				display: none !important;
			}
		}

		@media (min-width: 760px) {
			button.isFlag {
				display: none !important;
			}
		}

		@media (min-width: 759px) {
			button.isUnfavorite {
				display: none !important;
			}
		}
	}

	&-control {
		width: 100%;
		display: flex;
		// justify-content: center;
		align-items: center;
		// position: absolute;
		top: 4.2rem;
		left: 0;
		z-index: 8;
		padding: 8px 0;

		&-group {
			display: flex;
			justify-content: center;
			align-items: center;
			margin: 0 auto;
			transform: translateX(-15%);

			&-button {
				margin: 0 2px;
				padding: 4px 4px;
				border-radius: 5px;
				background-color: rgb(77, 77, 77);
				opacity: 0.6;
				color: var(--color-complement-text);
				font-size: var(--font-s);
				text-align: center;
				transition: color 0.2s, opacity 0.2s;
				user-select: none;
	
				&:hover {
					opacity: 1;
					color: white;
				}
			}
	
			&-active {
				background-color: var(--color-complement-text);
				color: white;
			}
		}

		.selectBtn {
			background-color: var(--color-component-background);
			padding: 3px;

			&-disabled {
				cursor: not-allowed;
			}
		}
	}

	&-chart,
	&-loading,
	&-error {
		height: 75%;
		position: relative;
		padding-top: 1%;
		overflow-y: scroll;

		p {
			color: var(--color-border);
		}
	}

	&-ai-panel {
		position: absolute;
		top: 2.6rem;
		left: var(--font-m);
		right: var(--font-m);
		z-index: 20;
		display: flex;
		flex-direction: column;
		row-gap: 8px;
		padding: 10px;
		border: 1px solid var(--color-border);
		border-radius: 8px;
		background: var(--color-component-background);
		box-shadow: 0 6px 16px rgba(0, 0, 0, 0.35);
		max-height: calc(100% - 3rem);
		overflow-y: auto;

		// In MapView (mode=map / halfmap) the card lives inside containers
		// that clip with overflow: hidden. The panel is teleported to
		// <body> and floats fixed beside the AI button (positioned via
		// inline style from aiPanelStyle).
		&.ai-panel-floating {
			position: fixed;
			width: 300px;
			max-width: calc(100vw - 32px);
			max-height: calc(100vh - 120px);
			padding: 8px;
			box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);
		}

		&-title {
			display: flex;
			align-items: center;
			justify-content: space-between;
			color: var(--color-normal-text);
			font-size: var(--font-s);
			font-weight: 700;

			button {
				background: none;
				border: none;
				cursor: pointer;
				color: var(--color-complement-text);

				span {
					font-family: var(--font-icon);
					font-size: 1rem;
				}
			}
		}
	}

	&-ai-suggestions {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;

		button {
			padding: 3px 8px;
			border: 1px solid var(--color-border);
			border-radius: 999px;
			background: transparent;
			color: var(--color-complement-text);
			font-size: var(--font-s);
			cursor: pointer;

			&:hover:not(:disabled) {
				color: var(--color-normal-text);
				border-color: var(--color-highlight);
			}
		}
	}

	&-ai-input {
		display: flex;
		column-gap: 6px;

		input {
			min-width: 0;
			flex: 1;
			padding: 6px 8px;
			border: 1px solid var(--color-border);
			border-radius: 6px;
			background: transparent;
			color: var(--color-normal-text);
			font-size: var(--font-s);
		}

		button {
			width: 32px;
			height: 32px;
			flex: 0 0 32px;
			border: none;
			border-radius: 50%;
			background: var(--color-highlight);
			color: white;
			cursor: pointer;

			span {
				font-family: var(--font-icon);
				font-size: 1rem;
			}
		}
	}

	&-ai-error {
		margin: 0;
		color: #ff8a8a;
		font-size: var(--font-s);
	}

	&-ai-result {
		color: var(--color-complement-text);
		font-size: var(--font-s);

		p {
			margin: 0;
			color: var(--color-normal-text);
		}

		ul {
			margin: 6px 0 0;
			padding-left: 18px;
		}

		&.is-clarify p {
			color: #ffd479;
		}
	}

	&-ai-insight {
		display: flex;
		align-items: flex-start;
		column-gap: 6px;
		margin-top: 6px;
		padding: 6px 8px;
		border-radius: 6px;
		background: rgba(255, 255, 255, 0.04);
		font-size: var(--font-s);
		color: var(--color-normal-text);

		.verdict-dot {
			margin-top: 6px;
			width: 8px;
			height: 8px;
			flex: 0 0 8px;
			border-radius: 50%;
			background: var(--color-complement-text);
		}

		&.verdict-easy .verdict-dot { background: #6bd47a; }
		&.verdict-balanced .verdict-dot { background: #f0c14b; }
		&.verdict-tight .verdict-dot { background: #ff6b6b; }
	}

	&-ai-followups {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		margin-top: 6px;

		button {
			padding: 3px 8px;
			border: 1px solid var(--color-border);
			border-radius: 999px;
			background: transparent;
			color: var(--color-complement-text);
			font-size: var(--font-s);
			cursor: pointer;

			&:hover:not(:disabled) {
				color: var(--color-normal-text);
				border-color: var(--color-highlight);
			}
		}
	}

	&-loading {
		display: flex;
		align-items: center;
		justify-content: center;

		div {
			width: 2rem;
			height: 2rem;
			border-radius: 50%;
			border: solid 4px var(--color-border);
			border-top: solid 4px var(--color-highlight);
			animation: spin 0.7s ease-in-out infinite;
		}
	}

	&-error {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;

		span {
			color: var(--color-complement-text);
			margin-bottom: 0.5rem;
			font-family: var(--font-icon);
			font-size: 2rem;
		}

		p {
			color: var(--color-complement-text);
		}
	}

	&-footer {
		height: 26px;
		display: flex;
		align-items: center;
		justify-content: space-between;
		overflow: visible;

		div {
			display: flex;
			align-items: center;
		}

		button,
		a {
			display: flex;
			align-items: center;
			transition: opacity 0.2s;

			&:hover {
				opacity: 0.8;
			}

			span {
				margin-left: 4px;
				color: var(--color-highlight);
				font-family: var(--font-icon);
				user-select: none;
			}

			p {
				max-height: 1.2rem;
				color: var(--color-highlight);
				user-select: none;
			}
		}
	}
}

@keyframes spin {
	to {
		transform: rotate(360deg);
	}
}

.large {
	height: 350px;
	max-height: 350px;

	@media (min-width: 820px) {
		height: 380px;
		max-height: 380px;
	}

	@media (min-width: 1200px) {
		height: 420px;
		max-height: 420px;
	}

	@media (min-width: 2200px) {
		height: 520px;
		max-height: 520px;
	}
}

.mapclosed {
	max-height: none;
	height: fit-content;
}

.compact {
	height: fit-content !important;
	max-height: none !important;

	.dashboardcomponent-chart {
		height: auto;
		overflow-y: visible;
	}
}

.mapopen {
	max-height: 330px;
	height: 330px;

	&-chart,
	&-loading {
		padding-top: 0%;
		height: 80%;
		position: relative;
		overflow-y: scroll;

		p {
			color: var(--color-border);
		}
	}
}

.half {
	height: 180px;
	max-height: 180px;

	@media (min-width: 1050px) {
		height: 210px;
		max-height: 210px;
	}

	@media (min-width: 1650px) {
		height: 225px;
		max-height: 225px;
	}

	@media (min-width: 2200px) {
		height: 275px;
		max-height: 275px;
	}

	&-chart,
	&-loading {
		height: 60%;
	}
}

.halfmapopen {
	height: 200px;
	max-height: 200px;

	&-chart {
		padding-top: 0;
		height: 75%;
	}
}

.preview {
	height: 170px;
	max-height: 170px;

	&-content {
		display: flex;
		justify-content: space-between;

		&-id {
			height: calc(100% - 2px);
			display: flex;
			flex-direction: column;
			justify-content: center;
			padding: 0 4px;
			border-radius: 5px;
			border: 1px dashed var(--color-complement-text);
			white-space: nowrap;
			margin-right: 4px;

			p {
				font-size: var(--font-s);
				color: var(--color-complement-text);
				text-overflow: ellipsis;
			}
		}

		&-charts {
			display: flex;
			column-gap: 4px;
			img {
				width: 40px;
				height: 40px;
				border-radius: 5px;
				background-color: var(
					--color-complement-text
				);
			}
		}
	}
}

.city {
	&-tag {
		&-container {
			margin: 4px 0;
			display: flex;
			gap: 5px;
	
			div:first-child {
				margin-left: 5px;
			}

			&-preview {
				display: flex;
				gap: 4px;
			}
		}
	}
}
</style>
