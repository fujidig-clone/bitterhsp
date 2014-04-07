import Compiler;
import AXData;
import Set;
using Mixin;

@:expose
class Toy2 {
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
		new Toy2(binary).main_();
	}

	public function main_() {
		for (insn in eachInsn()) {
			var id = retrieveVarFromInitializeCommand(insn);
			if (id != null) {
				trace('${insn}: ${id}');
			}
		}
		//var stat = copy();
	}

	var sequence: Instruction;
	var userDefFuncs: Array<UserDefFunc>;
	public var procedures: Array<Procedure>;
	var mainProcedure: Procedure;
	var labelToProc = new Map<Label, Procedure>();

	public function new(binary:String) {
		var compiled = new Compiler(binary).compile();
		this.sequence = compiled.sequence;
		this.userDefFuncs = compiled.userDefFuncs.filter(function(x) return x != null);
		setupProcedures();
		for (p in this.procedures) labelToProc[p.label] = p;
	}
	function retrieveVarFromInitializeCommand(insn:Instruction): Null<Int> {
		switch (insn.opts) {
		case Assign(insn2, _):
			switch (insn2.opts) {
			case Push_var(id,_):
				return id;
			default:
			}
		default:
		}
		return null;
	}
	function copy() {
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
			case Insn.On(_,labels,JumpType.Gosub):
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
