///<reference path="binary-reader.ts"/>

module BitterHSP {
    export interface NumDictionary<V> {
        [index: number]: V;
    }

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
        public labelNames: Array<string>;
        public funcsInfo: Array<FuncInfo>;
        public prmsInfo: Array<PrmInfo>;
        public labels: Array<number>;
        public labelsMap: NumDictionary<Array<number>>;

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
            this.createSymbolNames();
            this.funcsInfo = this.createFuncsInfo();
            this.prmsInfo = this.createPrmsInfo();
            this.labels = this.createLabels();
            this.labelsMap = this.createLabelsMap(this.labels);
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

        private createSymbolNames() {
            var dinfo = new BinaryReader(this.dinfo);
            this.variableNames = this.createVariableNames(dinfo);
            this.labelNames = this.createLabelNames(dinfo);
        }

        private createVariableNames(dinfo: BinaryReader): Array<string> {
            var variableNames = new Array<string>(this.max_val);
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

        private createLabelNames(dinfo: BinaryReader): Array<string> {
            var labelNames = new Array<string>(this.ot.length / 4);
            if (dinfo.readUint8() != 254) return [];
            while (true) {
                var ofs = dinfo.readUint8();
                console.log(ofs);
                if (ofs == 255) break;
                if (ofs != 253) return [];
                var dsPos = dinfo.readUint24();
                var i = dinfo.readUint16();
                labelNames[i] = this.getDSStr(dsPos);
            }
            return labelNames;
        }

        private createFuncsInfo(): Array<FuncInfo> {
            var funcsInfo = new Array<FuncInfo>();
            var finfo = new BinaryReader(this.finfo);
            while(!finfo.isEOS()) {
                var index = finfo.readInt16();
                var subid = finfo.readInt16();
                var prmindex = finfo.readInt32();
                var prmmax = finfo.readInt32();
                var nameidx = finfo.readInt32();
                var size = finfo.readInt32();
                var otindex = finfo.readInt32();
                var funcflag = finfo.readInt32();
                var name = this.getDSStr(nameidx);
                funcsInfo.push(new FuncInfo(index, subid, prmindex, prmmax,
                                            nameidx, size, otindex, funcflag, name));
            }
            return funcsInfo;
        }

        private createPrmsInfo(): Array<PrmInfo> {
            var prmsInfo = new Array<PrmInfo>();
            var minfo = new BinaryReader(this.minfo);
            while(!minfo.isEOS()) {
                var mptype = minfo.readInt16();
                var subid = minfo.readInt16();
                var offset = minfo.readInt32();
                prmsInfo.push(new PrmInfo(mptype, subid, offset));
            }
            return prmsInfo;
        }

        private createLabels(): Array<number> {
            var p = new BinaryReader(this.ot);
            var labels = new Array<number>();
            while(!p.isEOS()) {
                var pos = p.readInt32();
                labels.push(pos);
            }
            return labels;
        }

        private createLabelsMap(labels: Array<number>): NumDictionary<Array<number>> {
            // key: position in cs, val: array of label ids
            var labelsMap = Object.create(null);

            labels.forEach((x, i) => {
                if (x in labelsMap) {
                    labelsMap[x].push(i);
                } else {
                    labelsMap[x] = [i];
                }
            });
            return labelsMap;
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
        public val: number;
        constructor(public type: number, public ex1: boolean, public ex2: boolean,
                    public code: number, public fileName: string, public lineNumber: number,
                    public pos: number, public size: number, public skipOffset: number,
                    public stringValue: string, public doubleValue: number) {
            this.val = this.code;
        }
    }

    export class FuncInfo {
        constructor(public index: number, public subid: number,
                    public prmindex: number, public prmmax: number,
                    public nameidx: number, public size: number,
                    public otindex: number, public funcflag: number,
                    public name: string) {}
    }

    export class PrmInfo {
        constructor(public mptype: number, public subid: number, public offset: number) {}
    }

    export enum TokenType {
        MARK      = 0,
        VAR       = 1,
        STRING    = 2,
        DNUM      = 3,
        INUM      = 4,
        STRUCT    = 5,
        XLABEL    = 6,
        LABEL     = 7,
        INTCMD    = 8,
        EXTCMD    = 9,
        EXTSYSVAR = 10,
        CMPCMD    = 11,
        MODCMD    = 12,
        INTFUNC   = 13,
        SYSVAR    = 14,
        PROGCMD   = 15,
        DLLFUNC   = 16,
        DLLCTRL   = 17,
        USERDEF   = 18,
    }


    export enum MPType {
        NONE        = 0,
        VAR         = 1,
        STRING      = 2,
        DNUM        = 3,
        INUM        = 4,
        STRUCT      = 5,
        LABEL       = 7,
        LOCALVAR    = -1,
        ARRAYVAR    = -2,
        SINGLEVAR   = -3,
        FLOAT       = -4,
        STRUCTTAG   = -5,
        LOCALSTRING = -6,
        MODULEVAR   = -7,
        PPVAL       = -8,
        PBMSCR      = -9,
        PVARPTR     = -10,
        IMODULEVAR  = -11,
        IOBJECTVAR  = -12,
        LOCALWSTR   = -13,
        FLEXSPTR    = -14,
        FLEXWPTR    = -15,
        PTR_REFSTR  = -16,
        PTR_EXINFO  = -17,
        PTR_DPMINFO = -18,
        NULLPTR     = -19,
        TMODULEVAR  = -20,
    }
}
