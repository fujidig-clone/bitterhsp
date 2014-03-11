import js.Node;
import Compiler;

class T {
	static function main(){
		Node.global.BitterHSP = Node.require("./compiler");
		var path = Sys.args()[2];
		if (path == null) path = "hsp-programs/hello/hello.ax";
		var binary = Node.fs.readFileSync(path).toString("binary");
		var compiler = new Compiler(binary);
		var sequence = compiler.compile();
		var userDefFuncs = compiler.userDefFuncs;
		trace(Std.string(T.collectSubroutines(sequence)));
	}

	static function collectSubroutines(sequence:Array<Insn>): Array<SubRoutine> {
		var labelsSet = new Map<Label, Bool>();
		for (insn in sequence) {
			switch(insn) {
			case Insn.Gosub(label):
				labelsSet.set(label, true);
			case Insn.On(labels,isGosub=true):
				for (label in labels) labelsSet.set(label, true);
			case Insn.Call_builtin_handler_cmd(_,_,isGosub=true,label,_):
				labelsSet.set(label, true);
			default:
			}
		}
		return [for (label in labelsSet.keys()) SubRoutine.subRoutine(label)];
	}
}

enum SubRoutine {
	func(userDefFunc:UserDefFunc);
	subRoutine(label:Label);
}
