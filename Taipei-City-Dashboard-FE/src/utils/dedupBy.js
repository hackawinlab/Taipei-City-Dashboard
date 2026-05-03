export function dedupBy(items, keyFn) {
	const seen = new Set();
	return items.filter((item) => {
		const key = keyFn(item);
		if (seen.has(key)) return false;
		seen.add(key);
		return true;
	});
}
