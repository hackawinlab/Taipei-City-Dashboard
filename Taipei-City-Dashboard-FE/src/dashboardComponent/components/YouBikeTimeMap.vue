<!-- Developed by Taipei Urban Intelligence Center 2023-2024-->
<script setup>
import { ref, computed, watch, onUnmounted } from "vue";
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

const currentHour = ref(new Date().getHours());
const playing = ref(false);
const cache = ref({});

let playInterval = null;
let debounceTimer = null;

const layerId = computed(() => {
	if (!props.map_config || props.map_config.length === 0) return null;
	const cfg = props.map_config[0];
	return `${cfg.index}-${cfg.type}-${cfg.city}`;
});

async function fetchHour(hour) {
	if (!layerId.value) return;
	if (cache.value[hour]) {
		mapStore.updateTimeMapSource(layerId.value, cache.value[hour]);
		return;
	}
	try {
		const res = await http.get(`/commute/youbike/map?city=all&hour=${hour}`);
		cache.value[hour] = res.data;
		mapStore.updateTimeMapSource(layerId.value, res.data);
	} catch {
		// silently ignore fetch errors during play/drag
	}
}

async function prefetchAll() {
	for (let h = 0; h < 24; h++) {
		if (!cache.value[h]) {
			await fetchHour(h);
			await new Promise((resolve) => setTimeout(resolve, 100));
		}
	}
}

function togglePlay() {
	if (playing.value) {
		clearInterval(playInterval);
		playInterval = null;
		playing.value = false;
	} else {
		playing.value = true;
		prefetchAll();
		playInterval = setInterval(() => {
			currentHour.value = (currentHour.value + 1) % 24;
		}, 800);
	}
}

watch(currentHour, (h) => {
	clearTimeout(debounceTimer);
	debounceTimer = setTimeout(() => fetchHour(h), 200);
});

onUnmounted(() => {
	clearInterval(playInterval);
	clearTimeout(debounceTimer);
});
</script>

<template>
  <div class="youbike-timemap">
    <!-- Header: hour label + play button -->
    <div class="youbike-timemap-header">
      <span class="hour-label">{{ String(currentHour).padStart(2, "0") }}:00</span>
      <button
        class="play-btn"
        @click="togglePlay"
      >
        <span>{{ playing ? "pause" : "play_arrow" }}</span>
      </button>
    </div>
    <!-- Slider -->
    <div class="youbike-timemap-slider">
      <span>00:00</span>
      <input
        v-model.number="currentHour"
        type="range"
        min="0"
        max="23"
        step="1"
        @mousedown="if (playing) togglePlay()"
      >
      <span>23:00</span>
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
