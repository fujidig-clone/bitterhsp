import js.Node;
import Compiler;
using Mixin;

class Set<K> {
	var map: Map<K,Bool>;
	public function new(map) {
		this.map = map;
	}

	public function add(k:K): Void {
		this.map.set(k, true);
	}
	public function addAll(keys:Iterable<K>) {
		for (k in keys) {
			add(k);
		}
	}
	public function has(k:K): Bool {
		return this.map.exists(k);
	}
	public function remove(k:K) {
		return this.map.remove(k);
	}
	public function iterator(): Iterator<K> {
		return this.map.keys();
	}
	public function toArray(): Array<K> {
		return [for (x in this.map.keys()) x];
	}
}


typedef Subst = Instruction;

class Loc {
	public var insn: Instruction;
	public var returnAddress: Instruction;
	public var subHead: Bool;
	public var next: Array<Loc>;
	public var prev: Array<Loc>;

	public function new(insn, returnAddress, subHead) {
		this.insn = insn;
		this.returnAddress = returnAddress;
		this.subHead = subHead;
		untyped {
			Object.defineProperty(this, "next", {enumerable: false, writable: true});
			Object.defineProperty(this, "prev", {enumerable: false, writable: true});
		}
	}

	public function step(insn) {
		return new Loc(insn, this.returnAddress, false);
	}
}

class Flow {
	var sequence: Instruction;
	var locs: Array<Loc>;

	public function new(sequence) {
		this.sequence = sequence;
	}

	public function flow() {
		makeLocSequence();	
		log(this.locs);
	}

	function makeLocSequence() {
		function key(loc:Loc) {
			if (loc.returnAddress == null) return '${loc.insn.id}';
			return loc.insn.id+","+loc.returnAddress.id;
		}

		var locs = new Map<String,Loc>();
		var q = [new Loc(this.sequence, null, false)];
		while (q.length > 0) {
			var loc = q.shift();
			if (locs.exists(key(loc))) continue;
			locs.set(key(loc), loc);
			var next = nextInsns(loc.insn).map(function (insn) return loc.step(insn));
			switch (loc.insn.opts) {
			case Insn.Gosub(label):
				next.push(new Loc(label.insn, loc.insn.next, true));
			case Insn.Return(_):
				next.push(new Loc(loc.returnAddress, true)); // Ç†ÅI
			default:
			}
			q.pushAll(next);
			loc.next = next;
		}
		this.locs = Lambda.array(locs);
	}

	function nextInsns(insn:Instruction): Array<Instruction> {
		switch (insn.opts) {
		case Insn.Goto(label):
			return [label.insn];
		case Insn.Ifne(label):
			return [label.insn, insn.next];
		case Insn.Ifeq(label):
			return [label.insn, insn.next];
		case Insn.Return(_):
			return [];
		case Insn.Gosub(label):
			return [];
		default:
			return [insn.next];
		}
	}

	static function copy(set: Set<Subst>) {
		var newSet = new Set<Subst>(new Map());
		for (i in set) {
			newSet.add(i);
		}
		return newSet;
	}

	static function merge(loc:Loc, a: Set<Subst>, b: Set<Subst>) {
		var updated = false;
		for (i in b) {
			if (!a.has(i)) {
				updated = true;
				a.add(i);
			}
		}
		return updated;
	}


	static function log(x:Dynamic) {
		trace(Std.string(x));
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

class T {
	static function main(){
		Node.global.BitterHSP = Node.require("./compiler");
		var path = Sys.args()[2];
		if (path == null) path = "hsp-programs/hello/hello.ax";
		var binary = Node.fs.readFileSync(path).toString("binary");
		var compiler = new Compiler(binary);
		var compiled = compiler.compile();
		var sequence = compiled.sequence;
		var userDefFuncs = compiled.userDefFuncs;
		new Flow(compiled.sequence).flow();
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
