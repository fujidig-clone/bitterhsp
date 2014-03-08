///<reference path="axdata.ts"/>
//
module BitterHSP {
    export class Compiler {
        private tokensPos = 0;
        private labels: Array<Label>;
        private ifLabels: NumDictionary<Array<Label>> = Object.create(null);
        private userDefFuncs: Array<UserDefFunc> = [];
        private modules: Array<Module> = [];
        
        constructor(private ax: AXData) {
            this.labels = []; // HSP のラベルIDに対応したラベル
            for(var i = 0; i < ax.labels.length; i ++) {
                this.labels[i] = new Label;
            }
        }

        private compile(): Array<Insn> {
            var sequence: Array<Insn> = [];
            while(this.tokensPos < this.ax.tokens.length) {
                var token = this.ax.tokens[this.tokensPos];
                if(!token.ex1) {
                    throw this.error();
                }
                var labelIDs = this.ax.labelsMap[token.pos];
                if(labelIDs) {
                    for(var i = 0; i < labelIDs.length; i ++) {
                        var labelID = labelIDs[i];
                        this.labels[labelID].pos = sequence.length;
                    }
                }
                var labels = this.ifLabels[token.pos];
                if(labels) {
                    for(var i = 0; i < labels.length; i ++) {
                        labels[i].pos = sequence.length;
                    }
                }
                switch(token.type) {
                case TokenType.VAR:
                case TokenType.STRUCT:
                    this.compileAssignment(sequence);
                    break;
                case TokenType.CMPCMD:
                    this.compileBranchCommand(sequence);
                    break;
                case TokenType.PROGCMD:
                    this.compileProgramCommand(sequence);
                    break;
                case TokenType.MODCMD:
                    this.compileUserDefCommand(sequence);
                    break;
                case TokenType.INTCMD:
                    this.compileBasicCommand(sequence);
                    break;
                case TokenType.EXTCMD:
                    this.compileGuiCommand(sequence);
                    break;
                case TokenType.DLLFUNC:
                case TokenType.DLLCTRL:
                    this.compileCommand(sequence);
                    break;
                default:
                    throw this.error("命令コード " + token.type + " は解釈できません。");
                }
            }
            return sequence;
        }
        private pushNewInsn(sequence: Array<Insn>, code: InsnCode, opts: Array<any>, token?: Token) {
            token || (token = this.ax.tokens[this.tokensPos]);
            sequence.push(new Insn(code, opts, token.fileName, token.lineNumber));
        }
        private getFinfoIdByMinfoId(minfoId: number): number {
            var funcsInfo = this.ax.funcsInfo;
            for(var i = 0; i < funcsInfo.length; i ++) {
                var funcInfo = funcsInfo[i];
                if(funcInfo.prmindex <= minfoId && minfoId < funcInfo.prmindex + funcInfo.prmmax) {
                    return i;
                }
            }
            return null;
        }
        private error(message = "", token?: Token): CompileError {
            token || (token = this.ax.tokens[this.tokensPos]);
            return new CompileError(message, token.fileName, token.lineNumber);
        }
        private compileAssignment(sequence: Array<Insn>) {
            var varToken = this.ax.tokens[this.tokensPos];
            var insnCode: number;
            var opts: Array<any>;
            switch(varToken.type) {
            case TokenType.VAR:
                this.tokensPos ++;
                insnCode = 1;
                var indicesCount = this.compileVariableSubscript(sequence);
                opts = [varToken.code, indicesCount];
                break;
            case TokenType.STRUCT:
                var proxyVarType = this.getProxyVarType();
                if(!proxyVarType) {
                    throw this.error('変数が指定されていません');
                }
                var prmInfo = this.ax.prmsInfo[varToken.code];
                var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(varToken.code)];
                switch(proxyVarType) {
                case ProxyVarType.THISMOD:
                    insnCode = 0;
                    opts = [];
                    this.compileProxyVariable(sequence);
                    break;
                case ProxyVarType.MEMBER:
                    insnCode = 3;
                    this.tokensPos ++;
                    var indicesCount = this.compileVariableSubscript(sequence);
                    opts = [varToken.code - funcInfo.prmindex - 1, indicesCount];
                    break;
                case ProxyVarType.ARG_VAR:
                    insnCode = 0;
                    opts = [];
                    this.compileProxyVariable(sequence);
                    break;
                case ProxyVarType.ARG_ARRAY:
                case ProxyVarType.ARG_LOCAL:
                    insnCode = 2;
                    this.tokensPos ++;
                    var indicesCount = this.compileVariableSubscript(sequence);
                    opts = [varToken.code - funcInfo.prmindex, indicesCount];
                    break;
                default:
                    throw new Error('must not happen');
                }
                break;
            default:
                throw this.error('変数が指定されていません');
            }

