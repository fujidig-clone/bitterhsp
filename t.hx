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

typedef Subst = Instruction;

class Flow {
	var sequence: Instruction;
	var kill: Map<Instruction,Set<Subst>>;
	var gen: Map<Instruction,Set<Subst>>;
	var in_: Map<Instruction,Set<Subst>>;
	var out: Map<Instruction,Set<Subst>>;
	var prevs: Map<Instruction,Set<Instruction>>;

	public function new(sequence) {
		this.sequence = sequence;
	}

	public function flow() {
		this.init();
		var updated;
		do {
			updated = false;
			for (insn in eachInsn()) {
				if (increase(insn)) updated = true;
			}
		} while (updated);
		for (insn in eachInsn()) {
			var substs = this.out[insn].toArray();
			trace('${insn}: ${substs}');
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

	function increase(insn:Instruction) {
		var updated = false;

		for (i in this.prevs[insn]) {
			if (merge(insn, this.in_[insn], this.out[i])) updated = true;
		}
		this.out[insn] = copy(this.gen[insn]);
		for (i in this.in_[insn]) {
			if (!this.kill[insn].has(i)) {
				this.out[insn].add(i);
			}
		}
		return updated;
	}

	static function copy(set: Set<Subst>) {
		var newSet = new Set<Subst>(new Map());
		for (i in set) {
			newSet.add(i);
		}
		return newSet;
	}

	static function merge(insn:Instruction, a: Set<Subst>, b: Set<Subst>) {
		var updated = false;
		for (i in b) {
			if (!a.has(i)) {
				updated = true;
				a.add(i);
			}
		}
		return updated;
	}

	static function log(x) {
		trace(Std.string(x));
	}

	function init() {
		this.makeKillGen();
		this.makePrevs();
		var insn = this.sequence;
		this.in_ = new Map();
		this.out = new Map();
		while (insn != null) {
			this.in_[insn] = new Set(new Map());
			this.out[insn] = copy(this.gen[insn]);
			insn = insn.next;
		}
	}

	function makePrevs() {
		this.prevs = new Map();
		var insn = this.sequence;
		while (insn != null) {
			this.prevs[insn] = new Set(new Map());
			insn = insn.next;
		}
		var insn = this.sequence;
		while (insn != null) {
			for (i in this.nextInsns(insn)) {
				this.prevs[i].add(insn);
			}
			insn = insn.next;
		}
	}

	function nextInsns(insn:Instruction): Array<Instruction> {
		switch (insn.opts) {
		case Insn.Goto(label):
			return [label.insn];
		case Insn.Ifne(label):
			return [label.insn, insn.next];
		case Insn.Ifeq(label):
			return [label.insn, insn.next];
		default:
			return [insn.next];
		}
	}
	
	function makeKillGen() {
		this.kill = new Map();
		this.gen = new Map();
		var insn = this.sequence;
		while (insn != null) {
			this.gen[insn] = new Set(new Map());
			this.kill[insn] = new Set(new Map());
			switch (insn.opts) {
			case Insn.Assign_static_var(id, _):
				this.gen[insn].add(insn);
				//this.kill[insn].add(insn);
			default:
			}
			insn = insn.next;
		}
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
