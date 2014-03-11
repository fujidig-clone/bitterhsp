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

enum Insn {
	Nop;
	Push_int(x: Int);
	Push_double(x: Float);
	Push_string(x: String);
	Push_default;
	Push_var(id: Int);
	Get_var(id: Int);
	Pop;
	Pop_n(n: Int);
	Dup;
	Add;
	Sub;
	Mul;
	Div;
	Mod;
	And;
	Or;
	Xor;
	Eq;
	Ne;
	Gt;
	Lt;
	Gteq;
	Lteq;
	Rsh;
	Lsh;
	Goto;
	Ifne;
	Ifeq;
	Assign;
	Assign_static_var(id:Int, indicesCount:Int);
	Assign_arg_array(id:Int, indicesCount:Int);
	Assign_member(id:Int, indicesCount:Int);
	Compound_assign(op:Int);
	Compound_assign_static_var(op:Int, id:Int; indicesCount:Int);
	Compound_assign_arg_array(op:Int, id:Int; indicesCount:Int);
	Compound_assign_member(op:Int, id:Int; indicesCount:Int);
	Inc;
	Inc_static_var(id:Int, indicesCount:Int);
	Inc_arg_array(id:Int, indicesCount:Int);
	Inc_member(id:Int, indicesCount:Int);
	Dec;
	Dec_static_var(id:Int, indicesCount:Int);
	Dec_arg_array(id:Int, indicesCount:Int);
	Dec_member(id:Int, indicesCount:Int);
	Call_builtin_cmd(type:Int, code:Int, argc:Int);
	Call_builtin_func(type:Int, code:Int, argc:Int);
	Call_builtin_handler_cmd(type:Int, code:Int, isGosub:Bool, label:Label, argc:Int);
	Call_userdef_cmd(userDefFunc:UserDefFunc, argc:Int);
	Call_userdef_func(userDefFunc:UserDefFunc, argc:Int);
	Getarg(id:Int);
	Push_arg_var(id:Int, indicesCount:Int);
	Get_arg_var(id:Int, indicesCount:Int);
	Push_member(id:Int, indicesCount:Int);
	Get_member(id:Int, indicesCount:Int);
	Thismod;
	Newmod(module:Module, argc:Int);
	Return(hasReturnValue:Bool);
	Delmod;
	Repeat(label:Label, argc:Int);
	Loop;
	Cnt;
	Continue(label:Label, argc:Int);
	Break(label:Label);
	Foreach(label:Label);
	Eachchk(label:Label);
	Gosub(label:Label);
	Goto_expr;
	Gosub_expr;
	Exgoto(label:Label);
	On(labels:Array<Label>, isGosub:Bool);
}

