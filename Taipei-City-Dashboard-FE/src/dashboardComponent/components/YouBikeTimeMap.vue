<!-- Developed by Taipei Urban Intelligence Center 2023-2024-->
<script setup>
import { ref, reactive, computed, watch, onUnmounted, onMounted } from "vue";
import { useMapStore } from "../../store/mapStore";
import http from "../../router/axios";

const props = defineProps([
	"chart_config",
	"activeChart",
	"activeCity",
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
// Dashboard-level dropdown (DashboardComponent's selectBtn) drives this:
// item.city is "taipei" → API "Taipei"; "metrotaipei" / anything else → "all" (雙北).
const cityFilter = computed(() => (props.activeCity === "taipei" ? "Taipei" : "all"));
const cache = reactive({});
const currentFeatures = ref([]);

const stats = computed(() => {
	let empty = 0;
	let full = 0;
	for (const feat of currentFeatures.value) {
		const props = feat.properties || {};
		const avail = Number(props.avg_available);
		const total = Number(props.total_docks);
		if (!Number.isFinite(avail) || !Number.isFinite(total) || total <= 0) continue;
		if (avail <= 0) empty++;
		else if (avail >= total) full++;
	}
	return { empty, full, total: currentFeatures.value.length };
});

let playInterval = null;
let debounceTimer = null;
let unmounted = false;
let prefetching = false;

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
		if (slot === currentSlot.value) {
			currentFeatures.value = cache[key].features || [];
		}
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
		if (slot === currentSlot.value) {
			currentFeatures.value = res.data.features || [];
		}
	} catch (e) {
		console.warn("YouBikeTimeMap fetchSlot failed", e);
	}
}

async function prefetchAll() {
	if (prefetching) return;
	prefetching = true;
	try {
		for (let s = 0; s < TOTAL_SLOTS; s++) {
			if (unmounted) return;
			await fetchSlot(s);
			await new Promise((resolve) => setTimeout(resolve, 50));
		}
	} finally {
		prefetching = false;
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
		break;
	}
	case "focus_location": {
		if (!Array.isArray(payload.center) || payload.center.length !== 2) return;
		if (!mapStore.map) return;
		mapStore.easeToLocation([
			payload.center,
			Number.isFinite(payload.zoom) ? payload.zoom : 15,
			Number.isFinite(payload.pitch) ? payload.pitch : 45,
			Number.isFinite(payload.bearing) ? payload.bearing : 0,
			payload.place || "AI 指定位置",
		]);
		if (Number.isFinite(payload.radius_meters)) {
			drawAIHighlight(payload.center, payload.radius_meters, payload.verdict);
		} else {
			clearAIHighlight();
		}
		break;
	}
	default:
		break;
	}
}

const HIGHLIGHT_RING_SOURCE = "youbike-ai-highlight-ring";
const HIGHLIGHT_FILL_LAYER = "youbike-ai-highlight-fill";
const HIGHLIGHT_LINE_LAYER = "youbike-ai-highlight-line";
const HIGHLIGHT_CENTER_SOURCE = "youbike-ai-highlight-center-src";
const HIGHLIGHT_CENTER_LAYER = "youbike-ai-highlight-center";

const VERDICT_COLOR = {
	easy: "#6bd47a",
	balanced: "#f0c14b",
	tight: "#ff6b6b",
};

function makeRingPolygon(center, radiusMeters, points = 96) {
	const [lng, lat] = center;
	const earthMpDegLat = 111000;
	const dLat = radiusMeters / earthMpDegLat;
	const cosLat = Math.cos((lat * Math.PI) / 180);
	const dLng = radiusMeters / (earthMpDegLat * Math.max(cosLat, 0.01));
	const ring = [];
	for (let i = 0; i <= points; i++) {
		const t = (i / points) * 2 * Math.PI;
		ring.push([lng + dLng * Math.cos(t), lat + dLat * Math.sin(t)]);
	}
	return {
		type: "Feature",
		geometry: { type: "Polygon", coordinates: [ring] },
		properties: {},
	};
}

