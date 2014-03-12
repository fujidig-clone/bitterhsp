class Mixin {
	static function pushAll<T>(array: Array<T>, other:Array<T>) {
		for (x in other) array.push(x);
	}

	static function pushAt<K,V>(map: Map<K,Array<V>>, key: K, val: V) {
		if (map[key] == null) map[key] = [];
		map[key].push(val);
	}
}
