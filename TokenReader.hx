import AXData;

class TokenReader {
	public static function main() {
		var path, binary: String;
		untyped {
			path = process.argv[2];
			if (path == null) path = "t.ax";
			binary = require("fs").readFileSync(path).toString("binary");
		}
		var axdata = new AXData(binary);
		var reader = new TokenReader(axdata.tokens);
		while (!reader.isEOS()) {
			trace('${reader.getToken()}');
		}
	}

	var cs: Array<Token>;
	var reader: TokenReaderWithoutLookingAhead;
	var lookahead: Array<Token> = [];
	public var last(default,null): Token;

	public function new(cs: Array<Token>) {
		this.cs = cs;
		this.reader = new TokenReaderWithoutLookingAhead(cs);
	}

	public function getToken() {
		var token = if (this.lookahead.length > 0) {
			this.lookahead.shift();
		} else {
			this.reader.getToken();
		}
		this.last = token;
		return token;
	}

	public function origPos() {
		return peekToken().pos;
	}

	public function peekToken(i = 0) {
		while (!this.reader.isEOS() && i >= this.lookahead.length) {
			this.push();
		}
		if (i < this.lookahead.length) {
			return this.lookahead[i];
		} else {
			return TokenReaderUtils.makeEOS(this.cs.length);
		}
	}

	public function isEOS() {
		return this.lookahead.length == 0 && this.reader.isEOS();
	}

	function push() {
		if (!this.reader.isEOS()) {
			this.lookahead.push(this.reader.getToken());
		}
	}

	public function save() { return copy(); }
	public function rewind(saved) { replace(saved); }

	function copy() {
		var clone = new TokenReader(this.cs);
		clone.replace(this);
		return clone;
	}

	function replace(from: TokenReader) {
		this.cs = from.cs;
		this.reader = from.reader.copy();
		this.lookahead = from.lookahead.copy();
		this.last = from.last;
	}
}

class TokenReaderWithoutLookingAhead {
	var cs: Array<Token>;
	var csOffset = 0;
	var feededStmtHead = false;
	var feededComma = false;

	public function new(cs) {
		this.cs = cs;
	}

	public function isEOS() {
		return this.csOffset >= this.cs.length;
	}

	public function getToken() {
		if (isEOS()) {
			return TokenReaderUtils.makeEOS(this.cs.length);
		}
		var token = this.cs[this.csOffset];
		if (token.ex1 && !this.feededStmtHead) {
			this.feededStmtHead = true;
			return TokenReaderUtils.makeStmtHead(token);
		}
		if (token.ex2 && !this.feededComma) {
			this.feededComma = true;
			return TokenReaderUtils.makeComma(token);
		}
		this.feededStmtHead = false;
		this.feededComma = false;
		this.csOffset += 1;
		// パラメータ省略時の'?'はカンマをトークンとして送ることで不要になるので省く
		if (token.ex2 && token.type == TokenType.MARK && token.code == 63) {
			return getToken();
		}
		return token;
	}

	public function copy() {
		var clone = new TokenReaderWithoutLookingAhead(this.cs);
		clone.replace(this);
		return clone;
	}

	public function replace(from: TokenReaderWithoutLookingAhead) {
		this.cs = from.cs;
		this.csOffset = from.csOffset;
		this.feededStmtHead = from.feededStmtHead;
		this.feededComma = from.feededComma;
	}
}

class TokenReaderUtils {
	public static function makeEOS(pos) {
		return new Token(-1, false, false, 0, null, 0, pos, 0, 0, null, null);
	}

	public static function makeStmtHead(token) {
		return new Token(-1, false, false, 1, token.fileName, token.lineNumber, token.pos, 0, 0, null, null);

	}
	public static function makeComma(token) {
		return new Token(-1, false, false, 2, token.fileName, token.lineNumber, token.pos, 0, 0, null, null);

	}
	public static function isStmtHead(token) {
		return token.type == -1 && token.code <= 1;
	}

	public static function isComma(token) {
		return token.type == -1 && token.code == 2;
	}
}
