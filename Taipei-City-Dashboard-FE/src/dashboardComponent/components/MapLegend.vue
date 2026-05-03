<!-- Developed by Taipei Urban Intelligence Center 2023-2024-->

<script setup>
import { computed, ref, watch } from "vue";
import axios from "axios";
import bus from "../assets/map/bus.png";
import metro from "../assets/map/metro.png";
import triangle_green from "../assets/map/triangle_green.png";
import triangle_white from "../assets/map/triangle_white.png";
import bike_green from "../assets/map/bike_green.png";
import bike_orange from "../assets/map/bike_orange.png";
import bike_red from "../assets/map/bike_red.png";
import cross_bold from "../assets/map/cross_bold.png";
import cross_normal from "../assets/map/cross_normal.png";
import cctv from "../assets/map/cctv.png";
import live from "../assets/map/live.png";

const props = defineProps([
	"chart_config",
	"series",
	"map_config",
	"map_filter",
	"map_filter_on",
	"activeCity",
]);
const emits = defineEmits([
	"filterByParam",
	"filterByLayer",
	"clearByParamFilter",
	"clearByLayerFilter",
	"fly"
]);

function returnIcon(name) {
	switch (name) {
	case "bus":
		return bus;
	case "metro":
		return metro;
	case "triangle_green":
		return triangle_green;
	case "triangle_white":
		return triangle_white;
	case "bike_green":
		return bike_green;
	case "bike_orange":
		return bike_orange;
	case "bike_red":
		return bike_red;
	case "cross_bold":
		return cross_bold;
	case "cross_normal":
		return cross_normal;
	case "cctv":
		return cctv;
	case "live":
		return live;
	default:
		return "";
	}
}

const selectedIndex = ref(null);
const selectedRouteName = ref("");
const routeSearch = ref("");
const routeOptions = ref([]);
const routeFilterOpen = ref(false);

const isBusCongestionLayer = computed(() =>
	props.map_config?.some((config) => config?.index?.startsWith("bus_congestion_"))
);

const activeCityScope = computed(() =>
	props.activeCity || props.map_config?.[0]?.city || "metrotaipei"
);

const filteredRouteOptions = computed(() => {
	const query = routeSearch.value.trim().toLowerCase();
	if (!query) return routeOptions.value;
	return routeOptions.value.filter((routeName) =>
		routeName.toLowerCase().includes(query),
	);
});

function featureMatchesCity(properties) {
	const city = properties?.city || properties?.route;
	if (activeCityScope.value === "taipei") {
		return city === "台北市";
	}
	return ["台北市", "新北市"].includes(city);
}

async function loadRouteOptions() {
	if (!isBusCongestionLayer.value) {
		routeOptions.value = [];
		return;
	}
	const routeNames = new Set();
	try {
		const res = await axios.get("/mapData/bus_congestion_routes.json");
		(res.data?.routes || []).forEach((route) => {
			if (featureMatchesCity(route) && route.route_name) {
				routeNames.add(String(route.route_name));
			}
		});
	} catch (e) {
		console.error("Failed to load bus route options", e);
	}

	const targetConfigs = props.map_config
		?.filter((config) => config?.index?.startsWith("bus_congestion_"))
		.slice(0, 1) || [];

	if (routeNames.size === 0) {
		await Promise.all(
			targetConfigs.map(async (config) => {
				try {
					const res = await axios.get(`/mapData/${config.index}.geojson`);
					(res.data?.features || []).forEach((feature) => {
						const properties = feature.properties || {};
						if (featureMatchesCity(properties) && properties.route_name) {
							routeNames.add(String(properties.route_name));
						}
					});
				} catch (e) {
					console.error(`Failed to load route options for ${config.index}`, e);
				}
			})
		);
	}

	routeOptions.value = Array.from(routeNames).sort((a, b) =>
		a.localeCompare(b, "zh-Hant-u-kn-true")
	);

	if (
		selectedRouteName.value &&
		!routeOptions.value.includes(selectedRouteName.value)
	) {
		clearRouteFilter();
	}
}

