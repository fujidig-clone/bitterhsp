import AXData;
using Mixin;

typedef CompileResult = {
	var sequence: Instruction;
	var userDefFuncs: Array<UserDefFunc>;
	var modules: Array<Module>;
}

class Compiler {
	var ax: AXData;
	var tokensPos = 0;
	var labels: Array<Label>;
	var ifLabels: Map<Int, Array<Label>> = new Map();
	var userDefFuncs: Array<UserDefFunc> = [];
	var modules: Array<Module> = [];
	var sequence: Array<Instruction> = [];

	public static function main() {
		var path, binary: String;
		untyped {
			path = process.argv[2];
			if (path == null) path = "t.ax";
			binary = require("fs").readFileSync(path).toString("binary");
		}
		var compiler = new Compiler(binary);
		var compiled = compiler.compile();
		var insn = compiled.sequence;
		while (insn != null) {
			trace(Std.string(insn.opts));
			insn = insn.next;
		}
	}

	public function new(data: String) {
		var ax = this.ax = new AXData(data);
	}

	public function compile(): CompileResult {
		this.labels = []; // HSP のラベルIDに対応したラベル
		for (i in 0...ax.labels.length) {
			this.labels[i] = new Label(null, ax.labelNames[i]);
		}
		for (i in 0...this.ax.funcsInfo.length) this.buildUserDefFunc(i);
		for (i in 0...this.ax.funcsInfo.length) this.buildModule(i);
		while (this.tokensPos < this.ax.tokens.length) {
			this.compileStatement();
		}
		for (i in 0...sequence.length) {
			this.sequence[i].next = this.sequence[i+1];
		}
		for (label in this.allLabels()) {
			label.insn = this.sequence[label.pos];
		}
		return {
			sequence: this.sequence[0],
			userDefFuncs: this.userDefFuncs,
			modules: this.modules,
		};
	}
	function allLabels(): Array<Label> {
		var ret: Array<Label> = [];
		for (labels in this.ifLabels) {
			ret = ret.concat(labels);
		}
		return ret.concat(this.labels);
	}
	function pushNewInsn(opts: Insn, ?token: Token) {
		if (token == null) token = this.ax.tokens[this.tokensPos];
		this.sequence.push(new Instruction(opts, token.fileName, token.lineNumber, null, this.tokensPos));
	}
	function getFinfoIdByMinfoId(minfoId: Int): Int {
		var funcsInfo = this.ax.funcsInfo;
		for (i in 0...funcsInfo.length) {
			var funcInfo = funcsInfo[i];
			if (funcInfo.prmindex <= minfoId && minfoId < funcInfo.prmindex + funcInfo.prmmax) {
				return i;
			}
		}
		return null;
	}
	function error(message = "", ?token: Token): CompileError {
		if (token == null) token = this.ax.tokens[this.tokensPos];
		return new CompileError(message, token.fileName, token.lineNumber);
	}
	function compileStatement() {
		var token = this.ax.tokens[this.tokensPos];
		if (!token.ex1) {
			throw this.error();
		}
		var labelIDs = this.ax.labelsMap[token.pos];
		if (labelIDs != null) {
			for (i in 0...labelIDs.length) {
				var labelID = labelIDs[i];
				this.labels[labelID].pos = sequence.length;
			}
		}
		var labels = this.ifLabels[token.pos];
		if (labels != null) {
			for (i in 0...labels.length) {
				labels[i].pos = sequence.length;
			}
		}
		switch(token.type) {
		case TokenType.VAR, TokenType.STRUCT:
			this.compileAssignment();
		case TokenType.CMPCMD:
			this.compileBranchCommand();
		case TokenType.PROGCMD:
			this.compileProgramCommand();
		case TokenType.MODCMD:
			this.compileUserDefCommand();
		case TokenType.INTCMD:
			this.compileBasicCommand();
		case TokenType.EXTCMD:
			this.compileGuiCommand();
		default:
			this.compileCommand();
		}
	}
	function compileAssignment() {
		this.compileVariable();

		var token = this.ax.tokens[this.tokensPos++];
		if (!(token != null && token.type == TokenType.MARK)) {
			throw this.error();
		}
		if (this.ax.tokens[this.tokensPos].ex1) {
			if (token.val == 0) { // インクリメント
				this.pushNewInsn(Insn.Inc, token);
				return;
			}
			if (token.val == 1) { // デクリメント
				this.pushNewInsn(Insn.Dec, token);
				return;
			}
		}
		if (token.val != 8) { // CALCCODE_EQ
			// 複合代入
			var argc = this.compileParameters(true);
			if (argc != 1) {
				throw this.error("複合代入のパラメータの数が間違っています。", token);
			}
			this.pushNewInsn(Insn.Compound_assign(token.val), token);
			return;
		}
		var argc = this.compileParameters(true);
		if (argc == 0) {
			throw this.error("代入のパラメータの数が間違っています。", token);
		}
		this.pushNewInsn(Insn.Assign(argc), token);
	}
	function compileProgramCommand() {
		var token = this.ax.tokens[this.tokensPos];
		switch(token.code) {
		case 0x00: // goto
			var labelToken = this.ax.tokens[this.tokensPos + 1];
			if (labelToken != null && labelToken.type == TokenType.LABEL && !labelToken.ex2 && (this.ax.tokens[this.tokensPos + 2] == null || this.ax.tokens[this.tokensPos + 2].ex1)) {
				this.pushNewInsn(Insn.Goto(this.labels[labelToken.code]));
				this.tokensPos += 2;
			} else {
				this.tokensPos ++;
				var argc = this.compileParameters();
				if (argc != 1) throw this.error('goto の引数の数が違います', token);
				this.pushNewInsn(Insn.Goto_expr, token);
			}
		case 0x01: // gosub
			var labelToken = this.ax.tokens[this.tokensPos + 1];
			if (labelToken != null && labelToken.type == TokenType.LABEL && !labelToken.ex2 && (this.ax.tokens[this.tokensPos + 2] == null || this.ax.tokens[this.tokensPos + 2].ex1)) {
				this.pushNewInsn(Insn.Gosub(this.labels[labelToken.code]));
				this.tokensPos += 2;
			} else {
				this.tokensPos ++;
				var argc = this.compileParameters();
				if (argc != 1) throw this.error('gosub の引数の数が違います', token);
				this.pushNewInsn(Insn.Gosub_expr, token);
			}
		case 0x02: // return
			this.tokensPos ++;
			if (this.ax.tokens[this.tokensPos].ex2) throw this.error('パラメータは省略できません', token);
			var argc = this.compileParameters();
			if (argc > 1) throw this.error('return の引数が多すぎます', token);
			this.pushNewInsn(Insn.Return(argc == 1), token);
		case 0x03: // break
			this.tokensPos ++;
			var labelToken = this.ax.tokens[this.tokensPos++];
			if (labelToken.type != TokenType.LABEL) {
				throw this.error();
			}
			var argc = this.compileParameters();
			if (argc > 0) throw this.error('break の引数が多すぎます', token);
			this.pushNewInsn(Insn.Break(this.labels[labelToken.code]), token);
		case 0x04: // repeat
			this.tokensPos ++;
			var labelToken = this.ax.tokens[this.tokensPos++];
			if (labelToken.type != TokenType.LABEL) {
				throw this.error();
			}
			var argc;
			if (this.ax.tokens[this.tokensPos].ex2) {
				this.pushNewInsn(Insn.Push_int(-1), token);
				argc = 1 + this.compileParametersSub();
			} else {
				argc = this.compileParameters();
			}
			if (argc > 2) throw this.error('repeat の引数が多すぎます', token);
			this.pushNewInsn(Insn.Repeat(this.labels[labelToken.code], argc), token);
		case 0x05: // loop
			this.tokensPos ++;
			var argc = this.compileParameters();
			if (argc > 0) throw this.error('loop の引数が多すぎます', token);
			this.pushNewInsn(Insn.Loop, token);
		case 0x06: // continue
			this.tokensPos ++;
			var labelToken = this.ax.tokens[this.tokensPos++];
			if (labelToken.type != TokenType.LABEL) {
				throw this.error();
			}
			var argc = this.compileParameters();
			if (argc > 1) throw this.error('continue の引数が多すぎます', token);
			this.pushNewInsn(Insn.Continue(this.labels[labelToken.code], argc), token);
		case 0x0b: // foreach
			this.tokensPos ++;
			var labelToken = this.ax.tokens[this.tokensPos++];
			if (labelToken.type != TokenType.LABEL) {
				throw this.error();
			}
			var argc = this.compileParameters();
			if (argc > 0) throw this.error();
			this.pushNewInsn(Insn.Foreach(this.labels[labelToken.code]), token);
		case 0x0c: // eachchk
			this.tokensPos ++;
			var labelToken = this.ax.tokens[this.tokensPos++];
			if (labelToken.type != TokenType.LABEL) {
				throw this.error();
			}
			var argc = this.compileParameters();
			if (argc != 1) throw this.error('foreach の引数の数が違います', token);
			this.pushNewInsn(Insn.Eachchk(this.labels[labelToken.code]), token);
		case 0x12: // newmod
			this.tokensPos ++;
			if (this.ax.tokens[this.tokensPos].ex2) {
				throw this.error('パラメータは省略できません');
			}
			this.compileVariable(); 
			var structToken = this.ax.tokens[this.tokensPos++];
			var prmInfo = this.ax.prmsInfo[structToken.code];
			if (structToken.type != TokenType.STRUCT || prmInfo.mptype != MPType.STRUCTTAG) {
				throw this.error('モジュールが指定されていません', structToken);
			}
			var module = this.getModule(prmInfo.subid);
			var argc = this.compileParametersSub();
			this.pushNewInsn(Insn.Newmod(module, argc), token);
		case 0x14: // delmod
			this.tokensPos ++;
			var argc = this.compileParameters();
			if (argc != 1) throw this.error('delmod の引数の数が違います', token);
			this.pushNewInsn(Insn.Delmod, token);
		case 0x18: // exgoto
			this.tokensPos ++;
			var argc = this.compileParameters();
			if (argc != 4) throw this.error('exgoto の引数の数が違います', token);
			var label = this.popLabelInsn();
			this.pushNewInsn(Insn.Exgoto(label), token);
		case 0x19: // on
			this.tokensPos ++;
			var paramToken = this.ax.tokens[this.tokensPos];
			if (paramToken.ex1 || paramToken.ex2) {
				throw this.error('パラメータは省略できません', token);
			}
			this.compileParameter();
			var jumpType = this.readJumpType();
			if (jumpType == null) {
				throw this.error('goto / gosubが指定されていません');
			}
			var argc = this.compileParametersSub();
			var labels: Array<Label> = [];
			for (i in 0...argc) {
				labels.unshift(this.popLabelInsn());
			}
			this.pushNewInsn(Insn.On(labels, jumpType), token);
		default:
			this.compileCommand();
		}
	}
	function compileBasicCommand() {
		var token = this.ax.tokens[this.tokensPos];
		var posBak = this.tokensPos;
		switch(token.code) {
		case 0x00, // onexit
		     0x01, // onerror
		     0x02, // onkey
		     0x03, // onclick
		     0x04: // oncmd
			this.tokensPos ++;
			var jumpType = this.readJumpType();
			var label = this.readLabelLiteral();
			if (jumpType != null && label == null) {
				throw this.error("ラベル名が指定されていません");
			}
			if (label == null) {
				this.tokensPos = posBak;
				this.compileCommand();
				return;
			}
			if (jumpType == null) jumpType = JumpType.Goto;
			var argc = this.compileParametersSub();
			this.pushNewInsn(Insn.Call_builtin_handler_cmd(token.type, token.code, jumpType, label, argc), token);
		default:
			this.compileCommand();
		}
	}
	function compileGuiCommand() {
		var token = this.ax.tokens[this.tokensPos];
		switch(token.code) {
		case 0x00: // button
			this.tokensPos ++;
			var jumpType = this.readJumpType();
			if (jumpType == null) jumpType = JumpType.Goto;
			var argc = this.compileParameters();
			var label = this.popLabelInsn();
			this.pushNewInsn(Insn.Call_builtin_handler_cmd(token.type, token.code, jumpType, label, argc - 1), token);
		default:
			this.compileCommand();
		}
	}
	function compileCommand() {
		var token = this.ax.tokens[this.tokensPos++];
		var argc = this.compileParameters();
		this.pushNewInsn(Insn.Call_builtin_cmd(token.type, token.code, argc), token);
	}
	function compileBranchCommand() {
		var token = this.ax.tokens[this.tokensPos++];
		var skipTo = token.pos + token.size + token.skipOffset;
		var label = new Label();
		this.ifLabels.pushAt(skipTo, label);
		var argc = this.compileParameters(true);
		if (token.code == 0) { // 'if'
			if (argc != 1) throw this.error("if の引数の数が間違っています。", token);
			this.pushNewInsn(Insn.Ifeq(label), token);
		} else {
			if (argc != 0) throw this.error("else の引数の数が間違っています。", token);
			this.pushNewInsn(Insn.Goto(label), token);
		}
	}
	function popLabelInsn(): Label {
			var insn = this.sequence.pop();
			switch (insn.opts) {
			case Insn.Push_label(label):
				return label;
			default:
				throw this.error('ラベル名が指定されていません');
			}
	}
	function readLabelLiteral(): Label {
		var token = this.ax.tokens[this.tokensPos++];
		var nextToken = this.ax.tokens[this.tokensPos];
		if (token.type == TokenType.LABEL && (nextToken == null || nextToken.ex1 || nextToken.ex2)) {
			return this.labels[token.code];
		} else {
			return null;
		}
	}
	function compileParameters(cannotBeOmitted = false): Int {
		var argc = 0;
		if (this.ax.tokens[this.tokensPos].ex2) {
			if (cannotBeOmitted) {
				throw this.error('パラメータの省略はできません');
			}
			this.pushNewInsn(Insn.Push_default);
			argc ++;
		}
		argc += this.compileParametersSub(cannotBeOmitted);
		return argc;
	}
	function compileParametersSub(cannotBeOmitted = false): Int {
		var argc = 0;
		while (true) {
			var token = this.ax.tokens[this.tokensPos];
			if (token == null || token.ex1) return argc;
			if (token.type == TokenType.MARK) {
				if (token.code == 63) { // '?'
					if (cannotBeOmitted) {
						throw this.error('パラメータの省略はできません');
					}
					this.pushNewInsn(Insn.Push_default);
					this.tokensPos ++;
					argc ++;
					continue;
				}
				if (token.code == 41) { // ')'
					return argc;
				}
			}
			argc ++;
			this.compileParameter();
		}
	}
	function compileParameter() {
		var headPos = this.tokensPos;
		while (true) {
			var token = this.ax.tokens[this.tokensPos];
			if (token == null || token.ex1) return;
			switch(token.type) {
			case TokenType.MARK:
				if (token.code == 41) { // ')'
					return;
				}
				this.compileOperator();
			case TokenType.VAR:
				this.compileStaticVariable();
			case TokenType.STRING:
				this.pushNewInsn(Insn.Push_string(token.stringValue));
				this.tokensPos ++;
			case TokenType.DNUM:
				this.pushNewInsn(Insn.Push_double(token.doubleValue));
				this.tokensPos ++;
			case TokenType.INUM:
				this.pushNewInsn(Insn.Push_int(token.val));
				this.tokensPos ++;
			case TokenType.STRUCT:
				this.compileStruct();
			case TokenType.LABEL:
				this.pushNewInsn(Insn.Push_label(this.labels[token.code]));
				this.tokensPos ++;
			case TokenType.EXTSYSVAR:
				this.compileExtSysvar();
			case TokenType.SYSVAR:
				this.compileSysvar();
			case TokenType.MODCMD:
				this.compileUserDefFuncall();
			case TokenType.INTFUNC:
				this.compileIntFuncall();
			case TokenType.DLLCTRL:
				this.compileDllctrlCall();
			default:
				this.compileFuncall();
			}
			token = this.ax.tokens[this.tokensPos];
			if (token != null && token.ex2) return;
		}
	}
	function compileOperator() {
		var OP_INSN = [Insn.Add, Insn.Sub, Insn.Mul, Insn.Div, Insn.Mod,
		               Insn.And, Insn.Or, Insn.Xor, Insn.Eq, Insn.Ne,
					   Insn.Gt, Insn.Lt, Insn.Gteq, Insn.Lteq, Insn.Rsh, Insn.Lsh];
		var token = this.ax.tokens[this.tokensPos++];
		if (!(0 <= token.code && token.code < 16)) {
			throw this.error("演算子コード " + token.code + " は解釈できません。", token);
		}
		var len = sequence.length;
		this.pushNewInsn(OP_INSN[token.code], token);
	}
	function compileExtSysvar() {
		var token = this.ax.tokens[this.tokensPos];
		if (token.code >= 0x100) {
			this.compileFuncall();
		} else {
			this.compileSysvar();
		}
	}
	function compileStruct() {
		var token = this.ax.tokens[this.tokensPos];
		var prmInfo = this.ax.prmsInfo[token.code];
		if (this.getProxyVarType() != null) {
			this.compileProxyVariable();
		} else if (token.type == -1) {
			this.tokensPos ++;
			this.pushNewInsn(Insn.Thismod, token);
		} else {
			this.tokensPos ++;
			var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(token.code)];
			this.pushNewInsn(Insn.Getarg(token.code - funcInfo.prmindex), token);
		}
	}
	function compileSysvar() {
		var token = this.ax.tokens[this.tokensPos++];
		if (token.type == TokenType.SYSVAR && token.code == 0x04) {
			this.pushNewInsn(Insn.Cnt, token);
			return;
		}
		this.pushNewInsn(Insn.Call_builtin_func(token.type, token.code, 0), token);
	}
	function readJumpType(): JumpType {
		var token = this.ax.tokens[this.tokensPos];
		if (!token.ex1 && token.type == TokenType.PROGCMD && token.val <= 1) {
			this.tokensPos ++;
			return token.val == 1 ? JumpType.Gosub : JumpType.Goto;
		}
		return null;
	}
	function compileUserDefFuncall() {
		var token = this.ax.tokens[this.tokensPos++];
		var userDefFunc = this.getUserDefFunc(token.code);
		var argc = this.compileParenAndParameters();
		this.pushNewInsn(Insn.Call_userdef_func(userDefFunc, argc), token);
	}
	function compileUserDefCommand() {
		var token = this.ax.tokens[this.tokensPos++];
		var userDefFunc = this.getUserDefFunc(token.code);
		var argc = this.compileParameters();
		this.pushNewInsn(Insn.Call_userdef_cmd(userDefFunc, argc), token);
	}
	function getUserDefFunc(finfoId: Int): UserDefFunc {
		var func = this.userDefFuncs[finfoId];
		if (func == null) {
			throw this.error();
		}
		return func;
	}
	function buildUserDefFunc(finfoId: Int) {
		var funcInfo = this.ax.funcsInfo[finfoId];
		if (funcInfo.index != -1 && funcInfo.index != -2) { // STRUCTDAT_INDEX_FUNC, STRUCTDAT_INDEX_CFUNC
			return;
		}
		var isCType = funcInfo.index == -2;
		var paramTypes: Array<Int> = [];
		for (i in 0...funcInfo.prmmax) {
			paramTypes[i] = this.ax.prmsInfo[funcInfo.prmindex + i].mptype;
		}
		this.userDefFuncs[finfoId] = new UserDefFunc(isCType, funcInfo.name, this.labels[funcInfo.otindex], paramTypes, finfoId);
	}
	function getModule(finfoId: Int): Module {
		var module = this.modules[finfoId];
		if (module == null) {
			throw this.error();
		}
		return module;
	}
	function buildModule(finfoId: Int) {
		var funcInfo = this.ax.funcsInfo[finfoId];
		if (funcInfo.index != -3) { // STRUCTDAT_INDEX_STRUCT
			return;
		}
		var destructor = funcInfo.otindex != 0 ? this.getUserDefFunc(funcInfo.otindex) : null;
		var constructorFinfoId = this.ax.prmsInfo[funcInfo.prmindex].offset;
		var constructor = constructorFinfoId != -1 ? this.getUserDefFunc(constructorFinfoId) : null;
		this.modules[finfoId] = new Module(funcInfo.name, constructor, destructor, funcInfo.prmmax - 1, finfoId);
	}
	function compileIntFuncall() {
		var token = this.ax.tokens[this.tokensPos];
		if (token.code == 0x0c) { // varptr
			var token_1 = this.ax.tokens[this.tokensPos+1];
			var token_2 = this.ax.tokens[this.tokensPos+2];
			var token_3 = this.ax.tokens[this.tokensPos+3];
			if (this.isLeftParenToken(token_1) && token_2.type == TokenType.DLLFUNC && this.isRightParenToken(token_3)) {
				this.pushNewInsn(Insn.Push_int(token_2.val));
				this.pushNewInsn(Insn.Call_builtin_func(token.type, token.code, 1), token);
				this.tokensPos += 4;
				return;

			}
		}
		this.compileFuncall();
	}
	function compileDllctrlCall() {
		var token = this.ax.tokens[this.tokensPos];
		if (token.code >= 0x1000) {
			this.compileSysvar();
		} else {
			this.compileFuncall();
		}
	}
	function compileFuncall() {
		var token = this.ax.tokens[this.tokensPos++];
		var argc = this.compileParenAndParameters();
		this.pushNewInsn(Insn.Call_builtin_func(token.type, token.code, argc), token);
	}
	function compileParenAndParameters(): Int {
		this.compileLeftParen();
		var argc = this.compileParameters();
		this.compileRightParen();
		return argc;
	}
	function compileLeftParen() {
		var parenToken = this.ax.tokens[this.tokensPos++];
		if (!(parenToken != null && parenToken.type == TokenType.MARK && parenToken.code == 40)) {
			throw this.error('関数名の後ろに開き括弧がありません。', parenToken);
		}
	}
	function compileRightParen() {
		var parenToken = this.ax.tokens[this.tokensPos++];
		if (!(parenToken != null && parenToken.type == TokenType.MARK && parenToken.code == 41)) {
			throw this.error('関数パラメータの後ろに閉じ括弧がありません。', parenToken);
		}
	}
	function compileVariable() {
		switch(this.ax.tokens[this.tokensPos].type) {
		case TokenType.VAR:
			this.compileStaticVariable();
			return;
		case TokenType.STRUCT:
			if (this.getProxyVarType() != null) {
				this.compileProxyVariable();
				return;
			}
		default:
		}
		throw this.error('変数が指定されていません');
	}
	function compileStaticVariable() {
		var token = this.ax.tokens[this.tokensPos++];
		var argc = this.compileVariableSubscript();
		this.pushNewInsn(Insn.Push_var(token.code, argc), token);
	}
	function compileProxyVariable() {
		var proxyVarType = this.getProxyVarType();
		var token = this.ax.tokens[this.tokensPos++];
		var prmInfo = this.ax.prmsInfo[token.code];
		var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(token.code)];
		switch(proxyVarType) {
		case ProxyVarType.MEMBER:
			var argc = this.compileVariableSubscript();
			var id = token.code - funcInfo.prmindex - 1;
			this.pushNewInsn(Insn.Push_member(id, argc), token);
		case ProxyVarType.ARG_VAR:
			this.pushNewInsn(Insn.Getarg(token.code - funcInfo.prmindex), token);
		case ProxyVarType.ARG_ARRAY, ProxyVarType.ARG_LOCAL:
			var id = token.code - funcInfo.prmindex;
			var argc = this.compileVariableSubscript();
			this.pushNewInsn(Insn.Push_arg_var(id, argc), token);
		default:
			throw ""; // proxyVarType == nullとなるときに呼び出してはいけない
		}
	}
	// thismodや変数でないパラメータの場合nullを返す
	// token.type == TokenType.STRUCTのときに呼ばれなければならない
	function getProxyVarType(): ProxyVarType {
		var token = this.ax.tokens[this.tokensPos];
		if (token.code == -1) { // thismod
			return null;
		}
		var prmInfo = this.ax.prmsInfo[token.code];
		if (prmInfo.subid >= 0) {
			return ProxyVarType.MEMBER;
		}
		switch(prmInfo.mptype) {
		case MPType.LOCALVAR:
			return ProxyVarType.ARG_LOCAL;
		case MPType.ARRAYVAR:
			return ProxyVarType.ARG_ARRAY;
		case MPType.SINGLEVAR:
			if (this.isLeftParenToken(this.ax.tokens[this.tokensPos + 1])) {
				throw this.error('パラメータタイプ var の変数に添字を指定しています');
			}
			return ProxyVarType.ARG_VAR;
			default: // var,array,local以外のパラメータ
			return null;
		}
	}
	function isLeftParenToken(token: Token) {
		return token != null && token.type == TokenType.MARK && token.code == 40;
	}
	function isRightParenToken(token: Token) {
		return token != null && token.type == TokenType.MARK && token.code == 41;
	}
	function compileVariableSubscript(): Int {
		var argc = 0;
		var parenToken = this.ax.tokens[this.tokensPos];
		if (parenToken != null && parenToken.type == TokenType.MARK && parenToken.code == 40) {
			this.tokensPos ++;
			argc = this.compileParameters(true);
			if (argc == 0) {
				throw this.error('配列変数の添字が空です', parenToken);
			}
			parenToken = this.ax.tokens[this.tokensPos++];
			if (!(parenToken != null && parenToken.type == TokenType.MARK && parenToken.code == 41)) {
				throw this.error('配列変数の添字の後ろに閉じ括弧がありません。', parenToken);
			}
		}
		return argc;
	}
}

