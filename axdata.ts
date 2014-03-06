///<reference path="binary-reader.ts"/>

module BitterHSP {
    export class AXData {
        version: number;
        max_val: number;
        bootoption: number;
        runtime: number;

        private cs: string;
        private ds: string;
        private ot: string;
        private dinfo: string;
        private linfo: string;
        private finfo: string;
        private minfo: string;
        private finfo2: string;
        private hpidat: string;

        public tokens: Array<Token>;
        public variableNames: Array<string>;

        constructor(private data: string) {
            var r = new BinaryReader(data.substr(0, 96));

            var h1 = r.readInt8();
            var h2 = r.readInt8();
            var h3 = r.readInt8();
            var h4 = r.readInt8();
            if (h1 != 0x48 || h2 != 0x53 || h3 != 0x50 || h4 != 0x33) {
                throw new Error('invalid hsp object data');
            }
            this.version = r.readInt32();
            this.max_val = r.readInt32();
            var allsize = r.readInt32();
            var pt_cs = r.readInt32();
            var max_cs = r.readInt32();
            var pt_ds = r.readInt32();
            var max_ds = r.readInt32();
            var pt_ot = r.readInt32();
            var max_ot = r.readInt32();
            var pt_dinfo = r.readInt32();
            var max_dinfo = r.readInt32();
            var pt_linfo = r.readInt32();
            var max_linfo = r.readInt32();
            var pt_finfo = r.readInt32();
            var max_finfo = r.readInt32();
            var pt_minfo = r.readInt32();
            var max_minfo = r.readInt32();
            var pt_finfo2 = r.readInt32();
            var max_finfo2 = r.readInt32();
            var pt_hpidat = r.readInt32();
            var max_hpi = r.readInt16();
            var max_varhpi = r.readInt16();
            this.bootoption = r.readInt32();
            this.runtime = r.readInt32();
            this.cs = data.substr(pt_cs, max_cs);
            this.ds = data.substr(pt_ds, max_ds);
            this.ot = data.substr(pt_ot, max_ot);
            this.dinfo = data.substr(pt_dinfo, max_dinfo);
            this.linfo = data.substr(pt_linfo, max_linfo);
            this.finfo = data.substr(pt_finfo, max_finfo);
            this.minfo = data.substr(pt_minfo, max_minfo);
            this.finfo2 = data.substr(pt_finfo2, max_finfo2);
            this.hpidat = data.substr(pt_hpidat, max_hpi);

            this.tokens = this.createTokens();
            this.variableNames = this.createVariableNames();
        }

        private createTokens(): Array<Token> {
            var tokens: Array<Token> = [];
            var cs = new BinaryReader(this.cs);
            var dinfo = new BinaryReader(this.dinfo);
            var pos = 0;
            var fileName = "", lineNo = 0, lineSize = 0;
            while (!cs.isEOS()) {
                var c = cs.readUint16();
                var type = c & 0x0fff;
                var ex1 = (c & 0x2000) != 0;
                var ex2 = (c & 0x4000) != 0;
                var code = (c & 0x8000) ? cs.readInt32() : cs.readUint16();
                var skipOffset = 0;
                if (type == TokenType.CMPCMD) {
                    skipOffset = cs.readUint16();
                }
                var size = cs.cursor / 2 - pos;
                var stringValue = (type == TokenType.STRING) ? this.getDSStr(code) : null;
                var doubleValue = (type == TokenType.DNUM) ? this.getDSDouble(code) : null;
                while (true) {
                    var dinfoPos = dinfo.cursor;
                    var ofs = dinfo.readUint8();
                    if (ofs == 255) {
                        dinfo.cursor = dinfoPos;
                        break;
                    }
                    if (ofs == 254) {
                        var dsOffset = dinfo.readUint24();
                        if (dsOffset != 0 || fileName == undefined) {
                            fileName = this.getDSStr(dsOffset);
                        }
                        lineNo = dinfo.readUint16();
                        continue;
                    }
                    if (ofs == 253) {
                        dinfo.readUint24();
                        dinfo.readUint16();
                        continue;
                    }
                    if (ofs == 252) {
                        ofs = dinfo.readUint16();
                    }
                    if (lineSize < ofs) {
                        dinfo.cursor = dinfoPos;
                        break;
                    }
                    lineSize = 0;
                    lineNo++;
                }
                lineSize += size;
                tokens.push(new Token(type, ex1, ex2, code,
                    fileName, lineNo, pos, size, skipOffset, stringValue, doubleValue));
                pos += size;
            }
            return tokens;
        }

        private createVariableNames() {
            var variableNames = new Array<string>(this.max_val);
            var dinfo = new BinaryReader(this.dinfo);
            var i = 0;
            while (true) {
                var ofs = dinfo.readUint8();
                if (ofs == 255) break;
                if (ofs == 254) {
                    dinfo.readUint24();
                    dinfo.readUint16();
                }
                if (ofs == 253) {
                    variableNames[i++] = this.getDSStr(dinfo.readUint24());
                    dinfo.readUint16();
                }
                if (ofs == 252) {
                    ofs = dinfo.readUint16();
                }
            }
            return variableNames;
        }

        private getDSStr(index: number) {
            return AXData.getCStr(this.ds, index);
        }

        private getDSDouble(index: number) {
            return new BinaryReader(this.ds.slice(0, 8)).readDouble();
        }

        private static getCStr(str: string, index: number) {
            var end = str.indexOf("\0", index);
            if (end < 0) end = str.length;
            return str.slice(index, end);
        }
    }
    export class Token {
        constructor(public type: number, public ex1: boolean, public ex2: boolean,
            public code: number, public fileName: string, public lineNumber: number,
            public pos: number, public size: number, public skipSize: number,
            public stringValue: string, public doubleValue: number) { }
    }

    enum TokenType {
        MARK = 0,
        VAR = 1,
        STRING = 2,
        DNUM = 3,
        INUM = 4,
        STRUCT = 5,
        XLABEL = 6,
        LABEL = 7,
        INTCMD = 8,
        EXTCMD = 9,
        EXTSYSVAR = 10,
        CMPCMD = 11,
        MODCMD = 12,
        INTFUNC = 13,
        SYSVAR = 14,
        PROGCMD = 15,
        DLLFUNC = 16,
        DLLCTRL = 17,
        USERDEF = 18,
    }
}