            var token = this.ax.tokens[this.tokensPos++];
            if(!(token && token.type == TokenType.MARK)) {
                throw this.error();
            }
            if(this.ax.tokens[this.tokensPos].ex1) {
                if(token.val == 0) { // インクリメント
                    this.pushNewInsn(sequence, InsnCode.INC + insnCode, opts, token);
                    return;
                }
                if(token.val == 1) { // デクリメント
                    this.pushNewInsn(sequence, InsnCode.DEC + insnCode, opts, token);
                    return;
                }
            }
            if(token.val != 8) { // CALCCODE_EQ
                // 複合代入
                var argc = this.compileParameters(sequence, true, true);
                if(argc != 1) {
                    throw this.error("複合代入のパラメータの数が間違っています。", token);
                }
                this.pushNewInsn(sequence, InsnCode.COMPOUND_ASSIGN + insnCode, [token.val].concat(opts), token);
                return;
            }
            var argc = this.compileParameters(sequence, true, true);
            if(argc == 0) {
                throw this.error("代入のパラメータの数が間違っています。", token);
            }
            this.pushNewInsn(sequence, InsnCode.ASSIGN + insnCode, opts.concat([argc]), token);
        }
        private compileProgramCommand(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos];
            switch(token.code) {
            case 0x00: // goto
                var labelToken = this.ax.tokens[this.tokensPos + 1];
                if(labelToken && labelToken.type == TokenType.LABEL && !labelToken.ex2 && (!this.ax.tokens[this.tokensPos + 2] || this.ax.tokens[this.tokensPos + 2].ex1)) {
                    this.pushNewInsn(sequence, InsnCode.GOTO,
                                     [this.labels[labelToken.code]]);
                    this.tokensPos += 2;
                } else {
                    this.tokensPos ++;
                    var argc = this.compileParameters(sequence);
                    if(argc != 1) throw this.error('goto の引数の数が違います', token);
                    this.pushNewInsn(sequence, InsnCode.GOTO_EXPR, [], token);
                }
                break;
            case 0x01: // gosub
                var labelToken = this.ax.tokens[this.tokensPos + 1];
                if(labelToken && labelToken.type == TokenType.LABEL && !labelToken.ex2 && (!this.ax.tokens[this.tokensPos + 2] || this.ax.tokens[this.tokensPos + 2].ex1)) {
                    this.pushNewInsn(sequence, InsnCode.GOSUB,
                                     [this.labels[labelToken.code]]);
                    this.tokensPos += 2;
                } else {
                    this.tokensPos ++;
                    var argc = this.compileParameters(sequence);
                    if(argc != 1) throw this.error('gosub の引数の数が違います', token);
                    this.pushNewInsn(sequence, InsnCode.GOSUB_EXPR, [], token);
                }
                break;
            case 0x02: // return
                this.tokensPos ++;
                if(this.ax.tokens[this.tokensPos].ex2) throw this.error('パラメータは省略できません', token);
                var existReturnValue = !this.ax.tokens[this.tokensPos].ex1;
                var usedPushVar: boolean = null;
                if(existReturnValue) {
                    usedPushVar = this.compileParameter(sequence, true);
                    if(this.compileParametersSub(sequence) > 0) throw this.error('return の引数が多すぎます', token);
                }
                this.pushNewInsn(sequence, InsnCode.RETURN, [existReturnValue, usedPushVar], token);
                break;
            case 0x03: // break
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != TokenType.LABEL) {
                    throw this.error();
                }
                var argc = this.compileParameters(sequence);
                if(argc > 0) throw this.error('break の引数が多すぎます', token);
                this.pushNewInsn(sequence, InsnCode.BREAK,
                                 [this.labels[labelToken.code]], token);
                break;
            case 0x04: // repeat
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != TokenType.LABEL) {
                    throw this.error();
                }
                var argc: number;
                if(this.ax.tokens[this.tokensPos].ex2) {
                    this.pushNewInsn(sequence, InsnCode.PUSH,
                                     [-1], token);
                    argc = 1 + this.compileParametersSub(sequence);
                } else {
                    argc = this.compileParameters(sequence);
                }
                if(argc > 2) throw this.error('repeat の引数が多すぎます', token);
                this.pushNewInsn(sequence, InsnCode.REPEAT,
                                 [this.labels[labelToken.code], argc], token);
                break;
            case 0x05: // loop
                this.tokensPos ++;
                var argc = this.compileParameters(sequence);
                if(argc > 0) throw this.error('loop の引数が多すぎます', token);
                this.pushNewInsn(sequence, InsnCode.LOOP, [], token);
                break;
            case 0x06: // continue
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != TokenType.LABEL) {
                    throw this.error();
                }
                var argc = this.compileParameters(sequence);
                if(argc > 1) throw this.error('continue の引数が多すぎます', token);
                this.pushNewInsn(sequence, InsnCode.CONTINUE,
                                 [this.labels[labelToken.code], argc], token);
                break;
            case 0x0b: // foreach
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != TokenType.LABEL) {
                    throw this.error();
                }
                var argc = this.compileParameters(sequence);
                if(argc > 0) throw this.error();
                this.pushNewInsn(sequence, InsnCode.FOREACH,
                                 [this.labels[labelToken.code]], token);
                break;
            case 0x0c: // eachchk
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != TokenType.LABEL) {
                    throw this.error();
                }
                var argc = this.compileParameters(sequence);
                if(argc != 1) throw this.error('foreach の引数の数が違います', token);
                this.pushNewInsn(sequence, InsnCode.EACHCHK,
                                 [this.labels[labelToken.code]], token);
                break;
            case 0x12: // newmod
                this.tokensPos ++;
                if(this.ax.tokens[this.tokensPos].ex2) {
                    throw this.error('パラメータは省略できません');
                }
                var varData = this.getVariableDataNoSubscript();
                var structToken = this.ax.tokens[this.tokensPos++];
                var prmInfo = this.ax.prmsInfo[structToken.code];
                if(structToken.type != TokenType.STRUCT || prmInfo.mptype != MPType.STRUCTTAG) {
                    throw this.error('モジュールが指定されていません', structToken);
                }
                var module = this.getModule(prmInfo.subid);
                var paramsInfo: any = null;
                var argc: number;
                if(module.constructor) {
                    paramsInfo = this.compileUserDefFuncall0(sequence, module.constructor, false, false);
                    argc = paramsInfo[0].length;
                } else {
                    argc = this.compileParametersSub(sequence);
                }
                this.pushNewInsn(sequence, InsnCode.NEWMOD,
                                 [varData, module, paramsInfo, argc], token);
                break;
            case 0x14: // delmod
                this.tokensPos ++;
                var argc = this.compileParameters(sequence);
                if(argc != 1) throw this.error('delmod の引数の数が違います', token);
                this.pushNewInsn(sequence, InsnCode.DELMOD, [], token);
                break;
            case 0x18: // exgoto
                this.tokensPos ++;
                var argc = this.compileParameters(sequence);
                if(argc != 4) throw this.error('exgoto の引数の数が違います', token);
                this.pushNewInsn(sequence, InsnCode.EXGOTO, [], token);
                break;
            case 0x19: // on
                this.tokensPos ++;
                var paramToken = this.ax.tokens[this.tokensPos];
                if(paramToken.ex1 || paramToken.ex2) {
                    throw this.error('パラメータは省略できません', token);
                }
                this.compileParameter(sequence);
                var jumpTypeToken = this.ax.tokens[this.tokensPos];
                if(jumpTypeToken.ex1 || jumpTypeToken.type != TokenType.PROGCMD || jumpTypeToken.code > 1) {
                    throw this.error('goto / gosub が指定されていません', token);
                }
                var isGosub = jumpTypeToken.code == 1;
                this.tokensPos ++;
                var argc = this.compileParametersSub(sequence);
                this.pushNewInsn(sequence, InsnCode.ON, [argc, isGosub], token);
                break;
            default:
                this.compileCommand(sequence);
            }
        }
        private compileBasicCommand(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos];
            switch(token.code) {
            case 0x00: // onexit
            case 0x01: // onerror
            case 0x02: // onkey
            case 0x03: // onclick
            case 0x04: // oncmd
                this.tokensPos ++;
                this.compileOptionalJumpType(sequence);
                var argc = 1 + this.compileParameters(sequence);
                this.pushNewInsn(sequence, InsnCode.CALL_BUILTIN_CMD,
                                 [token.type, token.code, argc], token);
                break;
            default:
                this.compileCommand(sequence);
            }
        }
        private compileGuiCommand(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos];
            switch(token.code) {
            case 0x00: // button
                this.tokensPos ++;
                this.compileOptionalJumpType(sequence);
                var argc = 1 + this.compileParameters(sequence);
                this.pushNewInsn(sequence, InsnCode.CALL_BUILTIN_CMD,
                                 [token.type, token.code, argc], token);
                break;
            default:
                this.compileCommand(sequence);
            }
        }
        private compileCommand(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos++];
            var argc = this.compileParameters(sequence);
            this.pushNewInsn(sequence, InsnCode.CALL_BUILTIN_CMD,
                             [token.type, token.code, argc], token);
        }
        private compileBranchCommand(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos++];
            var skipTo = token.pos + token.size + token.skipOffset;
            var label = new Label;
            if(skipTo in this.ifLabels) {
                this.ifLabels[skipTo].push(label);
            } else {
                this.ifLabels[skipTo] = [label];
            }
            var argc = this.compileParameters(sequence, true, true);
            if(token.code == 0) { // 'if'
                if(argc != 1) throw this.error("if の引数の数が間違っています。", token);
                this.pushNewInsn(sequence, InsnCode.IFEQ, [label], token);
            } else {
                if(argc != 0) throw this.error("else の引数の数が間違っています。", token);
                this.pushNewInsn(sequence, InsnCode.GOTO, [label], token);
            }
        }
        private compileParameters(sequence: Array<Insn>, cannotBeOmitted = false, notReceiveVar = false): number {
            var argc = 0;
            if(this.ax.tokens[this.tokensPos].ex2) {
                if(cannotBeOmitted) {
                    throw this.error('パラメータの省略はできません');
                }
                this.pushNewInsn(sequence, InsnCode.PUSH_DEFAULT, []);
                argc ++;
            }
            argc += this.compileParametersSub(sequence, cannotBeOmitted, notReceiveVar);
            return argc;
        }
        private compileParametersSub(sequence: Array<Insn>, cannotBeOmitted = false, notReceiveVar = false): number {
            var argc = 0;
            while(true) {
                var token = this.ax.tokens[this.tokensPos];
                if(!token || token.ex1) return argc;
                if(token.type == TokenType.MARK) {
                    if(token.code == 63) { // '?'
                        if(cannotBeOmitted) {
                            throw this.error('パラメータの省略はできません');
                        }
                        this.pushNewInsn(sequence, InsnCode.PUSH_DEFAULT, []);
                        this.tokensPos ++;
                        argc ++;
                        continue;
                    }
                    if(token.code == 41) { // ')'
                        return argc;
                    }
                }
                argc ++;
                this.compileParameter(sequence, notReceiveVar);
            }
        }
        /*
        notReceiveVar: パラメータが変数として受け取られうることがない (bool)
        dim や peek などの関数はパラメータを値としてではなく変数として受け取る。
        そのためにパラメータが単一の変数の場合は変数を表すオブジェクトをスタックに積む。
        でも、変数として受け取ることがないパラメータの場合、それは無駄である。
        このパラメータを true にすれば値そのものを積む命令を生成する。
        
        戻り値: パラメータが単一の変数であり、
                変数を積む命令を生成したとき true 、そうでないとき false
        */
        private compileParameter(sequence: Array<Insn>, notReceiveVar = false): boolean {
            var headPos = this.tokensPos;
            var usedPushVar = false;
            while(true) {
                var token = this.ax.tokens[this.tokensPos];
                if(!token || token.ex1) return usedPushVar;
                switch(token.type) {
                case TokenType.MARK:
                    if(token.code == 41) { // ')'
                        return usedPushVar;
                    }
                    this.compileOperator(sequence);
                    break;
                case TokenType.VAR:
                    var useGetVar = notReceiveVar || !this.isOnlyVar(this.tokensPos, headPos);
                    this.compileStaticVariable(sequence, useGetVar);
                    usedPushVar = !useGetVar;
                    break;
                case TokenType.STRING:
                    this.pushNewInsn(sequence, InsnCode.PUSH,
                                     [token.stringValue]);
                    this.tokensPos ++;
                    break;
                case TokenType.DNUM:
                    this.pushNewInsn(sequence, InsnCode.PUSH,
                                     [token.doubleValue]);
                    this.tokensPos ++;
                    break;
                case TokenType.INUM:
                    this.pushNewInsn(sequence, InsnCode.PUSH,
                                     [token.val]);
                    this.tokensPos ++;
                    break;
                case TokenType.STRUCT:
                    var onlyVar = this.isOnlyVar(this.tokensPos, headPos);
                    var result = this.compileStruct(sequence, notReceiveVar || !onlyVar);
                    if(onlyVar) usedPushVar = result;
                    break;
                case TokenType.LABEL:
                    this.pushNewInsn(sequence, InsnCode.PUSH,
                                     [this.labels[token.code]]);
                    this.tokensPos ++;
                    break;
                case TokenType.EXTSYSVAR:
                    this.compileExtSysvar(sequence);
                    break;
                case TokenType.SYSVAR:
                    this.compileSysvar(sequence);
                    break;
                case TokenType.MODCMD:
                    this.compileUserDefFuncall(sequence);
                    break;
                case TokenType.INTFUNC:
                case TokenType.DLLFUNC:
                case TokenType.DLLCTRL:
                    this.compileFuncall(sequence);
                    break;
                default:
                    throw this.error("命令コード " + token.type + " は解釈できません。");
                }
                token = this.ax.tokens[this.tokensPos];
                if(token && token.ex2) return usedPushVar;
            }
        }
        private isOnlyVar(pos: number, headPos: number): boolean {
            if(pos != headPos) return false;
            var nextTokenPos = pos + 1;
            nextTokenPos += this.skipParenAndParameters(nextTokenPos);
            var nextToken = this.ax.tokens[nextTokenPos];
            return (!nextToken || nextToken.ex1 || nextToken.ex2 || this.isRightParenToken(nextToken));
        }
        private skipParameter(pos: number): number {
            var size = 0;
            var parenLevel = 0;
            while(true) {
                var token = this.ax.tokens[pos + size];
                if(!token || token.ex1) return size;
                if(token.type == TokenType.MARK) {
                    switch(token.val) {
                    case 40:
                        parenLevel ++;
                        break;
                    case 41:
                        if(parenLevel == 0) return size;
                        parenLevel --;
                        break;
                    case 63:
                        return size + 1;
                        break;
                    }
                }
                size ++;
                token = this.ax.tokens[pos + size];
                if(parenLevel == 0 && token && token.ex2) {
                    return size;
                }
            }
        }
        private skipParameters(pos: number): number {
            var skipped = 0;
            var size = 0;
            while((skipped = this.skipParameter(pos + size))) {
                size += skipped;
            }
            return size;
        }
        private skipParenAndParameters(pos: number): number {
            var parenToken = this.ax.tokens[pos];
            if(!(parenToken && parenToken.type == TokenType.MARK && parenToken.code == 40)) {
                return 0;
            }
            var size = 1;
            size += this.skipParameters(pos + size);
            parenToken = this.ax.tokens[pos + size];
            if(!(parenToken && parenToken.type == TokenType.MARK && parenToken.code == 41)) {
                throw this.error('関数パラメータの後ろに閉じ括弧がありません。', parenToken);
            }
            return size + 1;
        }
        private compileOperator(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos++];
            if(!(0 <= token.code && token.code < 16)) {
                throw this.error("演算子コード " + token.code + " は解釈できません。", token);
            }
            var len = sequence.length;
            this.pushNewInsn(sequence, InsnCode.ADD + token.code, [], token);
        }
        private compileExtSysvar(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos];
            if(token.code >= 0x100) {
                this.compileFuncall(sequence);
            } else {
                this.compileSysvar(sequence);
            }
        }
        private compileStruct(sequence: Array<Insn>, useGetVar: boolean): boolean {
            var token = this.ax.tokens[this.tokensPos];
            var prmInfo = this.ax.prmsInfo[token.code];
            var usedPushVar = this.compileProxyVariable(sequence, useGetVar);
            if(usedPushVar == null) {
                var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(token.code)];
                this.pushNewInsn(sequence, InsnCode.GETARG,
                                 [token.code - funcInfo.prmindex], token);
            }
            return usedPushVar;
        }
        private compileSysvar(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos++];
            if(token.type == TokenType.SYSVAR && token.code == 0x04) {
                this.pushNewInsn(sequence, InsnCode.CNT, [], token);
                return;
            }
            this.pushNewInsn(sequence, InsnCode.CALL_BUILTIN_FUNC,
                             [token.type, token.code, 0], token);
        }
        private compileOptionalJumpType(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos];
            if(token.type == TokenType.PROGCMD && token.val == 0) { // goto
                this.pushNewInsn(sequence, InsnCode.PUSH, [0], token);
                this.tokensPos ++;
            } else if(token.type == TokenType.PROGCMD && token.val == 1) { // gosub
                this.pushNewInsn(sequence, InsnCode.PUSH, [1], token);
                this.tokensPos ++;
            } else {
                this.pushNewInsn(sequence, InsnCode.PUSH, [0], token);
            }
        }
        private compileUserDefFuncall(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos++];
            var userDefFunc = this.getUserDefFunc(token.code);
            var paramsInfo = this.compileUserDefFuncall0(sequence, userDefFunc, true, true);
            this.pushNewInsn(sequence, InsnCode.CALL_USERDEF_FUNC,
                             [userDefFunc, paramsInfo], token);
        }
        private compileUserDefCommand(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos++];
            var userDefFunc = this.getUserDefFunc(token.code);
            var paramsInfo = this.compileUserDefFuncall0(sequence, userDefFunc, false, true);
            this.pushNewInsn(sequence, InsnCode.CALL_USERDEF_CMD,
                             [userDefFunc, paramsInfo], token);
        }
        private compileUserDefFuncall0(sequence: Array<Insn>, userDefFunc: UserDefFunc, isCType: boolean, isHead: boolean): any {
            var argsCount = 0;
            var paramTypes: Array<ParamType> = [];
            var paramVals: Array<any>  = [];
            function nextMPType(): MPType {
                do {
                    var mptype = userDefFunc.paramTypes[argsCount++];
                } while(mptype == MPType.LOCALVAR);
                return mptype;
            }
            function push(type: ParamType, val: any) {
                paramTypes.push(type);
                paramVals.push(val);
            }
            if(isHead && isCType) this.compileLeftParen(sequence);
            if(isHead && this.ax.tokens[this.tokensPos].ex2) {
                push(ParamType.OMMITED, null);
                nextMPType();
            }
            while(true) {
                var token = this.ax.tokens[this.tokensPos];
                if(!token || token.ex1) break;
                if(token.type == TokenType.MARK) {
                    if(token.code == 63) { // '?'
                        this.tokensPos ++;
                        push(ParamType.OMMITED, null);
                        nextMPType();
                        continue;
                    }
                    if(token.code == 41) { // ')'
                        break;
                    }
                }
                var mptype = nextMPType();
                if(mptype == MPType.ARRAYVAR) {
                    if((token.type == TokenType.VAR || token.type == TokenType.STRUCT) &&
                       this.isOnlyVar(this.tokensPos, this.tokensPos)) {
                        push(ParamType.VARIABLE, this.getVariableData(sequence));
                    } else {
                        this.compileParameter(sequence, false);
                        push(ParamType.VALUE, null);
                    }
                    continue;
                }
                var notReceiveVar = mptype != MPType.SINGLEVAR && mptype != MPType.MODULEVAR;
                var usedPushVar = this.compileParameter(sequence, notReceiveVar);
                var literal: any = null;
                var insn = sequence[sequence.length - 1];
                if(insn.code == InsnCode.PUSH) {
                    literal = insn.opts[0];
                    sequence.pop();
                }
                push(usedPushVar ? ParamType.VARIABLE : ParamType.VALUE, literal);
            }
            if(isCType) this.compileRightParen(sequence);
            return [paramTypes, paramVals];
        }
        private getUserDefFunc(finfoId: number): UserDefFunc {
            var func = this.userDefFuncs[finfoId];
            if(func) return func;
            var funcInfo = this.ax.funcsInfo[finfoId];
            if (funcInfo.index != -1 && funcInfo.index != -2) { // STRUCTDAT_INDEX_FUNC, STRUCTDAT_INDEX_CFUNC
                return null;
            }
            var isCType = funcInfo.index == -2;
            var paramTypes: Array<MPType> = [];
            for(var i = 0; i < funcInfo.prmmax; i ++) {
                paramTypes[i] = this.ax.prmsInfo[funcInfo.prmindex + i].mptype;
            }
            return this.userDefFuncs[finfoId] = new UserDefFunc(isCType, funcInfo.name, this.labels[funcInfo.otindex], paramTypes, finfoId);
        }
        private getModule(finfoId: number): Module {
            var module = this.modules[finfoId];
            if(module) return module;
            var funcInfo = this.ax.funcsInfo[finfoId];
            if(funcInfo.index != -3) { // STRUCTDAT_INDEX_STRUCT
                return null;
            }
            var destructor = funcInfo.otindex != 0 ? this.getUserDefFunc(funcInfo.otindex) : null;
            var constructorFinfoId = this.ax.prmsInfo[funcInfo.prmindex].offset;
            var constructor = constructorFinfoId != -1 ? this.getUserDefFunc(constructorFinfoId) : null;
            return this.modules[finfoId] = new Module(funcInfo.name, constructor, destructor, funcInfo.prmmax - 1, finfoId);
        }
        private compileFuncall(sequence: Array<Insn>) {
            var token = this.ax.tokens[this.tokensPos++];
            var argc = this.compileParenAndParameters(sequence);
            this.pushNewInsn(sequence, InsnCode.CALL_BUILTIN_FUNC,
                             [token.type, token.code, argc], token);
        }
        private compileParenAndParameters(sequence: Array<Insn>): number {
            this.compileLeftParen(sequence);
            var argc = this.compileParameters(sequence);
            this.compileRightParen(sequence);
            return argc;
        }
        private compileLeftParen(sequence: Array<Insn>) {
            var parenToken = this.ax.tokens[this.tokensPos++];
            if(!(parenToken && parenToken.type == TokenType.MARK && parenToken.code == 40)) {
                throw this.error('関数名の後ろに開き括弧がありません。', parenToken);
            }
        }
        private compileRightParen(sequence: Array<Insn>) {
            var parenToken = this.ax.tokens[this.tokensPos++];
            if(!(parenToken && parenToken.type == TokenType.MARK && parenToken.code == 41)) {
                throw this.error('関数パラメータの後ろに閉じ括弧がありません。', parenToken);
            }
        }
        private compileVariable(sequence: Array<Insn>) {
            switch(this.ax.tokens[this.tokensPos].type) {
            case TokenType.VAR:
                this.compileStaticVariable(sequence);
                return;
            case TokenType.STRUCT:
                if(this.compileProxyVariable(sequence) != null) return;
            }
            throw this.error('変数が指定されていません');
        }
        private compileStaticVariable(sequence: Array<Insn>, useGetVar = false) {
            var token = this.ax.tokens[this.tokensPos++];
            var argc = this.compileVariableSubscript(sequence);
            this.pushNewInsn(sequence, useGetVar ? InsnCode.GET_VAR : InsnCode.PUSH_VAR,
                             [token.code, argc], token);
        }
        private compileProxyVariable(sequence: Array<Insn>, useGetVar = false): boolean {
            var proxyVarType = this.getProxyVarType();
            var token = this.ax.tokens[this.tokensPos++];
            var prmInfo = this.ax.prmsInfo[token.code];
            var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(token.code)];
            switch(proxyVarType) {
            case ProxyVarType.THISMOD:
                this.pushNewInsn(sequence, InsnCode.THISMOD, [], token);
                return true;
            case ProxyVarType.MEMBER:
                var argc = this.compileVariableSubscript(sequence);
                this.pushNewInsn(sequence, useGetVar ? InsnCode.GET_MEMBER : InsnCode.PUSH_MEMBER,
                                 [token.code - funcInfo.prmindex - 1, argc], token);
                return useGetVar;
            case ProxyVarType.ARG_VAR:
                this.pushNewInsn(sequence, InsnCode.GETARG,
                                 [token.code - funcInfo.prmindex], token);
                return true;
            case ProxyVarType.ARG_ARRAY:
            case ProxyVarType.ARG_LOCAL:
                var argc = this.compileVariableSubscript(sequence);
                this.pushNewInsn(sequence, useGetVar ? InsnCode.GET_ARG_VAR : InsnCode.PUSH_ARG_VAR,
                                 [token.code - funcInfo.prmindex, argc], token);
                return useGetVar;
            default:
                return null;
            }
        }
        private getVariableData(sequence: Array<Insn>): any {
            var token = this.ax.tokens[this.tokensPos];
            var result = this.getVariableData0();
            this.tokensPos ++;
            var argc = this.compileVariableSubscript(sequence);
            if(argc) {
                this.pushNewInsn(sequence, InsnCode.POP_N, [argc], token);
            }
            return result;
        }
        private getVariableDataNoSubscript(): any {
            var result = this.getVariableData0();
            if(this.isLeftParenToken(this.ax.tokens[++this.tokensPos])) {
                throw this.error('変数の添字は指定できません');
            }
            return result;
        }
        private getVariableData0(): any {
            var token = this.ax.tokens[this.tokensPos];
            if(token.type == TokenType.VAR) {
                return [ProxyVarType.STATIC, token.code];
            } else if(token.type == TokenType.STRUCT) {
                var type = this.getProxyVarType();
                var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(token.code)];
                if(type == ProxyVarType.MEMBER) {
                    return [type, token.code - funcInfo.prmindex - 1];
                } else {
                    return [type, token.code - funcInfo.prmindex];
                }
            } else {
                throw new Error('must not happen');
            }
        }
        private getProxyVarType() {
            var token = this.ax.tokens[this.tokensPos];
            if(token.code == -1) {
                if(this.isLeftParenToken(this.ax.tokens[this.tokensPos + 1])) {
                    throw this.error('thismod に添字を指定しています');
                }
                return ProxyVarType.THISMOD;
            }
            var prmInfo = this.ax.prmsInfo[token.code];
            if(prmInfo.subid >= 0) {
                return ProxyVarType.MEMBER;
            }
            switch(prmInfo.mptype) {
            case MPType.LOCALVAR:
                return ProxyVarType.ARG_LOCAL;
            case MPType.ARRAYVAR:
                return ProxyVarType.ARG_ARRAY;
            case MPType.SINGLEVAR:
                if(this.isLeftParenToken(this.ax.tokens[this.tokensPos + 1])) {
                    throw this.error('パラメータタイプ var の変数に添字を指定しています');
                }
                return ProxyVarType.ARG_VAR;
            default:
                return null;
            }
        }
        private isLeftParenToken(token: Token) {
            return token && token.type == TokenType.MARK && token.code == 40;
        }
        private isRightParenToken(token: Token) {
            return token && token.type == TokenType.MARK && token.code == 41;
        }
        private compileVariableSubscript(sequence: Array<Insn>): number {
            var argc = 0;
            var parenToken = this.ax.tokens[this.tokensPos];
            if(parenToken && parenToken.type == TokenType.MARK && parenToken.code == 40) {
                this.tokensPos ++;
                argc = this.compileParameters(sequence, true, true);
                if(argc == 0) {
                    throw this.error('配列変数の添字が空です', parenToken);
                }
                parenToken = this.ax.tokens[this.tokensPos++];
                if(!(parenToken && parenToken.type == TokenType.MARK && parenToken.code == 41)) {
                    throw this.error('配列変数の添字の後ろに閉じ括弧がありません。', parenToken);
                }
            }
            return argc;
        }
    }

    class Insn {
        constructor(public code: InsnCode, public opts: any, public fileName: string, public lineNo: number) {}
    }

    class Label {
        public pos: number = null;
        constructor() {}
    }

    class UserDefFunc {
        constructor(public isCType: boolean, public name: string, public label: Label, public paramTypes: Array<MPType>, public id: number) {}
    }

    class Module {
        constructor(public name: string, public constructor: UserDefFunc, public destructor: UserDefFunc, public membersCount: number, public id: number) {}
    }

    enum InsnCode {
        NOP,
        PUSH,
        PUSH_DEFAULT,
        PUSH_VAR,
        GET_VAR,
        POP,
        POP_N,
        DUP,
        ADD,
        SUB,
        MUL,
        DIV,
        MOD,
        AND,
        OR,
        XOR,
        EQ,
        NE,
        GT,
        LT,
        GTEQ,
        LTEQ,
        RSH,
        LSH,
        GOTO,
        IFNE,
        IFEQ,
        ASSIGN,
        ASSIGN_STATIC_VAR,
        ASSIGN_ARG_ARRAY,
        ASSIGN_MEMBER,
        COMPOUND_ASSIGN,
        COMPOUND_ASSIGN_STATIC_VAR,
        COMPOUND_ASSIGN_ARG_ARRAY,
        COMPOUND_ASSIGN_MEMBER,
        INC,
        INC_STATIC_VAR,
        INC_ARG_ARRAY,
        INC_MEMBER,
        DEC,
        DEC_STATIC_VAR,
        DEC_ARG_ARRAY,
        DEC_MEMBER,
        CALL_BUILTIN_CMD,
        CALL_BUILTIN_FUNC,
        CALL_USERDEF_CMD,
        CALL_USERDEF_FUNC,
        GETARG,
        PUSH_ARG_VAR,
        GET_ARG_VAR,
        PUSH_MEMBER,
        GET_MEMBER,
        THISMOD,
        NEWMOD,
        RETURN,
        DELMOD,
        REPEAT,
        LOOP,
        CNT,
        CONTINUE,
        BREAK,
        FOREACH,
        EACHCHK,
        GOSUB,
        GOTO_EXPR,
        GOSUB_EXPR,
        EXGOTO,
        EXGOTO_OPT1,
        EXGOTO_OPT2,
        EXGOTO_OPT3,
        ON,
    }

    enum ProxyVarType {
        STATIC,
        THISMOD,
        MEMBER,
        ARG_VAR,
        ARG_ARRAY,
        ARG_LOCAL,
    }

    enum ParamType {
        OMMITED,
        VARIABLE,
        VALUE,
    }

    class CompileError {
        constructor(public message: string, public hspFileName: string, public hspLineNumber: number) {}
    }
}