function handleDataSelection(index) {
	if (!props.map_filter || !props.map_filter_on) {
		return;
	}
	if (index !== selectedIndex.value) {
		// Supports filtering by xAxis
		if (props.map_filter.mode === "byParam") {
			emits(
				"filterByParam",
				props.map_filter,
				props.map_config,
				props.series[index].name,
				null
			);
		}
		// Supports filtering by xAxis
		else if (props.map_filter.mode === "byLayer") {
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

function applyRouteFilter(routeName) {
	selectedIndex.value = null;
	selectedRouteName.value = routeName;
	routeFilterOpen.value = false;
	emits(
		"filterByParam",
		{ mode: "byParam", byParam: { xParam: "route_name" } },
		props.map_config,
		routeName,
		null
	);
}

function clearRouteFilter() {
	selectedRouteName.value = "";
	routeSearch.value = "";
	emits("clearByParamFilter", props.map_config);
}

watch(
	() => [props.map_config, activeCityScope.value],
	() => {
		selectedRouteName.value = "";
		routeSearch.value = "";
		loadRouteOptions();
	},
	{ immediate: true, deep: true }
);
</script>

<template>
  <div class="maplegend">
    <div
      v-if="isBusCongestionLayer && map_filter_on"
      class="maplegend-route-filter"
    >
      <button
        type="button"
        class="maplegend-route-filter-toggle"
        :class="{ active: selectedRouteName }"
        @click="routeFilterOpen = !routeFilterOpen"
      >
        <span class="material-icons">search</span>
        <span>{{ selectedRouteName || "公車路線" }}</span>
      </button>
      <button
        v-if="selectedRouteName"
        type="button"
        class="maplegend-route-filter-clear"
        aria-label="清除公車路線篩選"
        @click="clearRouteFilter"
      >
        <span class="material-icons">close</span>
      </button>
      <div
        v-if="routeFilterOpen"
        class="maplegend-route-filter-panel"
      >
        <input
          v-model="routeSearch"
          type="search"
          placeholder="搜尋路線"
        >
        <div class="maplegend-route-filter-options">
          <button
            v-for="routeName in filteredRouteOptions"
            :key="routeName"
            type="button"
            :class="{ selected: selectedRouteName === routeName }"
            @click="applyRouteFilter(routeName)"
          >
            {{ routeName }}
          </button>
        </div>
      </div>
    </div>
    <div class="maplegend-legend">
      <button
        v-for="(item, index) in series"
        :key="item.name"
        :class="{
          'maplegend-legend-item': true,
          'maplegend-filter': map_filter_on && map_filter,
          'maplegend-selected':
            map_filter_on && selectedIndex === index,
        }"
        @click="handleDataSelection(index)"
      >
        <!-- Show different icons for different map types -->
        <div
          v-if="item.type !== 'symbol'"
          :style="{
            backgroundColor: `${chart_config.color[index]}`,
            height: item.type === 'line' ? '0.4rem' : '1rem',
            borderRadius: item.type === 'circle' ? '50%' : '2px',
          }"
        />
        <img
          v-else
          :src="returnIcon(item.icon)"
        >
        <!-- If there is a value attached, show the value -->
        <div v-if="item.value !== undefined && item.value !== null">
          <h5>{{ item.name }}</h5>
          <h6>{{ item.value }} {{ chart_config.unit }}</h6>
        </div>
        <div v-else>
          <h6>{{ item.name }}</h6>
        </div>
      </button>
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
.maplegend {
	width: 100%;
	height: 100%;
	display: flex;
	flex-direction: column;
	align-items: center;
	justify-content: center;
	margin-top: -var(--font-ms);
	overflow: visible;

	&-route-filter {
		position: relative;
		width: 100%;
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin-bottom: 0.6rem;
		overflow: visible;

		&-toggle {
			min-width: 0;
			flex: 1;
			display: flex;
			align-items: center;
			gap: 0.35rem;
			height: 2rem;
			padding: 0 0.65rem;
			border: 1px solid var(--color-border);
			border-radius: 5px;
			color: var(--color-normal-text);
			background-color: var(--color-component-background);
			cursor: pointer;

			span:last-child {
				overflow: hidden;
				text-overflow: ellipsis;
				white-space: nowrap;
			}

			.material-icons {
				flex: 0 0 auto;
				font-size: 1rem;
			}

			&.active {
				border-color: var(--color-highlight);
				color: var(--color-highlight);
			}
		}

		&-clear {
			width: 2rem;
			height: 2rem;
			display: grid;
			place-items: center;
			border: 1px solid var(--color-border);
			border-radius: 5px;
			color: var(--color-complement-text);
			cursor: pointer;

			.material-icons {
				font-size: 1rem;
			}
		}

		&-panel {
			position: absolute;
			top: calc(100% + 0.35rem);
			left: 0;
			z-index: 5;
			width: 100%;
			padding: 0.5rem;
			border: 1px solid var(--color-border);
			border-radius: 5px;
			background-color: var(--color-component-background);
			box-shadow: 0 6px 16px rgba(0, 0, 0, 0.22);
			overflow: visible;

			input {
				width: 100%;
				height: 2rem;
				padding: 0 0.55rem;
				border: 1px solid var(--color-border);
				border-radius: 4px;
				color: var(--color-normal-text);
				background-color: transparent;
				font-size: 0.85rem;
			}
		}

		&-options {
			max-height: 11rem;
			margin-top: 0.45rem;
			display: grid;
			gap: 0.25rem;
			overflow-y: auto;

			button {
				min-height: 1.8rem;
				padding: 0.25rem 0.45rem;
				border-radius: 4px;
				color: var(--color-normal-text);
				text-align: left;
				cursor: pointer;

				&:hover,
				&.selected {
					background-color: rgba(255, 255, 255, 0.08);
				}
			}
		}
	}

	&-legend {
		width: 100%;
		display: grid;
		grid-template-columns: 1fr 1fr;
		column-gap: 0.5rem;
		row-gap: 0.5rem;
		overflow: visible;

		&-item {
			display: flex;
			align-items: center;
			padding: 5px 10px 5px 5px;
			border: 1px solid transparent;
			border-radius: 5px;
			transition: box-shadow 0.2s;
			cursor: auto;

			div:first-child,
			img {
				width: var(--font-ms);
				margin-right: 0.75rem;
			}

			h5 {
				color: var(--color-complement-text);
				font-size: 0.75rem;
				text-align: left;
			}

			h6 {
				color: var(--color-normal-text);
				font-size: var(--font-ms);
				font-weight: 400;
				text-align: left;
			}
		}
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
}
</style>
