import Compiler;
import AXData;
import Set;

@:expose
class Toy1 {
	public static function main() {
		if (untyped __js__("typeof process") != "undefined") {
			main_nodejs();
		}
        }
	public static function run(binary: String) {
		var compiler = new Compiler(binary);
		return new Toy1(compiler.compile()).run_();
	}
	function run_() {
		var dup = copy();
		var buf = new StringBuf();
		for (p in this.procedures) {
			buf.add('${p.name}: ${dup[p]}\n');
		}
		return buf.toString();
	}
	public static function main_nodejs() {
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
		return;
		this.specialize();
		for (p in this.procedures) {
			trace('${p.name}: ${this.specialized[p]}');
		}
	}

	var sequence: Instruction;
	var userDefFuncs: Array<UserDefFunc>;
	var procedures: Array<Procedure>;
	var labelToProc = new Map<Label, Procedure>();

	var specialized: Map<Procedure,Int>;
	var history: Array<Procedure>;

	public function new(compiled:CompileResult) {
		this.sequence = compiled.sequence;
		this.userDefFuncs = compiled.userDefFuncs.filter(function(x) return x != null);
		this.procedures = listProcedures();
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
	function specialize() {
		this.history = [];
		this.specialized = new Map();
		for (p in this.procedures) {
			this.specialized[p] = 0;
		}
		this.specialize0(this.procedures[0]);
	}
	function specialize0(p:Procedure) {
		if (this.history.indexOf(p) >= 0) {
			trace(p.name);
			trace(p.insn().fileName);
			throw new ThereIsRecursion();
		}
		this.specialized[p] += 1;
		trace(p.name);
		for (insn in p.insns) {
			trace('${insn} ${getLabelsFromCallInsn(insn)}');
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
		default:
			return [];
		}
	}


	function copy() {
		var used = new Set(new Map());
		var dup = new Map<Procedure,Int>();
		for (p in this.procedures) {
			var copied = new Map();
			var newHead = copyProcedureBody(p.insn(), copied);
			dup[p] = 0;
			p.insns = [];
			for (i in copied.keys()) {
				if (used.has(i)) {
					dup[p] += 1;
				}
				used.add(i);
				p.insns.push(copied[i]);
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
