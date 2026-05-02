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

const now = new Date();
const currentSlot = ref(
	now.getHours() * SLOTS_PER_HOUR + Math.floor(now.getMinutes() / 15),
);
const playing = ref(false);
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

async function fetchSlot(slot) {
	if (!layerId.value) return;
	if (cache[slot]) {
		mapStore.updateTimeMapSource(layerId.value, cache[slot]);
		return;
	}
	const hour = Math.floor(slot / SLOTS_PER_HOUR);
	const quarter = slot % SLOTS_PER_HOUR;
	try {
		const res = await http.get(
			`/commute/youbike/map?city=all&hour=${hour}&quarter=${quarter}`,
		);
		cache[slot] = res.data;
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

function pauseIfPlaying() {
	if (playing.value) togglePlay();
}

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
    <!-- Legend -->
    <div class="youbike-timemap-legend">
      <span class="dot red" /><span>缺車 (&lt;10%)</span>
      <span class="dot orange" /><span>普通 (10–30%)</span>
      <span class="dot green" /><span>充足 (≥30%)</span>
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

    &-legend {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        column-gap: var(--font-ms);
        row-gap: 4px;
        font-size: var(--font-s);
        color: var(--color-complement-text);

        .dot {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            &.red    { background: #ef4444; }
            &.orange { background: #f97316; }
            &.green  { background: #22c55e; }
        }
    }
}
</style>