class Instruction {
	public var opts: Insn;
	public var fileName: String;
	public var lineNumber: Int;
	public var next: Instruction;
	public var origPos: Int;

	public function new(opts: Insn, fileName: String, lineNumber: Int, next: Instruction, origPos: Int) {
		this.opts = opts;
		this.fileName = fileName;
		this.lineNumber = lineNumber;
		this.next = next;
		this.origPos = origPos;
#if debug
		// Std.stringの出力にnextプロパティが出てこないようにする
		untyped { Object.defineProperty(this, "next", {enumerable: false, writable: true}); }
#end
	}

	public function toString() {
		return '<${this.lineNumber} ${Type.enumConstructor(this.opts)}>';
	}
}

enum Insn {
	Nop;
	Push_int(x:Int);
	Push_double(x:Float);
	Push_string(x:String);
	Push_label(x:Label);
	Push_default;
	Push_var(id:Int, argc:Int);
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
	Goto(label:Label);
	Ifne(label:Label);
	Ifeq(label:Label);
	Assign(argc:Int);
	Compound_assign(op:Int);
	Inc;
	Dec;
	Call_builtin_cmd(type:Int, code:Int, argc:Int);
	Call_builtin_func(type:Int, code:Int, argc:Int);
	Call_builtin_handler_cmd(type:Int, code:Int, jumpType:JumpType, label: Label, argc:Int);
	Call_userdef_cmd(userDefFunc:UserDefFunc, argc:Int);
	Call_userdef_func(userDefFunc:UserDefFunc, argc:Int);
	Getarg(id:Int);
	Push_arg_var(id:Int, indicesCount:Int);
	Push_member(id:Int, indicesCount:Int);
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
	On(labels:Array<Label>, jumpType:JumpType);
}

