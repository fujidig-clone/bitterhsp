module BitterHSP {
    export class BinaryReader {
        private view: DataView;
        private length: number;
        public cursor: number;
        constructor(str: string, private littleEndian = true) {
            this.view = new DataView(BinaryReader.makeBuffer(str));
            this.length = str.length;
            this.cursor = 0;
        }

        private static makeBuffer(str: string): ArrayBuffer {
            var length = str.length;
            var buf = new ArrayBuffer(length);
            var bufView = new Uint8Array(buf);
            for (var i = 0; i < length; i++) {
                bufView[i] = str.charCodeAt(i);
            }
            return buf;
        }

        isEOS(): boolean {
            return this.cursor == this.length;
        }

        readInt8(): number {
            var v = this.view.getInt8(this.cursor);
            this.cursor += 1;
            return v;
        }

        readUint8(): number {
            var v = this.view.getUint8(this.cursor);
            this.cursor += 1;
            return v;
        }

        readInt16(): number {
            var v = this.view.getInt16(this.cursor);
            this.cursor += 2;
            return v;
        }

        readUint16(): number {
            var v = this.view.getUint16(this.cursor, this.littleEndian);
            this.cursor += 2;
            return v;
        }

        readInt32(): number {
            var v = this.view.getInt32(this.cursor, this.littleEndian);
            this.cursor += 4;
            return v;
        }

        readUint32(): number {
            var v = this.view.getUint32(this.cursor, this.littleEndian);
            this.cursor += 4;
            return v;
        }

        readDouble(): number {
            var v = this.view.getFloat64(this.cursor, this.littleEndian);
            this.cursor += 8;
            return v;
        }

        readUInt24(): number {
            if (this.littleEndian) {
                var v = this.view.getInt8(this.cursor)
                        + 0x100 * this.view.getInt8(this.cursor + 1)
                        + 0x10000 * this.view.getInt8(this.cursor + 2);
            } else {
                var v = this.view.getInt8(this.cursor + 2)
                        + 0x100 * this.view.getInt8(this.cursor + 1)
                        + 0x10000 * this.view.getInt8(this.cursor);
            }
            this.cursor += 3;
            return v;
        }
    }
}
