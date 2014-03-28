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

	var reader: TokenReaderWithoutLookingAhead;
	var lookahead: Array<Token> = [];

	public function new(cs: Array<Token>) {
		this.reader = new TokenReaderWithoutLookingAhead(cs);
	}

	public function getToken() {
		if (this.lookahead.length > 0) {
			return this.lookahead.shift();
		} else {
			return this.reader.getToken();
		}
	}

	public function peekToken(i = 0) {
		while (!this.reader.isEOS() && i >= this.lookahead.length) {
			this.push();
		}
		return this.lookahead[i];
	}

	public function isEOS() {
		return this.lookahead.length == 0 && this.reader.isEOS();
	}

	function push() {
		if (!this.reader.isEOS()) {
			this.lookahead.push(this.reader.getToken());
		}
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
		if (isEOS()) return null;
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
		return token;
	}
}

class TokenReaderUtils {
	public static function makeStmtHead(token) {
		return new Token(TokenType.MARK, false, false, 256, token.fileName, token.lineNumber, token.pos, 0, 0, null, null);

	}

	public static function makeComma(token) {
		return new Token(TokenType.MARK, false, false, 257, token.fileName, token.lineNumber, token.pos, 0, 0, null, null);

	}

	public static function isStmtHead(token) {
		return token.type == TokenType.MARK && token.code == 256;
	}

	public static function isComma(token) {
		return token.type == TokenType.MARK && token.code == 257;
	}
}