enum JumpType {
	Goto;
	Gosub;
}

class Label {
	public var pos:Int;
	public var insn:Instruction;
	public var name:String;

	public function new(insn = null, name = null) {
		this.pos = -1;
		this.insn = insn;
		this.name = name;
	}

	public function toString() {
		return "<Label>";
	}
}

class UserDefFunc {
	public var isCType: Bool;
	public var name: String;
	public var label: Label;
	public var paramTypes: Array<Int>;
	public var id: Int;

	public function new(isCType, name, label, paramTypes, id) {
		this.isCType = isCType;
		this.name = name;
		this.label = label;
		this.paramTypes = paramTypes;
		this.id = id;
	}
}

class Module {
	public var name: String;
	public var constructor: UserDefFunc;
	public var destructor: UserDefFunc;
	public var membersCount: Int;
	public var id: Int;

	public function new(name, constructor, destructor, membersCount, id) {
		this.name = name;
		this.constructor = constructor;
		this.destructor = destructor;
		this.membersCount = membersCount;
		this.id = id;
	}
}

enum ProxyVarType {
	MEMBER;
	ARG_VAR;
	ARG_ARRAY;
	ARG_LOCAL;
}

class CompileError {
	public var message: String;
	public var hspFileName: String;
	public var hspLineNumber: Int;

	public function new(message, hspFileName, hspLineNumber) {
		this.message = message;
		this.hspFileName = hspFileName;
		this.hspLineNumber = hspLineNumber;
	}
}

