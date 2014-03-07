module BitterHSP {
    export class Compiler {
        private tokensPos = 0;
        private labels: Array<Label>;
        private ifLabels: NumDictionary<V> = Object.create(null);
        private userDefFuncs: Array<UserDefFunc>;
        
        constructor(private ax: AXData) {
            this.labels = []; // HSP のラベルIDに対応したラベル
            for(var i = 0; i < ax.labels.length; i ++) {
                this.labels[i] = new Label;
            }
        }

        private compile() {
            var sequence = [];
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
                case Token.Type.VAR:
                case Token.Type.STRUCT:
                    this.compileAssignment(sequence);
                    break;
                case Token.Type.CMPCMD:
                    this.compileBranchCommand(sequence);
                    break;
                case Token.Type.PROGCMD:
                    this.compileProgramCommand(sequence);
                    break;
                case Token.Type.MODCMD:
                    this.compileUserDefCommand(sequence);
                    break;
                case Token.Type.INTCMD:
                    this.compileBasicCommand(sequence);
                    break;
                case Token.Type.EXTCMD:
                    this.compileGuiCommand(sequence);
                    break;
                case Token.Type.DLLFUNC:
                case Token.Type.DLLCTRL:
                    this.compileCommand(sequence);
                    break;
                default:
                    throw this.error("命令コード " + token.type + " は解釈できません。");
                }
            }
            return sequence;
        }
        private pushNewInsn(sequence, code, opts, token) {
            token || (token = this.ax.tokens[this.tokensPos]);
            sequence.push(new Instruction(code, opts, token.fileName, token.lineNo));
        }
        private getFinfoIdByMinfoId(minfoId) {
            var funcsInfo = this.ax.funcsInfo;
            for(var i = 0; i < funcsInfo.length; i ++) {
                var funcInfo = funcsInfo[i];
                if(funcInfo.prmindex <= minfoId && minfoId < funcInfo.prmindex + funcInfo.prmmax) {
                    return i;
                }
            }
            return null;
        }
        private error(message, token) {
            token || (token = this.ax.tokens[this.tokensPos]);
            return new CompileError(message, token.fileName, token.lineNo);
        }
        private compileAssignment(sequence) {
            var varToken = this.ax.tokens[this.tokensPos];
            var insnCode;
            var opts;
            switch(varToken.type) {
            case Token.Type.VAR:
                this.tokensPos ++;
                insnCode = 1;
                var indicesCount = this.compileVariableSubscript(sequence);
                opts = [varToken.code, indicesCount];
                break;
            case Token.Type.STRUCT:
                var proxyVarType = this.getProxyVarType();
                if(!proxyVarType) {
                    throw this.error('変数が指定されていません');
                }
                var prmInfo = this.ax.prmsInfo[varToken.code];
                var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(varToken.code)];
                switch(proxyVarType) {
                case Compiler.ProxyVarType.THISMOD:
                    insnCode = 0;
                    opts = [];
                    this.compileProxyVariable(sequence);
                    break;
                case Compiler.ProxyVarType.MEMBER:
                    insnCode = 3;
                    this.tokensPos ++;
                    var indicesCount = this.compileVariableSubscript(sequence);
                    opts = [varToken.code - funcInfo.prmindex - 1, indicesCount];
                    break;
                case Compiler.ProxyVarType.ARG_VAR:
                    insnCode = 0;
                    opts = [];
                    this.compileProxyVariable(sequence);
                    break;
                case Compiler.ProxyVarType.ARG_ARRAY:
                case Compiler.ProxyVarType.ARG_LOCAL:
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
            if(!(token && token.type == Token.Type.MARK)) {
                throw this.error();
            }
            if(this.ax.tokens[this.tokensPos].ex1) {
                if(token.val == 0) { // インクリメント
                    this.pushNewInsn(sequence, Instruction.Code.INC + insnCode, opts, token);
                    return;
                }
                if(token.val == 1) { // デクリメント
                    this.pushNewInsn(sequence, Instruction.Code.DEC + insnCode, opts, token);
                    return;
                }
            }
            if(token.val != 8) { // CALCCODE_EQ
                // 複合代入
                var argc = this.compileParameters(sequence, true, true);
                if(argc != 1) {
                    throw this.error("複合代入のパラメータの数が間違っています。", token);
                }
                this.pushNewInsn(sequence, Instruction.Code.COMPOUND_ASSIGN + insnCode, [token.val].concat(opts), token);
                return;
            }
            var argc = this.compileParameters(sequence, true, true);
            if(argc == 0) {
                throw this.error("代入のパラメータの数が間違っています。", token);
            }
            this.pushNewInsn(sequence, Instruction.Code.ASSIGN + insnCode, opts.concat([argc]), token);
        }
        private compileProgramCommand(sequence) {
            var token = this.ax.tokens[this.tokensPos];
            switch(token.code) {
            case 0x00: // goto
                var labelToken = this.ax.tokens[this.tokensPos + 1];
                if(labelToken && labelToken.type == Token.Type.LABEL && !labelToken.ex2 && (!this.ax.tokens[this.tokensPos + 2] || this.ax.tokens[this.tokensPos + 2].ex1)) {
                    this.pushNewInsn(sequence, Instruction.Code.GOTO,
                                     [this.labels[labelToken.code]]);
                    this.tokensPos += 2;
                } else {
                    this.tokensPos ++;
                    var argc = this.compileParameters(sequence);
                    if(argc != 1) throw this.error('goto の引数の数が違います', token);
                    this.pushNewInsn(sequence, Instruction.Code.GOTO_EXPR, [], token);
                }
                break;
            case 0x01: // gosub
                var labelToken = this.ax.tokens[this.tokensPos + 1];
                if(labelToken && labelToken.type == Token.Type.LABEL && !labelToken.ex2 && (!this.ax.tokens[this.tokensPos + 2] || this.ax.tokens[this.tokensPos + 2].ex1)) {
                    this.pushNewInsn(sequence, Instruction.Code.GOSUB,
                                     [this.labels[labelToken.code]]);
                    this.tokensPos += 2;
                } else {
                    this.tokensPos ++;
                    var argc = this.compileParameters(sequence);
                    if(argc != 1) throw this.error('gosub の引数の数が違います', token);
                    this.pushNewInsn(sequence, Instruction.Code.GOSUB_EXPR, [], token);
                }
                break;
            case 0x02: // return
                this.tokensPos ++;
                if(this.ax.tokens[this.tokensPos].ex2) throw this.error('パラメータは省略できません', token);
                var existReturnValue = !this.ax.tokens[this.tokensPos].ex1;
                var usedPushVar = null;
                if(existReturnValue) {
                    var usedPushVar = this.compileParameter(sequence, true);
                    if(this.compileParametersSub(sequence) > 0) throw this.error('return の引数が多すぎます', token);
                }
                this.pushNewInsn(sequence, Instruction.Code.RETURN, [existReturnValue, usedPushVar], token);
                break;
            case 0x03: // break
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != Token.Type.LABEL) {
                    throw this.error();
                }
                var argc = this.compileParameters(sequence);
                if(argc > 0) throw this.error('break の引数が多すぎます', token);
                this.pushNewInsn(sequence, Instruction.Code.BREAK,
                                 [this.labels[labelToken.code]], token);
                break;
            case 0x04: // repeat
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != Token.Type.LABEL) {
                    throw this.error();
                }
                var argc;
                if(this.ax.tokens[this.tokensPos].ex2) {
                    this.pushNewInsn(sequence, Instruction.Code.PUSH,
                                     [new IntValue(-1)], token);
                    argc = 1 + this.compileParametersSub(sequence);
                } else {
                    argc = this.compileParameters(sequence);
                }
                if(argc > 2) throw this.error('repeat の引数が多すぎます', token);
                this.pushNewInsn(sequence, Instruction.Code.REPEAT,
                                 [this.labels[labelToken.code], argc], token);
                break;
            case 0x05: // loop
                this.tokensPos ++;
                var argc = this.compileParameters(sequence);
                if(argc > 0) throw this.error('loop の引数が多すぎます', token);
                this.pushNewInsn(sequence, Instruction.Code.LOOP, [], token);
                break;
            case 0x06: // continue
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != Token.Type.LABEL) {
                    throw this.error();
                }
                var argc = this.compileParameters(sequence);
                if(argc > 1) throw this.error('continue の引数が多すぎます', token);
                this.pushNewInsn(sequence, Instruction.Code.CONTINUE,
                                 [this.labels[labelToken.code], argc], token);
                break;
            case 0x0b: // foreach
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != Token.Type.LABEL) {
                    throw this.error();
                }
                var argc = this.compileParameters(sequence);
                if(argc > 0) throw this.error();
                this.pushNewInsn(sequence, Instruction.Code.FOREACH,
                                 [this.labels[labelToken.code]], token);
                break;
            case 0x0c: // eachchk
                this.tokensPos ++;
                var labelToken = this.ax.tokens[this.tokensPos++];
                if(labelToken.type != Token.Type.LABEL) {
                    throw this.error();
                }
                var argc = this.compileParameters(sequence);
                if(argc != 1) throw this.error('foreach の引数の数が違います', token);
                this.pushNewInsn(sequence, Instruction.Code.EACHCHK,
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
                if(structToken.type != Token.Type.STRUCT || prmInfo.mptype != MPType.STRUCTTAG) {
                    throw this.error('モジュールが指定されていません', structToken);
                }
                var module = this.getUserDefFunc(prmInfo.subid);
                var paramsInfo = null;
                var argc;
                if(module.constructor) {
                    paramsInfo = this.compileUserDefFuncall0(sequence, module.constructor, false, false);
                    argc = paramsInfo[0].length;
                } else {
                    argc = this.compileParametersSub(sequence);
                }
                this.pushNewInsn(sequence, Instruction.Code.NEWMOD,
                                 [varData, module, paramsInfo, argc], token);
                break;
            case 0x14: // delmod
                this.tokensPos ++;
                var argc = this.compileParameters(sequence);
                if(argc != 1) throw this.error('delmod の引数の数が違います', token);
                this.pushNewInsn(sequence, Instruction.Code.DELMOD, [], token);
                break;
            case 0x18: // exgoto
                this.tokensPos ++;
                // exgoto <添字指定のない静的変数>, p2, p3, <ラベルリテラル> を最適化
                var pos = this.tokensPos;
                var varToken = this.ax.tokens[pos];
                if(!varToken.ex1 && !varToken.ex2 &&
                   varToken.type == Token.Type.VAR && this.ax.tokens[pos + 1].ex2) {
                    pos ++;
                    var secondParamPos = pos;
                    pos += this.skipParameter(pos);
                    var thirdParamPos = pos;
                    pos += this.skipParameter(pos);
                    var labelToken = this.ax.tokens[pos];
                    if(labelToken && !labelToken.ex1 &&
                       labelToken.type == Token.Type.LABEL && this.ax.tokens[pos+1]) {
                        // p2 が整数リテラルの場合はさらに最適化
                        if(secondParamPos + 1 == thirdParamPos && this.ax.tokens[secondParamPos].type == Token.Type.INUM) {
                            this.tokensPos = thirdParamPos;
                            this.compileParameter(sequence);
                            if(this.ax.tokens[secondParamPos].code >= 0) {
                                this.pushNewInsn(sequence, Instruction.Code.EXGOTO_OPT2,
                                                 [varToken.code, this.labels[labelToken.code]], token);
                            } else {
                                this.pushNewInsn(sequence, Instruction.Code.EXGOTO_OPT3,
                                                 [varToken.code, this.labels[labelToken.code]], token);
                            }
                            this.tokensPos = pos + 1;
                            break;
                        }
                        this.tokensPos = secondParamPos;
                        this.compileParameter(sequence);
                        this.compileParameter(sequence);
                        this.pushNewInsn(sequence, Instruction.Code.EXGOTO_OPT1,
                                         [varToken.code, this.labels[labelToken.code]], token);
                        this.tokensPos = pos + 1;
                        break;
                    }
                }
                var argc = this.compileParameters(sequence);
                if(argc != 4) throw this.error('exgoto の引数の数が違います', token);
                this.pushNewInsn(sequence, Instruction.Code.EXGOTO, [], token);
                break;
            case 0x19: // on
                this.tokensPos ++;
                var paramToken = this.ax.tokens[this.tokensPos];
                if(paramToken.ex1 || paramToken.ex2) {
                    throw this.error('パラメータは省略できません', token);
                }
                this.compileParameter(sequence);
                var jumpTypeToken = this.ax.tokens[this.tokensPos];
                if(jumpTypeToken.ex1 || jumpTypeToken.type != Token.Type.PROGCMD || jumpTypeToken.code > 1) {
                    throw this.error('goto / gosub が指定されていません', token);
                }
                var isGosub = jumpTypeToken.code == 1;
                this.tokensPos ++;
                var argc = this.compileParametersSub(sequence);
                this.pushNewInsn(sequence, Instruction.Code.ON, [argc, isGosub], token);
                break;
            default:
                this.compileCommand(sequence);
            }
        }
        private compileBasicCommand(sequence) {
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
                this.pushNewInsn(sequence, Instruction.Code.CALL_BUILTIN_CMD,
                                 [token.type, token.code, argc], token);
                break;
            default:
                this.compileCommand(sequence);
            }
        }
        private compileGuiCommand(sequence) {
            var token = this.ax.tokens[this.tokensPos];
            switch(token.code) {
            case 0x00: // button
                this.tokensPos ++;
                this.compileOptionalJumpType(sequence);
                var argc = 1 + this.compileParameters(sequence);
                this.pushNewInsn(sequence, Instruction.Code.CALL_BUILTIN_CMD,
                                 [token.type, token.code, argc], token);
                break;
            default:
                this.compileCommand(sequence);
            }
        }
        private compileCommand(sequence) {
            var token = this.ax.tokens[this.tokensPos++];
            var argc = this.compileParameters(sequence);
            this.pushNewInsn(sequence, Instruction.Code.CALL_BUILTIN_CMD,
                             [token.type, token.code, argc], token);
        }
        private compileBranchCommand(sequence) {
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
                // if の条件式がリテラルのとき最適化
                var lastInsn = sequence[sequence.length - 1];
                if(lastInsn.code == Instruction.Code.PUSH &&
                   (lastInsn.opts[0].getType() == VarType.INT || lastInsn.opts[0].getType() == VarType.DOUBLE)) {
                    sequence.pop();
                    if(!lastInsn.opts[0]._value) {
                        this.pushNewInsn(sequence, Instruction.Code.GOTO, [label], token);
                    }
                    return;
                }
                this.pushNewInsn(sequence, Instruction.Code.IFEQ, [label], token);
            } else {
                if(argc != 0) throw this.error("else の引数の数が間違っています。", token);
                this.pushNewInsn(sequence, Instruction.Code.GOTO, [label], token);
            }
        }
        private compileParameters(sequence, cannotBeOmitted, notReceiveVar) {
            var argc = 0;
            if(this.ax.tokens[this.tokensPos].ex2) {
                if(cannotBeOmitted) {
                    throw this.error('パラメータの省略はできません');
                }
                this.pushNewInsn(sequence, Instruction.Code.PUSH_DEFAULT, []);
                argc ++;
            }
            argc += this.compileParametersSub(sequence, cannotBeOmitted, notReceiveVar);
            return argc;
        }
        private compileParametersSub(sequence, cannotBeOmitted, notReceiveVar) {
            var argc = 0;
            while(true) {
                var token = this.ax.tokens[this.tokensPos];
                if(!token || token.ex1) return argc;
                if(token.type == Token.Type.MARK) {
                    if(token.code == 63) { // '?'
                        if(cannotBeOmitted) {
                            throw this.error('パラメータの省略はできません');
                        }
                        this.pushNewInsn(sequence, Instruction.Code.PUSH_DEFAULT, []);
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
        private compileParameter(sequence, notReceiveVar) {
            var headPos = this.tokensPos;
            var usedPushVar = false;
            while(true) {
                var token = this.ax.tokens[this.tokensPos];
                if(!token || token.ex1) return usedPushVar;
                switch(token.type) {
                case Token.Type.MARK:
                    if(token.code == 41) { // ')'
                        return usedPushVar;
                    }
                    this.compileOperator(sequence);
                    break;
                case Token.Type.VAR:
                    var useGetVar = notReceiveVar || !this.isOnlyVar(this.tokensPos, headPos);
                    this.compileStaticVariable(sequence, useGetVar);
                    usedPushVar = !useGetVar;
                    break;
                case Token.Type.STRING:
                    this.pushNewInsn(sequence, Instruction.Code.PUSH,
                                     [new StrValue(token.val)]);
                    this.tokensPos ++;
                    break;
                case Token.Type.DNUM:
                    this.pushNewInsn(sequence, Instruction.Code.PUSH,
                                     [new DoubleValue(token.val)]);
                    this.tokensPos ++;
                    break;
                case Token.Type.INUM:
                    this.pushNewInsn(sequence, Instruction.Code.PUSH,
                                     [new IntValue(token.val)]);
                    this.tokensPos ++;
                    break;
                case Token.Type.STRUCT:
                    var onlyVar = this.isOnlyVar(this.tokensPos, headPos);
                    var result = this.compileStruct(sequence, notReceiveVar || !onlyVar);
                    if(onlyVar) usedPushVar = result;
                    break;
                case Token.Type.LABEL:
                    this.pushNewInsn(sequence, Instruction.Code.PUSH,
                                     [this.labels[token.code]]);
                    this.tokensPos ++;
                    break;
                case Token.Type.EXTSYSVAR:
                    this.compileExtSysvar(sequence);
                    break;
                case Token.Type.SYSVAR:
                    this.compileSysvar(sequence);
                    break;
                case Token.Type.MODCMD:
                    this.compileUserDefFuncall(sequence);
                    break;
                case Token.Type.INTFUNC:
                case Token.Type.DLLFUNC:
                case Token.Type.DLLCTRL:
                    this.compileFuncall(sequence);
                    break;
                default:
                    throw this.error("命令コード " + token.type + " は解釈できません。");
                }
                token = this.ax.tokens[this.tokensPos];
                if(token && token.ex2) return usedPushVar;
            }
        }
        private isOnlyVar(pos, headPos) {
            if(pos != headPos) return false;
            var nextTokenPos = pos + 1;
            nextTokenPos += this.skipParenAndParameters(nextTokenPos);
            var nextToken = this.ax.tokens[nextTokenPos];
            return (!nextToken || nextToken.ex1 || nextToken.ex2 || this.isRightParenToken(nextToken));
        }
        private skipParameter(pos) {
            var size = 0;
            var parenLevel = 0;
            while(true) {
                var token = this.ax.tokens[pos + size];
                if(!token || token.ex1) return size;
                if(token.type == Token.Type.MARK) {
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
        private skipParameters(pos) {
            var skipped = 0;
            var size = 0;
            while((skipped = this.skipParameter(pos + size))) {
                size += skipped;
            }
            return size;
        }
        private skipParenAndParameters(pos) {
            var parenToken = this.ax.tokens[pos];
            if(!(parenToken && parenToken.type == Token.Type.MARK && parenToken.code == 40)) {
                return 0;
            }
            var size = 1;
            size += this.skipParameters(pos + size);
            parenToken = this.ax.tokens[pos + size];
            if(!(parenToken && parenToken.type == Token.Type.MARK && parenToken.code == 41)) {
                throw this.error('関数パラメータの後ろに閉じ括弧がありません。', parenToken);
            }
            return size + 1;
        }
        private compileOperator(sequence) {
            var token = this.ax.tokens[this.tokensPos++];
            if(!(0 <= token.code && token.code < 16)) {
                throw this.error("演算子コード " + token.code + " は解釈できません。", token);
            }
            var len = sequence.length;
            // リテラル同士の演算の最適化 ex. 1 + 1 -> 2
            if(len >= 2 &&
               sequence[len-2].code == Instruction.Code.PUSH &&
               sequence[len-1].code == Instruction.Code.PUSH &&
               sequence[len-2].opts[0] && sequence[len-1].opts[0]) {
                var lhs = sequence[len-2].opts[0], rhs = sequence[len-1].opts[0];
                try {
                    var result = this.operate(lhs, rhs, token.code);
                    sequence.length -= 2;
                    this.pushNewInsn(sequence, Instruction.Code.PUSH, [result], token);
                    return;
                } catch(e) {
                    if(!(e instanceof HSPError)) throw e;
                }
            }
            this.pushNewInsn(sequence, Instruction.Code.ADD + token.code, [], token);
        }
        private operate(lhs, rhs, calcCode) {
            switch(calcCode) {
            case  0: return lhs.add(rhs);
            case  1: return lhs.sub(rhs);
            case  2: return lhs.mul(rhs);
            case  3: return lhs.div(rhs);
            case  4: return lhs.mod(rhs);
            case  5: return lhs.and(rhs);
            case  6: return lhs.or(rhs);
            case  7: return lhs.xor(rhs);
            case  8: return lhs.eq(rhs);
            case  9: return lhs.ne(rhs);
            case 10: return lhs.gt(rhs);
            case 11: return lhs.lt(rhs);
            case 12: return lhs.gteq(rhs);
            case 13: return lhs.lteq(rhs);
            case 14: return lhs.rsh(rhs);
            case 15: return lhs.lsh(rhs);
            default:  throw new Error('must not happen');
            }
        }
        private compileExtSysvar(sequence) {
            var token = this.ax.tokens[this.tokensPos];
            if(token.code >= 0x100) {
                this.compileFuncall(sequence);
            } else {
                this.compileSysvar(sequence);
            }
        }
        private compileStruct(sequence, useGetVar) {
            var token = this.ax.tokens[this.tokensPos];
            var prmInfo = this.ax.prmsInfo[token.code];
            var usedPushVar = this.compileProxyVariable(sequence, useGetVar);
            if(usedPushVar == null) {
                var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(token.code)];
                this.pushNewInsn(sequence, Instruction.Code.GETARG,
                                 [token.code - funcInfo.prmindex], token);
            }
            return usedPushVar;
        }
        private compileSysvar(sequence) {
            var token = this.ax.tokens[this.tokensPos++];
            if(token.type == Token.Type.SYSVAR && token.code == 0x04) {
                this.pushNewInsn(sequence, Instruction.Code.CNT, [], token);
                return;
            }
            this.pushNewInsn(sequence, Instruction.Code.CALL_BUILTIN_FUNC,
                             [token.type, token.code, 0], token);
        }
        private compileOptionalJumpType(sequence) {
            var token = this.ax.tokens[this.tokensPos];
            if(token.type == Token.Type.PROGCMD && token.val == 0) {
                this.pushNewInsn(sequence, Instruction.Code.PUSH, [JumpType.GOTO], token);
                this.tokensPos ++;
            } else if(token.type == Token.Type.PROGCMD && token.val == 1) {
                this.pushNewInsn(sequence, Instruction.Code.PUSH, [JumpType.GOSUB], token);
                this.tokensPos ++;
            } else {
                this.pushNewInsn(sequence, Instruction.Code.PUSH, [JumpType.GOTO], token);
            }
        }
        private compileUserDefFuncall(sequence) {
            var token = this.ax.tokens[this.tokensPos++];
            var userDefFunc = this.getUserDefFunc(token.code);
            var paramsInfo = this.compileUserDefFuncall0(sequence, userDefFunc, true, true);
            this.pushNewInsn(sequence, Instruction.Code.CALL_USERDEF_FUNC,
                             [userDefFunc, paramsInfo], token);
        }
        private compileUserDefCommand(sequence) {
            var token = this.ax.tokens[this.tokensPos++];
            var userDefFunc = this.getUserDefFunc(token.code);
            var paramsInfo = this.compileUserDefFuncall0(sequence, userDefFunc, false, true);
            this.pushNewInsn(sequence, Instruction.Code.CALL_USERDEF_CMD,
                             [userDefFunc, paramsInfo], token);
        }
        private compileUserDefFuncall0(sequence, userDefFunc, isCType, isHead) {
            var argsCount = 0;
            var paramTypes = [];
            var paramVals = [];
            function nextMPType() {
                do {
                    var mptype = userDefFunc.paramTypes[argsCount++];
                } while(mptype == MPType.LOCALVAR);
                return mptype;
            }
            function push(type, val) {
                paramTypes.push(type);
                paramVals.push(val);
            }
            if(isHead && isCType) this.compileLeftParen(sequence);
            if(isHead && this.ax.tokens[this.tokensPos].ex2) {
                push(Compiler.ParamType.OMMITED, null);
                nextMPType();
            }
            while(true) {
                var token = this.ax.tokens[this.tokensPos];
                if(!token || token.ex1) break;
                if(token.type == Token.Type.MARK) {
                    if(token.code == 63) { // '?'
                        this.tokensPos ++;
                        push(Compiler.ParamType.OMMITED, null);
                        nextMPType();
                        continue;
                    }
                    if(token.code == 41) { // ')'
                        break;
                    }
                }
                var mptype = nextMPType();
                if(mptype == MPType.ARRAYVAR) {
                    if((token.type == Token.Type.VAR || token.type == Token.Type.STRUCT) &&
                       this.isOnlyVar(this.tokensPos, this.tokensPos)) {
                        push(Compiler.ParamType.VARIABLE, this.getVariableData(sequence));
                    } else {
                        this.compileParameter(sequence, false);
                        push(Compiler.ParamType.VALUE, null);
                    }
                    continue;
                }
                var notReceiveVar = mptype != MPType.SINGLEVAR && mptype != MPType.MODULEVAR;
                var usedPushVar = this.compileParameter(sequence, notReceiveVar);
                var literal = null;
                var insn = sequence[sequence.length - 1];
                if(insn.code == Instruction.Code.PUSH) {
                    literal = insn.opts[0];
                    -- sequence.length;
                }
                push(usedPushVar ? Compiler.ParamType.VARIABLE : Compiler.ParamType.VALUE, literal);
            }
            if(isCType) this.compileRightParen(sequence);
            return [paramTypes, paramVals];
        }
        private getUserDefFunc(finfoId) {
            var func = this.userDefFuncs[finfoId];
            if(func) return func;
            var funcInfo = this.ax.funcsInfo[finfoId];
            if(funcInfo.index == -3) { // STRUCTDAT_INDEX_STRUCT
                var destructor = funcInfo.otindex != 0 ? this.getUserDefFunc(funcInfo.otindex) : null;
                var constructorFinfoId = this.ax.prmsInfo[funcInfo.prmindex].offset;
                var constructor = constructorFinfoId != -1 ? this.getUserDefFunc(constructorFinfoId) : null;
                return this.userDefFuncs[finfoId] = new Module(funcInfo.name, constructor, destructor, funcInfo.prmmax - 1, finfoId);
            }
            var isCType = funcInfo.index == -2; // STRUCTDAT_INDEX_CFUNC
            var paramTypes = [];
            for(var i = 0; i < funcInfo.prmmax; i ++) {
                paramTypes[i] = this.ax.prmsInfo[funcInfo.prmindex + i].mptype;
            }
            return this.userDefFuncs[finfoId] = new UserDefFunc(isCType, funcInfo.name, this.labels[funcInfo.otindex], paramTypes, finfoId);
        }
        private compileFuncall(sequence) {
            var token = this.ax.tokens[this.tokensPos++];
            var argc = this.compileParenAndParameters(sequence);
            this.pushNewInsn(sequence, Instruction.Code.CALL_BUILTIN_FUNC,
                             [token.type, token.code, argc], token);
        }
        private compileParenAndParameters(sequence) {
            this.compileLeftParen(sequence);
            var argc = this.compileParameters(sequence);
            this.compileRightParen(sequence);
            return argc;
        }
        private compileLeftParen(sequence) {
            var parenToken = this.ax.tokens[this.tokensPos++];
            if(!(parenToken && parenToken.type == Token.Type.MARK && parenToken.code == 40)) {
                throw this.error('関数名の後ろに開き括弧がありません。', parenToken);
            }
        }
        private compileRightParen(sequence) {
            var parenToken = this.ax.tokens[this.tokensPos++];
            if(!(parenToken && parenToken.type == Token.Type.MARK && parenToken.code == 41)) {
                throw this.error('関数パラメータの後ろに閉じ括弧がありません。', parenToken);
            }
        }
        private compileVariable(sequence) {
            switch(this.ax.tokens[this.tokensPos].type) {
            case Token.Type.VAR:
                this.compileStaticVariable(sequence);
                return;
            case Token.Type.STRUCT:
                if(this.compileProxyVariable(sequence) != null) return;
            }
            throw this.error('変数が指定されていません');
        }
        private compileStaticVariable(sequence, useGetVar) {
            var token = this.ax.tokens[this.tokensPos++];
            var argc = this.compileVariableSubscript(sequence);
            this.pushNewInsn(sequence, useGetVar ? Instruction.Code.GET_VAR : Instruction.Code.PUSH_VAR,
                             [token.code, argc], token);
        }
        private compileProxyVariable(sequence, useGetVar) {
            var proxyVarType = this.getProxyVarType();
            var token = this.ax.tokens[this.tokensPos++];
            var prmInfo = this.ax.prmsInfo[token.code];
            var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(token.code)];
            switch(proxyVarType) {
            case Compiler.ProxyVarType.THISMOD:
                this.pushNewInsn(sequence, Instruction.Code.THISMOD, [], token);
                return true;
            case Compiler.ProxyVarType.MEMBER:
                var argc = this.compileVariableSubscript(sequence);
                this.pushNewInsn(sequence, useGetVar ? Instruction.Code.GET_MEMBER : Instruction.Code.PUSH_MEMBER,
                                 [token.code - funcInfo.prmindex - 1, argc], token);
                return useGetVar;
            case Compiler.ProxyVarType.ARG_VAR:
                this.pushNewInsn(sequence, Instruction.Code.GETARG,
                                 [token.code - funcInfo.prmindex], token);
                return true;
            case Compiler.ProxyVarType.ARG_ARRAY:
            case Compiler.ProxyVarType.ARG_LOCAL:
                var argc = this.compileVariableSubscript(sequence);
                this.pushNewInsn(sequence, useGetVar ? Instruction.Code.GET_ARG_VAR : Instruction.Code.PUSH_ARG_VAR,
                                 [token.code - funcInfo.prmindex, argc], token);
                return useGetVar;
            default:
                return null;
            }
        }
        private getVariableData(sequence) {
            var token = this.ax.tokens[this.tokensPos];
            var result = this.getVariableData0();
            this.tokensPos ++;
            var argc = this.compileVariableSubscript(sequence);
            if(argc) {
                this.pushNewInsn(sequence, Instruction.Code.POP_N, [argc], token);
            }
            return result;
        }
        private getVariableDataNoSubscript() {
            var result = this.getVariableData0();
            if(this.isLeftParenToken(this.ax.tokens[++this.tokensPos])) {
                throw this.error('変数の添字は指定できません');
            }
            return result;
        }
        private getVariableData0() {
            var token = this.ax.tokens[this.tokensPos];
            var result;
            if(token.type == Token.Type.VAR) {
                return [Compiler.ProxyVarType.STATIC, token.code];
            } else if(token.type == Token.Type.STRUCT) {
                var type = this.getProxyVarType();
                var funcInfo = this.ax.funcsInfo[this.getFinfoIdByMinfoId(token.code)];
                if(type == Compiler.ProxyVarType.MEMBER) {
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
                return Compiler.ProxyVarType.THISMOD;
            }
            var prmInfo = this.ax.prmsInfo[token.code];
            if(prmInfo.subid >= 0) {
                return Compiler.ProxyVarType.MEMBER;
            }
            switch(prmInfo.mptype) {
            case MPType.LOCALVAR:
                return Compiler.ProxyVarType.ARG_LOCAL;
            case MPType.ARRAYVAR:
                return Compiler.ProxyVarType.ARG_ARRAY;
            case MPType.SINGLEVAR:
                if(this.isLeftParenToken(this.ax.tokens[this.tokensPos + 1])) {
                    throw this.error('パラメータタイプ var の変数に添字を指定しています');
                }
                return Compiler.ProxyVarType.ARG_VAR;
            default:
                return null;
            }
        }
        private isLeftParenToken(token) {
            return token && token.type == Token.Type.MARK && token.code == 40;
        }
        private isRightParenToken(token) {
            return token && token.type == Token.Type.MARK && token.code == 41;
        }
        private compileVariableSubscript(sequence) {
            var argc = 0;
            var parenToken = this.ax.tokens[this.tokensPos];
            if(parenToken && parenToken.type == Token.Type.MARK && parenToken.code == 40) {
                this.tokensPos ++;
                argc = this.compileParameters(sequence, true, true);
                if(argc == 0) {
                    throw this.error('配列変数の添字が空です', parenToken);
                }
                parenToken = this.ax.tokens[this.tokensPos++];
                if(!(parenToken && parenToken.type == Token.Type.MARK && parenToken.code == 41)) {
                    throw this.error('配列変数の添字の後ろに閉じ括弧がありません。', parenToken);
                }
            }
            return argc;
        }
    }

    class CompileError {
        constructor(public message: string, public hspFileName: string, public hspLineNumber: number) {
        }
    }
}