function clearAIHighlight() {
	const {map} = mapStore;
	if (!map) return;
	for (const id of [
		HIGHLIGHT_FILL_LAYER,
		HIGHLIGHT_LINE_LAYER,
		HIGHLIGHT_CENTER_LAYER,
	]) {
		if (map.getLayer(id)) map.removeLayer(id);
	}
	for (const id of [HIGHLIGHT_RING_SOURCE, HIGHLIGHT_CENTER_SOURCE]) {
		if (map.getSource(id)) map.removeSource(id);
	}
}

function drawAIHighlight(center, radiusMeters, verdict) {
	const {map} = mapStore;
	if (!map || !Array.isArray(center) || !radiusMeters) return;
	clearAIHighlight();
	const color = VERDICT_COLOR[verdict] || "#ffd479";

	map.addSource(HIGHLIGHT_RING_SOURCE, {
		type: "geojson",
		data: {
			type: "FeatureCollection",
			features: [makeRingPolygon(center, radiusMeters)],
		},
	});
	map.addLayer({
		id: HIGHLIGHT_FILL_LAYER,
		type: "fill",
		source: HIGHLIGHT_RING_SOURCE,
		paint: { "fill-color": color, "fill-opacity": 0.12 },
	});
	map.addLayer({
		id: HIGHLIGHT_LINE_LAYER,
		type: "line",
		source: HIGHLIGHT_RING_SOURCE,
		paint: { "line-color": color, "line-width": 2 },
	});

	map.addSource(HIGHLIGHT_CENTER_SOURCE, {
		type: "geojson",
		data: {
			type: "FeatureCollection",
			features: [
				{
					type: "Feature",
					geometry: { type: "Point", coordinates: center },
					properties: {},
				},
			],
		},
	});
	map.addLayer({
		id: HIGHLIGHT_CENTER_LAYER,
		type: "circle",
		source: HIGHLIGHT_CENTER_SOURCE,
		paint: {
			"circle-radius": 7,
			"circle-color": color,
			"circle-stroke-color": "#1a1a1a",
			"circle-stroke-width": 2,
		},
	});
}

defineExpose({ applyAIEvent, getComponentState, clearAIHighlight });

// Fetch slot 0 immediately so the stats panel populates as soon as the
// component mounts, even on tabs with no map context. Then wait for the
// map source to appear and re-apply (cache hit) so the visual layer also
// matches the slider's starting position.
onMounted(async () => {
	fetchSlot(currentSlot.value);
	for (let i = 0; i < 30; i++) {
		if (
			layerId.value &&
			mapStore.map?.getSource(`${layerId.value}-source`)
		) {
			fetchSlot(currentSlot.value);
			return;
		}
		await new Promise((r) => setTimeout(r, 200));
	}
});

onUnmounted(() => {
	unmounted = true;
	clearInterval(playInterval);
	clearTimeout(debounceTimer);
	clearAIHighlight();
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
    <!-- Per-slot station stats -->
    <div class="youbike-timemap-stats">
      <div class="stat-row">
        <span class="stat-dot empty" />
        <span class="stat-label">無車站點</span>
        <span class="stat-value">{{ stats.empty }}</span>
        <span class="stat-of">/ {{ stats.total }}</span>
      </div>
      <div class="stat-row">
        <span class="stat-dot full" />
        <span class="stat-label">滿車站點</span>
        <span class="stat-value">{{ stats.full }}</span>
        <span class="stat-of">/ {{ stats.total }}</span>
      </div>
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

    &-stats {
        display: flex;
        flex-direction: column;
        row-gap: 12px;
        padding: 12px;
        margin-bottom: 16px;
        border: 1px solid var(--color-border);
        border-radius: 6px;
        background: var(--color-component-background);

        .stat-row {
            display: flex;
            align-items: center;
            column-gap: 8px;
            font-size: var(--font-s);
            line-height: 1;

            .stat-dot {
                width: 10px;
                height: 10px;
                border-radius: 50%;
                flex-shrink: 0;

                &.empty { background: #ff6b6b; }
                &.full { background: #4dabf7; }
            }

            .stat-label {
                color: var(--color-complement-text);
                flex: 1;
            }

            .stat-value {
                font-weight: 700;
                color: var(--color-normal-text);
                font-variant-numeric: tabular-nums;
            }

            .stat-of {
                color: var(--color-complement-text);
                font-variant-numeric: tabular-nums;
            }
        }
    }
}
</style>
