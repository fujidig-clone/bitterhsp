class Set<K> {
	var map: Map<K,Bool>;
	public function new(map) {
		this.map = map;
	}

	public function add(k:K): Void {
		this.map.set(k, true);
	}
	public function addAll(keys:Iterable<K>) {
		for (k in keys) {
			add(k);
		}
	}
	public function has(k:K): Bool {
		return this.map.exists(k);
	}
	public function remove(k:K) {
		return this.map.remove(k);
	}
	public function iterator(): Iterator<K> {
		return this.map.keys();
	}
	public function toArray(): Array<K> {
		return [for (x in this.map.keys()) x];
	}
}
