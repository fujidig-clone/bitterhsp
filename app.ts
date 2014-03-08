///<reference path="node.d.ts"/>
///<reference path="axdata.ts"/>
///<reference path="compiler.ts"/>

// how to run:  tsc app.ts --out app.js && node app.js

var fs = require("fs");
var binary = fs.readFileSync(process.argv[2] || "hsp-programs/hello/hello.ax").toString("binary");
var axdata = new BitterHSP.AXData(binary);
var sequence = new BitterHSP.Compiler(axdata).compile();

sequence.forEach((insn) => {
    console.log(BitterHSP.InsnCode[insn.code], insn.opts);
});
