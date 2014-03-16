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
			trace('${procName(p)}: ${dup[procName(p)]}');
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
		// [XXX] ProcedureをキーにしたMapを使うとEnumValueMapが使われて
		// 動作がおかしいのでかりそめとしてStringをキーにする
		var dup = new Map<String,Int>();
		for (p in this.procedures) {
			var copied = new Map();
			var newHead = copyProcedureBody(procHead(p), copied);
			var name = procName(p);
			dup[name] = 0;
			for (i in copied.keys()) {
				if (used.has(i)) {
					dup[name] += 1;
				}
				used.add(i);
			}
			setProcHead(p, newHead);
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
		var main = Procedure.subRoutine(new Label(this.sequence, "(main)"));
		var subRoutines = [for (s in listSubroutines()) Procedure.subRoutine(s)];
		var funcs = [for (f in this.userDefFuncs) Procedure.func(f)];
		var procs = [main].concat(subRoutines).concat(funcs);
		procs.sort(function (a, b) return procHead(a).origPos - procHead(b).origPos);
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
	static function setProcHead(proc: Procedure, insn: Instruction) {
		// ラベルのinsnプロパティを書き換えることによって
		// すべての呼び出し元の飛び先も変わる。ハッキーかも
		switch (proc) {
		case Procedure.func(u):
			u.label.insn = insn;
		case Procedure.subRoutine(l):
			l.insn = insn;
		}
	}
	static function procHead(proc: Procedure) {
		switch (proc) {
		case Procedure.func(u):
			return u.label.insn;
		case Procedure.subRoutine(l):
			return l.insn;
		}
	}
	static function procName(proc: Procedure) {
		switch (proc) {
		case Procedure.func(u):
			return u.name;
		case Procedure.subRoutine(l):
			return "*"+l.name;
		}
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

enum Procedure {
	func(userDefFunc:UserDefFunc);
	subRoutine(label:Label);
}

