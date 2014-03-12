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
		trace(Std.string(T.listSubroutines(compiled.sequence)));
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
