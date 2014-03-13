using Mixin;

class AXData {
	public var version: Int;
	public var max_val: Int;
	public var bootoption: Int;
	public var runtime: Int;

	var data: String;
	var cs: String;
	var ds: String;
	var ot: String;
	var dinfo: String;
	var linfo: String;
	var finfo: String;
	var minfo: String;
	var finfo2: String;
	var hpidat: String;

	public var tokens: Array<Token>;
	public var variableNames: Array<String>;
	public var labelNames: Array<String>;
	public var paramNames: Array<String>;
	public var funcsInfo: Array<FuncInfo>;
	public var prmsInfo: Array<PrmInfo>;
	public var labels: Array<Int>;
	public var labelsMap: Map<Int, Array<Int>>;

	public function new(data: String) {
		this.data = data;
		var r = new BinaryReader(data.substr(0, 96));

		var h1 = r.readInt8();
		var h2 = r.readInt8();
		var h3 = r.readInt8();
		var h4 = r.readInt8();
		if (h1 != 0x48 || h2 != 0x53 || h3 != 0x50 || h4 != 0x33) {
			throw new js.Error('invalid hsp object data');
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

	function createTokens(): Array<Token> {
		var tokens: Array<Token> = [];
		var cs = new BinaryReader(this.cs);
		var dinfo = new BinaryReader(this.dinfo);
		var pos = 0;
		var fileName = null, lineNo = 0, lineSize = 0;
		while (!cs.isEOS()) {
			var c = cs.readUint16();
			var type = c & 0x0fff;
			var ex1 = (c & 0x2000) != 0;
			var ex2 = (c & 0x4000) != 0;
			var code = (c & 0x8000) != 0 ? cs.readInt32() : cs.readUint16();
			var skipOffset = 0;
			if (type == TokenType.CMPCMD) {
				skipOffset = cs.readUint16();
			}
			var size = Std.int(cs.cursor / 2) - pos;
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
					if (dsOffset != 0 || fileName == null) {
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

	function createSymbolNames() {
		var dinfo = new BinaryReader(this.dinfo);
		this.variableNames = this.createVariableNames(dinfo);
		this.labelNames = this.createLabelNames(dinfo);
		this.paramNames = this.createLabelNames(dinfo);
	}

	function createVariableNames(dinfo: BinaryReader): Array<String> {
		var variableNames: Array<String> = [];
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

	function createLabelNames(dinfo: BinaryReader): Array<String> {
		var labelNames: Array<String> = [];
		while (true) {
			var ofs = dinfo.readUint8();
			if (ofs == 255) break;
			if (ofs != 251) return [];
			var dsPos = dinfo.readUint24();
			var i = dinfo.readUint16();
			labelNames[i] = this.getDSStr(dsPos);
		}
		return labelNames;
	}

	function createFuncsInfo(): Array<FuncInfo> {
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

	function createPrmsInfo(): Array<PrmInfo> {
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

	function createLabels(): Array<Int> {
		var p = new BinaryReader(this.ot);
		var labels = new Array<Int>();
		while(!p.isEOS()) {
			var pos = p.readInt32();
			labels.push(pos);
		}
		return labels;
	}

	function createLabelsMap(labels: Array<Int>): Map<Int, Array<Int>> {
		// key: position in cs, val: array of label ids
		var labelsMap = new Map();

		for (i in 0...labels.length) {
			labelsMap.pushAt(labels[i], i);
		}
		return labelsMap;
	}

	function getDSStr(index: Int) {
		return AXData.getCStr(this.ds, index);
	}

	function getDSDouble(index: Int) {
		return new BinaryReader(this.ds.substr(0, 8)).readDouble();
	}

	static function getCStr(str: String, index: Int) {
		var end = str.indexOf("\x00", index);
		if (end < 0) end = str.length;
		return str.substring(index, end);
	}
}

class Token {
	public var type: Int;
	public var ex1: Bool;
	public var ex2: Bool;
	public var code: Int;
	public var val: Int;
	public var fileName: String;
	public var lineNumber: Int;
	public var pos: Int;
	public var size: Int;
	public var skipOffset: Int;
	public var stringValue: String;
	public var doubleValue: Float;

	public function new(type, ex1, ex2, code, fileName, lineNumber,
				pos, size, skipOffset, stringValue, doubleValue) {
		this.type = type;
		this.ex1 = ex1;
		this.ex2 = ex2;
		this.code = this.val = code;
		this.fileName = fileName;
		this.lineNumber = lineNumber;
		this.pos = pos;
		this.size = size;
		this.skipOffset = skipOffset;
		this.stringValue = stringValue;
		this.doubleValue = doubleValue;
	}
}

class FuncInfo {
	public var index: Int;
	public var subid: Int;
	public var prmindex: Int;
	public var prmmax: Int;
	public var nameidx: Int;
	public var size: Int;
	public var otindex: Int;
	public var funcflag: Int;
	public var name: String;

	public function new(index, subid, prmindex, prmmax,
	                    nameidx, size, otindex, funcflag, name) {
		this.index = index;
		this.subid = subid;
		this.prmindex = prmindex;
		this.prmmax = prmmax;
		this.nameidx = nameidx;
		this.size = size;
		this.otindex = otindex;
		this.funcflag = funcflag;
		this.name = name;
	}
}

class PrmInfo {
	public var mptype: Int;
	public var subid: Int;
	public var offset: Int;

	public function new(mptype, subid, offset) {
		this.mptype = mptype;
		this.subid = subid;
		this.offset = offset;
	}
}

class TokenType {
	public static var MARK      = 0;
	public static var VAR       = 1;
	public static var STRING    = 2;
	public static var DNUM      = 3;
	public static var INUM      = 4;
	public static var STRUCT    = 5;
	public static var XLABEL    = 6;
	public static var LABEL     = 7;
	public static var INTCMD    = 8;
	public static var EXTCMD    = 9;
	public static var EXTSYSVAR = 10;
	public static var CMPCMD    = 11;
	public static var MODCMD    = 12;
	public static var INTFUNC   = 13;
	public static var SYSVAR    = 14;
	public static var PROGCMD   = 15;
	public static var DLLFUNC   = 16;
	public static var DLLCTRL   = 17;
	public static var USERDEF   = 18;
}


class MPType {
	public static var NONE        = 0;
	public static var VAR         = 1;
	public static var STRING      = 2;
	public static var DNUM        = 3;
	public static var INUM        = 4;
	public static var STRUCT      = 5;
	public static var LABEL       = 7;
	public static var LOCALVAR    = -1;
	public static var ARRAYVAR    = -2;
	public static var SINGLEVAR   = -3;
	public static var FLOAT       = -4;
	public static var STRUCTTAG   = -5;
	public static var LOCALSTRING = -6;
	public static var MODULEVAR   = -7;
	public static var PPVAL       = -8;
	public static var PBMSCR      = -9;
	public static var PVARPTR     = -10;
	public static var IMODULEVAR  = -11;
	public static var IOBJECTVAR  = -12;
	public static var LOCALWSTR   = -13;
	public static var FLEXSPTR    = -14;
	public static var FLEXWPTR    = -15;
	public static var PTR_REFSTR  = -16;
	public static var PTR_EXINFO  = -17;
	public static var PTR_DPMINFO = -18;
	public static var NULLPTR     = -19;
	public static var TMODULEVAR  = -20;
}
