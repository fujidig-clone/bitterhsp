import Compiler;
import AXData;
import Set;
using Mixin;

@:expose
class Toy1 {
	public static function main() {
		if (untyped __js__("typeof process") != "undefined") {
			main_nodejs();
		}
        }
	public static function main_nodejs() {
		var path, binary: String;
		untyped {
			path = process.argv[2];
			if (path == null) path = "t.ax";
			binary = require("fs").readFileSync(path).toString("binary");
		}
		new Toy1(binary).main_();
	}

	public function main_() {
		var stat = copy();
		for (p in this.procedures) {
			var names = [for (proc in stat[p].procs) proc.name].join(", ");
			trace('${p.name}: ${stat[p].num} ${names}');
		}
		trace("--------------------------------------------------");
		var start = Date.now();
		trace(start);
		this.thereAreCallsAtWaitCommand = true;
		this.specialize();
		for (p in this.procedures) {
			trace('${p.name}: ${this.specialized[p]}');
		}
		var n = this.countInsns();
		var nn = this.countSpecializedInsns();
		var end = Date.now();
		trace('${nn / n} (${nn} / ${n})');
		trace(end);
		trace((end.getTime() - start.getTime()) / 1000);
	}

	var sequence: Instruction;
	var userDefFuncs: Array<UserDefFunc>;
	public var procedures: Array<Procedure>;
	var mainProcedure: Procedure;
	var labelToProc = new Map<Label, Procedure>();
	var handlerSubs: Array<Label>;
	public var thereAreCallsAtWaitCommand: Bool;

	var specialized: Map<Procedure,Int>;
	var history: Array<Procedure>;

	public function new(binary:String) {
		var compiled = new Compiler(binary).compile();
		this.sequence = compiled.sequence;
		this.userDefFuncs = compiled.userDefFuncs.filter(function(x) return x != null);
		setupProcedures();
		this.handlerSubs = listHandlerEntryPoints(JumpType.Gosub);
		for (p in this.procedures) labelToProc[p.label] = p;
	}
	function collectHandlers() {
		for (insn in eachInsn()) {
			switch (insn.opts) {
			case Insn.Call_builtin_handler_cmd(type,code,jumpType,label,argc):
				trace('${type} ${code} ${jumpType} ${label.name}');
			case Insn.Call_builtin_cmd(TokenType.PROGCMD, 0x11, _): // stop
				trace('stop');
			case Insn.Call_builtin_cmd(TokenType.PROGCMD, 0x07, _): // wait
				trace('wait');
			case Insn.Call_builtin_cmd(TokenType.PROGCMD, 0x08, _): // await
				trace('await');
			default:
			}
		}
	}
	function countInsns() {
		var num = 0;
		for (p in this.procedures) {
			if (this.specialized[p] >= 1) {
				num += p.insns.length;
			}
		}
		return num;
	}
	function countSpecializedInsns() {
		var num = 0;
		for (p in this.procedures) {
			num += this.specialized[p] * p.insns.length;
		}
		return num;
	}
	function specialize() {
		this.history = [];
		this.specialized = new Map();
		for (p in this.procedures) {
			this.specialized[p] = 0;
		}
		this.specialize0(this.procedures[0]);
		return this.specialized;
	}
	function specialize0(p:Procedure) {
		this.specialized[p] += 1;
		if (this.history.indexOf(p) >= 0) {
			// 再帰呼び出し
			return;
		}
		for (insn in p.insns) {
			for (label in getLabelsFromCallInsn(insn)) {
				var proc = this.labelToProc[label];
				this.history.push(p);
				specialize0(proc);
				this.history.pop();
			}
		}
	}

	function getLabelsFromCallInsn(insn:Instruction) {
		switch (insn.opts) {
		case Insn.Call_userdef_cmd(u,_):
			return [u.label];
		case Insn.Call_userdef_func(u,_):
			return [u.label];
		case Insn.Gosub(label):
			return [label];
		case Insn.On(labels,JumpType.Gosub):
			return labels;
		case Insn.Call_builtin_cmd(TokenType.PROGCMD, 0x11, _), // stop
		     Insn.Call_builtin_cmd(TokenType.PROGCMD, 0x07, _), // wait
		     Insn.Call_builtin_cmd(TokenType.PROGCMD, 0x08, _): // await
			if (this.thereAreCallsAtWaitCommand) {
				return this.handlerSubs;
			} else {
				return [];
			}
		default:
			return [];
		}
	}


