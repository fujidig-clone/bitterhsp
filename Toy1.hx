import Compiler;
import AXData;
import Set;

class Toy1 {
	public static function main() {
		var path, binary: String;
		untyped {
			path = process.argv[2];
			if (path == null) path = "t.ax";
			binary = require("fs").readFileSync(path).toString("binary");
		}
		var compiler = new Compiler(binary);
		new Toy1(compiler.compile()).main_();
	}

	public function main_() {
		var dup = copy();
		for (p in this.procedures) {
			trace('${p.name}: ${dup[p]}');
		}
	}

	var sequence: Instruction;
	var userDefFuncs: Array<UserDefFunc>;
	var procedures: Array<Procedure>;

	public function new(compiled:CompileResult) {
		this.sequence = compiled.sequence;
		this.userDefFuncs = compiled.userDefFuncs.filter(function(x) return x != null);
		this.procedures = listProcedures();
	}
	function copy() {
		var used = new Set(new Map());
		var dup = new Map<Procedure,Int>();
		for (p in this.procedures) {
			var copied = new Map();
			var newHead = copyProcedureBody(p.insn(), copied);
			dup[p] = 0;
			for (i in copied.keys()) {
				if (used.has(i)) {
					dup[p] += 1;
				}
				used.add(i);
			}
			// ラベルのinsnプロパティを書き換えることによって
			// すべての呼び出し元の飛び先も変わる。ハッキーかも
			p.label.insn = newHead;
		}
		return dup;
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
	function listProcedures() {
		var main = new Procedure(null, new Label(this.sequence), "(main)");
		var subRoutines = [for (l in listSubroutines()) new Procedure(null, l, "*"+l.name)];
		var funcs = [for (f in this.userDefFuncs) new Procedure(f, f.label, f.name)];
		var procs = [main].concat(subRoutines).concat(funcs);
		procs.sort(function (a, b) return a.insn().origPos - b.insn().origPos);
		return procs;
	}
	function listSubroutines(): Array<Label> {
		var labelsSet = new Set<Label>(new Map());
		for (insn in eachInsn()) {
			switch(insn.opts) {
			case Insn.Gosub(label):
				labelsSet.add(label);
			case Insn.On(labels,isGosub=true):
				for (label in labels) labelsSet.add(label);
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

class Procedure {
	public var userDefFunc: UserDefFunc;
	public var label: Label;
	public var name: String;

	public function new(userDefFunc, label, name) {
		this.userDefFunc = userDefFunc;
		this.label = label;
		this.name = name;
	}

	public function insn() {
		return this.label.insn;
	}
}
