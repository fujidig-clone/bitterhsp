import js.html.ArrayBuffer;
import js.html.DataView;
import js.html.Uint8Array;

class BinaryReader {
	var view: DataView;
	var length: Int;
	var littleEndian: Bool;
	public var cursor: Int;
	public function new(str: String, littleEndian = true) {
		this.view = new DataView(BinaryReader.makeBuffer(str));
		this.length = str.length;
		this.littleEndian = littleEndian;
		this.cursor = 0;
	}
	
	static function makeBuffer(str: String): ArrayBuffer {
		var length = str.length;
		var buf = new ArrayBuffer(Math.max(length, 1));
		var bufView = new Uint8Array(buf);
		for (i in 0...length) {
			bufView[i] = str.charCodeAt(i);
		}
		return buf;
	}

	public function isEOS(): Bool {
		return this.cursor == this.length;
	}

	public function readInt8(): Int {
		var v = this.view.getInt8(this.cursor);
		this.cursor += 1;
		return v;
	}

	public function readUint8(): Int {
		var v = this.view.getUint8(this.cursor);
		this.cursor += 1;
		return v;
	}

	public function readInt16(): Int {
		var v = this.view.getInt16(this.cursor, this.littleEndian);
		this.cursor += 2;
		return v;
	}

	public function readUint16(): Int {
		var v = this.view.getUint16(this.cursor, this.littleEndian);
		this.cursor += 2;
		return v;
	}

	public function readInt32(): Int {
		var v = this.view.getInt32(this.cursor, this.littleEndian);
		this.cursor += 4;
		return v;
	}

	public function readUint32(): Int {
		var v = this.view.getUint32(this.cursor, this.littleEndian);
		this.cursor += 4;
		return v;
	}

	public function readDouble(): Float {
		var v = this.view.getFloat64(this.cursor, this.littleEndian);
		this.cursor += 8;
		return v;
	}

	public function readUint24(): Int {
		var v;
		if (this.littleEndian) {
			v = this.view.getUint8(this.cursor)
					+ 0x100 * this.view.getUint8(this.cursor + 1)
					+ 0x10000 * this.view.getUint8(this.cursor + 2);
		} else {
			v = this.view.getUint8(this.cursor + 2)
					+ 0x100 * this.view.getUint8(this.cursor + 1)
					+ 0x10000 * this.view.getUint8(this.cursor);
		}
		this.cursor += 3;
		return v;
	}

	public static function main() {
		var r = new BinaryReader("\x01\x02\x03");
		trace(r.readInt8());
		trace(r.readInt16());
	}
}
