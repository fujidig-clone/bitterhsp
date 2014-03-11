package ;

@:native('BitterHSP.Compiler')
extern class Compiler_ {
	static public function compile(data:String): Array<Dynamic>;
}

@:native('BitterHSP.Insn')
extern class Insn_ {
	public var code: Int;
	public var opts: Array<Dynamic>;
	public var fileName: String;
	public var lineNumber: Int;
}

class Compiler {
	static public function compile(data:String): Array<Insn> {
		return Compiler_.compile(data).map(function (i:Insn_) {
			return new Insn(i.code);
		});
	}
}

class Insn {
	public var code: Int;

	public function new(code:Int) {
		this.code = code;
	}
}