	public function copy() {
		var used = new Map<Instruction,Procedure>();
		var stat = new Map<Procedure,CopyStat>();
		for (p in this.procedures) {
			var copied = new Map();
			var labels = [p.label];
			// button gotoなどの行き先はメイン手続きに含める
			if (p == this.mainProcedure) {
				labels.pushAll(this.listHandlerEntryPoints(JumpType.Goto));
			}
			for (label in labels) {
				// ラベルのinsnプロパティを書き換えることによって
				// すべての呼び出し元の飛び先も変わる。ハッキーかも
				var newInsn = copyProcedureBody(label.insn, copied);
				label.insn = newInsn;
			}

			// 統計
			var num = 0;
			var procs = new Set(new Map());
			p.insns = [];
			for (i in copied.keys()) {
				if (used[i] != null) {
					num += 1;
					procs.add(used[i]);
				} else {
					used[i] = p;
				}
				p.insns.push(copied[i]);
			}
			stat[p] = {num: num, procs: procs};
		}
		return stat;
	}
	function copyProcedureBody(insn:Instruction, copied:Map<Instruction,Instruction>) {
		// [XXX] 深さ優先探索だとスタックを食いつぶしてしまうかもしれないから
		// 幅優先探索にした方がよい
		if (copied[insn] != null) return copied[insn];
		var newInsn = new Instruction(insn.opts, insn.fileName, insn.lineNumber, null, insn.origPos);
		copied[insn] = newInsn;
		switch (insn.opts) {
		case Insn.Goto(label):
			newInsn.opts = Insn.Goto(new Label(copyProcedureBody(label.insn, copied)));
		case Insn.Ifne(label):
			newInsn.opts = Insn.Ifne(new Label(copyProcedureBody(label.insn, copied)));
			newInsn.next = copyProcedureBody(insn.next, copied);
		case Insn.Ifeq(label):
			newInsn.opts = Insn.Ifeq(new Label(copyProcedureBody(label.insn, copied)));
			newInsn.next = copyProcedureBody(insn.next, copied);
		case Insn.Return:
			// do nothing
		case Insn.Call_builtin_cmd(TokenType.PROGCMD, 0x10, _), // end
		     Insn.Call_builtin_cmd(TokenType.PROGCMD, 0x11, _): // stop
			// do nothing
		default:
			newInsn.next = copyProcedureBody(insn.next, copied);
		}
		return newInsn;
	}
	function setupProcedures() {
		this.mainProcedure = new Procedure(null, new Label(this.sequence), "(main)");
		var subRoutines = [for (l in listSubroutines()) new Procedure(null, l, "*"+l.name)];
		var funcs = [for (f in this.userDefFuncs) new Procedure(f, f.label, f.name)];
		var procs = [this.mainProcedure].concat(subRoutines).concat(funcs);
		procs.sort(function (a, b) return a.insn().origPos - b.insn().origPos);
		this.procedures = procs;
	}
	// buttonやoncmdなどの飛び先をリストする
	function listHandlerEntryPoints(jumpType:JumpType): Array<Label> {
		var labelsSet = new Set<Label>(new Map());
		for (insn in eachInsn()) {
			switch (insn.opts) {
			case Insn.Call_builtin_handler_cmd(type,code,j,label,argc):
				if (j == jumpType) labelsSet.add(label);
			default:
			}
		}
		return labelsSet.toArray();
	}
	function listSubroutines(): Array<Label> {
		var labelsSet = new Set<Label>(new Map());
		for (insn in eachInsn()) {
			switch(insn.opts) {
			case Insn.Gosub(label):
				labelsSet.add(label);
			case Insn.On(labels,JumpType.Gosub):
				for (label in labels) labelsSet.add(label);
			case Insn.Call_builtin_handler_cmd(type,code,jumpType=JumpType.Gosub,label,argc):
				labelsSet.add(label);
			default:
			}
		}
		return labelsSet.toArray();
	}
	function eachInsn() {
		var insn = this.sequence;
		return {
			hasNext: function() return insn != null,
			next: function() {
				var cur = insn;
				insn = insn.next;
				return cur;
			}
		};
	}
}

typedef CopyStat = {
	var num: Int;
	var procs: Set<Procedure>;
}

class ThereIsRecursion { public function new() {} }

class Procedure {
	public var userDefFunc: UserDefFunc;
	public var label: Label;
	public var name: String;
	public var insns: Array<Instruction>;

	public function new(userDefFunc, label, name) {
		this.userDefFunc = userDefFunc;
		this.label = label;
		this.name = name;
	}

	public function insn() {
		return this.label.insn;
	}
}
