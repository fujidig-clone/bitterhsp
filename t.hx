import js.Node;
import Compiler;

class Set<K> {
	var map: Map<K,Bool>;
	public function new(map) {
		this.map = map;
	}

	public function add(k:K): Void {
		this.map.set(k, true);
	}
	public function has(k:K): Bool {
		return this.map.exists(k);
	}
	public function iterator(): Iterator<K> {
		return this.map.keys();
	}
	public function toArray(): Array<K> {
		return [for (x in this.map.keys()) x];
	}
}

class T {
	static function main(){
		Node.global.BitterHSP = Node.require("./compiler");
		var path = Sys.args()[2];
		if (path == null) path = "hsp-programs/hello/hello.ax";
		var binary = Node.fs.readFileSync(path).toString("binary");
		var compiler = new Compiler(binary);
		var compiled = compiler.compile();
		var userDefFuncs = compiled.userDefFuncs;
		var s = T.listSubroutines(compiled.sequence)[0];
		trace(Std.string(collectSubRoutineBody(s).toArray()));
	}

	static function collectSubRoutineBody(subRoutine:SubRoutine) {
		var label = T.toLabel(subRoutine);
		var q = [label.insn];
		var bodyInsns = new Set<Instruction>(new Map());
		while (q.length > 0) {
			var insn = q.shift();
			if (bodyInsns.has(insn)) continue;
			bodyInsns.add(insn);
			switch (insn.opts) {
			case Insn.Goto(label):
				q.push(label.insn);
			case Insn.Ifne(label):
				q.push(label.insn);
				q.push(insn.next);
			case Insn.Ifeq(label):
				q.push(label.insn);
				q.push(insn.next);
			case Insn.Return:
				// do nothing
			default:
				q.push(insn.next);
			}
		}
		return bodyInsns;
	}

	static function toLabel(subRoutine:SubRoutine) {
		switch (subRoutine) {
		case SubRoutine.func(u): return u.label;
		case SubRoutine.subRoutine(label): return label;
		}
	}

	static function listSubroutines(sequence:Instruction): Array<SubRoutine> {
		var labelsSet = new Set<Label>(new Map());
		var insn = sequence;
		while (insn != null) {
			switch(insn.opts) {
			case Insn.Gosub(label):
				labelsSet.add(label);
			case Insn.On(labels,isGosub=true):
				for (label in labels) labelsSet.add(label);
			case Insn.Call_builtin_handler_cmd(_,_,isGosub=true,label,_):
				labelsSet.add(label);
			default:
			}
			insn = insn.next;
		}
		return [for (label in labelsSet) SubRoutine.subRoutine(label)];
	}
}

enum SubRoutine {
	func(userDefFunc:UserDefFunc);
	subRoutine(label:Label);
}
