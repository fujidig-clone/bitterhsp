class Mixin {
	static function pushAll<T>(array: Array<T>, other:Array<T>) {
		for (x in other) array.push(x);
	}
}
