import js.Node;
import sys.io.File;
import Compiler;


class T {
	static function main(){
		Node.global.BitterHSP = Node.require("./compiler");
		var path = Sys.args()[2];
		if (path == null) path = "hsp-programs/hello/hello.ax";
		var binary = Node.fs.readFileSync(path).toString("binary");
		var sequence = Compiler.compile(binary);
		trace(Std.string(sequence));
	}
}
