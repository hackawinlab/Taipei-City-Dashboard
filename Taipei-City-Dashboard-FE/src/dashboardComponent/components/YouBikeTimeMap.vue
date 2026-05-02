<!-- Developed by Taipei Urban Intelligence Center 2023-2024-->
<script setup>
import { ref, reactive, computed, watch, onUnmounted } from "vue";
import { useMapStore } from "../../store/mapStore";
import http from "../../router/axios";

const props = defineProps([
	"chart_config",
	"activeChart",
	"series",
	"map_config",
	"map_filter",
	"map_filter_on",
]);

const mapStore = useMapStore();

const SLOTS_PER_HOUR = 4;
const TOTAL_SLOTS = 24 * SLOTS_PER_HOUR; // 96

const currentSlot = ref(0);
const playing = ref(false);
const cityFilter = ref("all"); // "all" = 雙北, "Taipei" = 台北市
const cache = reactive({});

let playInterval = null;
let debounceTimer = null;
let unmounted = false;

const layerId = computed(() => {
	if (!props.map_config || props.map_config.length === 0) return null;
	const cfg = props.map_config[0];
	return `${cfg.index}-${cfg.type}-${cfg.city}`;
});

const currentLabel = computed(() => {
	const h = Math.floor(currentSlot.value / SLOTS_PER_HOUR);
	const m = (currentSlot.value % SLOTS_PER_HOUR) * 15;
	return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
});

function cacheKey(slot) {
	return `${cityFilter.value}:${slot}`;
}

async function fetchSlot(slot) {
	if (!layerId.value) return;
	const key = cacheKey(slot);
	if (cache[key]) {
		mapStore.updateTimeMapSource(layerId.value, cache[key]);
		return;
	}
	const hour = Math.floor(slot / SLOTS_PER_HOUR);
	const quarter = slot % SLOTS_PER_HOUR;
	try {
		const res = await http.get(
			`/commute/youbike/map?city=${cityFilter.value}&hour=${hour}&quarter=${quarter}`,
		);
		cache[key] = res.data;
		mapStore.updateTimeMapSource(layerId.value, res.data);
	} catch (e) {
		console.warn("YouBikeTimeMap fetchSlot failed", e);
	}
}

async function prefetchAll() {
	for (let s = 0; s < TOTAL_SLOTS; s++) {
		if (unmounted) return;
		await fetchSlot(s);
		await new Promise((resolve) => setTimeout(resolve, 50));
	}
}

function togglePlay() {
	if (playing.value) {
		clearInterval(playInterval);
		playInterval = null;
		playing.value = false;
	} else {
		if (playInterval) return; // guard rapid-toggle race
		playing.value = true;
		prefetchAll();
		playInterval = setInterval(() => {
			currentSlot.value = (currentSlot.value + 1) % TOTAL_SLOTS;
		}, 350);
	}
}

watch(currentSlot, (s) => {
	clearTimeout(debounceTimer);
	debounceTimer = setTimeout(() => fetchSlot(s), 150);
});

watch(cityFilter, () => {
	clearTimeout(debounceTimer);
	debounceTimer = setTimeout(() => fetchSlot(currentSlot.value), 100);
});

function setCity(value) {
	if (cityFilter.value === value) return;
	if (playing.value) togglePlay();
	cityFilter.value = value;
}

function pauseIfPlaying() {
	if (playing.value) togglePlay();
}

function getMapBoundsSnapshot() {
	if (!mapStore.map) return null;
	const bounds = mapStore.map.getBounds();
	return {
		north: bounds.getNorth(),
		south: bounds.getSouth(),
		east: bounds.getEast(),
		west: bounds.getWest(),
	};
}

function getComponentState() {
	return {
		city_scope: cityFilter.value,
		current_slot: currentSlot.value,
		current_time: currentLabel.value,
		map_bounds: getMapBoundsSnapshot(),
	};
}

function applyAIEvent(event) {
	if (!event || !event.action) return;
	const payload = event.payload || {};
	switch (event.action) {
	case "set_time_slot": {
		const nextSlot = Number(payload.slot);
		if (!Number.isInteger(nextSlot) || nextSlot < 0 || nextSlot >= TOTAL_SLOTS) {
			return;
		}
		pauseIfPlaying();
		currentSlot.value = nextSlot;
		fetchSlot(nextSlot);
		break;
	}
	case "focus_location": {
		if (!Array.isArray(payload.center) || payload.center.length !== 2) return;
		if (!mapStore.map) return;
		mapStore.easeToLocation([
			payload.center,
			payload.zoom || 15,
			payload.pitch || 45,
			payload.bearing || 0,
			payload.place || "AI 指定位置",
		]);
		break;
	}
	default:
		break;
	}
}

defineExpose({ applyAIEvent, getComponentState });

onUnmounted(() => {
	unmounted = true;
	clearInterval(playInterval);
	clearTimeout(debounceTimer);
});
</script>

<template>
  <div
    v-if="activeChart === 'YouBikeTimeMap'"
    class="youbike-timemap"
  >
    <!-- Header: time label + play button -->
    <div class="youbike-timemap-header">
      <span class="hour-label">{{ currentLabel }}</span>
      <div class="youbike-timemap-city">
        <button
          :class="{ active: cityFilter === 'Taipei' }"
          @click="setCity('Taipei')"
        >
          台北市
        </button>
        <button
          :class="{ active: cityFilter === 'all' }"
          @click="setCity('all')"
        >
          雙北
        </button>
      </div>
      <button
        class="play-btn"
        @click="togglePlay"
      >
        <span>{{ playing ? "pause" : "play_arrow" }}</span>
      </button>
    </div>
    <!-- Slider (96 × 15-min slots) -->
    <div class="youbike-timemap-slider">
      <span>00:00</span>
      <input
        v-model.number="currentSlot"
        type="range"
        min="0"
        :max="TOTAL_SLOTS - 1"
        step="1"
        @mousedown="pauseIfPlaying"
        @touchstart="pauseIfPlaying"
      >
      <span>23:45</span>
    </div>
  </div>
</template>

<style scoped lang="scss">
.youbike-timemap {
    padding: var(--font-s);
    display: flex;
    flex-direction: column;
    row-gap: var(--font-s);

    &-header {
        display: flex;
        align-items: center;
        justify-content: space-between;

        .hour-label {
            font-size: var(--font-xl);
            font-weight: 700;
            color: var(--color-highlight);
        }
        .play-btn {
            background: none;
            border: none;
            cursor: pointer;
            span {
                font-family: var(--font-icon);
                font-size: 1.5rem;
                color: var(--color-highlight);
            }
        }
    }

    &-city {
        display: flex;
        column-gap: 4px;

        button {
            padding: 2px 10px;
            border: 1px solid var(--color-border);
            border-radius: 999px;
            background: transparent;
            color: var(--color-complement-text);
            font-size: var(--font-s);
            cursor: pointer;
            transition: background 0.2s, color 0.2s, border-color 0.2s;

            &:hover { color: var(--color-normal-text); }

            &.active {
                background: var(--color-highlight);
                border-color: var(--color-highlight);
                color: var(--color-normal-text);
            }
        }
    }

    &-slider {
        display: flex;
        align-items: center;
        column-gap: var(--font-s);

        input[type="range"] {
            flex: 1;
            accent-color: var(--color-highlight);
            cursor: pointer;
        }
        span { font-size: var(--font-s); color: var(--color-complement-text); }
    }
}
</style>
