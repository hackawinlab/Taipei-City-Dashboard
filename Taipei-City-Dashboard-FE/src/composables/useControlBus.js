const handlers = new Map(); // action → Set<fn>

export function useControlBus() {
	return {
		on(action, fn) {
			if (!handlers.has(action)) handlers.set(action, new Set());
			handlers.get(action).add(fn);
			return () => handlers.get(action)?.delete(fn);
		},
		emit(action, payload) {
			handlers.get(action)?.forEach((fn) => fn(payload));
		},
	};
}
