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
		return Compiler_.compile(data).map(Compiler.convertInsn);
	}

	static private function convertInsn(insn:Insn_): Insn {
		var a:Dynamic = insn.opts[0];
		var b:Dynamic = insn.opts[1];
		var c:Dynamic = insn.opts[2];
		var d:Dynamic = insn.opts[3];
		var e:Dynamic = insn.opts[4];
		switch(insn.code) {
		case  0: return Insn.Nop;
		case  1: return Insn.Push_int(a);
		case  2: return Insn.Push_double(a);
		case  3: return Insn.Push_string(a);
		case  4: return Insn.Push_label(a);
		case  5: return Insn.Push_default;
		case  6: return Insn.Push_var(a);
		case  7: return Insn.Get_var(a);
		case  8: return Insn.Pop;
		case  9: return Insn.Pop_n(a);
		case 10: return Insn.Dup;
		case 11: return Insn.Add;
		case 12: return Insn.Sub;
		case 13: return Insn.Mul;
		case 14: return Insn.Div;
		case 15: return Insn.Mod;
		case 16: return Insn.And;
		case 17: return Insn.Or;
		case 18: return Insn.Xor;
		case 19: return Insn.Eq;
		case 20: return Insn.Ne;
		case 21: return Insn.Gt;
		case 22: return Insn.Lt;
		case 23: return Insn.Gteq;
		case 24: return Insn.Lteq;
		case 25: return Insn.Rsh;
		case 26: return Insn.Lsh;
		case 27: return Insn.Goto;
		case 28: return Insn.Ifne;
		case 29: return Insn.Ifeq;
		case 30: return Insn.Assign;
		case 31: return Insn.Assign_static_var(a, b);
		case 32: return Insn.Assign_arg_array(a, b);
		case 33: return Insn.Assign_member(a, b);
		case 34: return Insn.Compound_assign(a);
		case 35: return Insn.Compound_assign_static_var(a, b, c);
		case 36: return Insn.Compound_assign_arg_array(a, b, c);
		case 37: return Insn.Compound_assign_member(a, b, c);
		case 38: return Insn.Inc;
		case 39: return Insn.Inc_static_var(a, b);
		case 40: return Insn.Inc_arg_array(a, b);
		case 41: return Insn.Inc_member(a, b);
		case 42: return Insn.Dec;
		case 43: return Insn.Dec_static_var(a, b);
		case 44: return Insn.Dec_arg_array(a, b);
		case 45: return Insn.Dec_member(a, b);
		case 46: return Insn.Call_builtin_cmd(a, b, c);
		case 47: return Insn.Call_builtin_func(a, b, c);
		case 48: return Insn.Call_builtin_handler_cmd(a, b, c, d, e);
		case 49: return Insn.Call_userdef_cmd(a, b);
		case 50: return Insn.Call_userdef_func(a, b);
		case 51: return Insn.Getarg(a);
		case 52: return Insn.Push_arg_var(a, b);
		case 53: return Insn.Get_arg_var(a, b);
		case 54: return Insn.Push_member(a, b);
		case 55: return Insn.Get_member(a, b);
		case 56: return Insn.Thismod;
		case 57: return Insn.Newmod(a, b);
		case 58: return Insn.Return(a);
		case 59: return Insn.Delmod;
		case 60: return Insn.Repeat(a, b);
		case 61: return Insn.Loop;
		case 62: return Insn.Cnt;
		case 63: return Insn.Continue(a, b);
		case 64: return Insn.Break(a);
		case 65: return Insn.Foreach(a);
		case 66: return Insn.Eachchk(a);
		case 67: return Insn.Gosub(a);
		case 68: return Insn.Goto_expr;
		case 69: return Insn.Gosub_expr;
		case 70: return Insn.Exgoto(a);
		case 71: return Insn.On(a, b);
		default:
			throw "invalid code";
		}
	}
}

enum Insn {
	Nop;
	Push_int(x:Int);
	Push_double(x:Float);
	Push_string(x:String);
	Push_label(x:Label);
	Push_default;
	Push_var(id:Int);
	Get_var(id:Int);
	Pop;
	Pop_n(n:Int);
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
	Compound_assign_static_var(op:Int, id:Int, indicesCount:Int);
	Compound_assign_arg_array(op:Int, id:Int, indicesCount:Int);
	Compound_assign_member(op:Int, id:Int, indicesCount:Int);
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

typedef Label = {
	var pos:Int;
}

typedef UserDefFunc = {
	var isCType: Bool;
	var name: String;
	var label: Label;
	var paramTypes: Array<Int>;
	var id: Int;
}

typedef Module = {
	var name: String;
	var constructor: UserDefFunc;
	var destructor: UserDefFunc;
	var membersCount: Int;
	var id: Int;
}
