///<reference path="node.d.ts"/>
///<reference path="axdata.ts"/>
///<reference path="compiler.ts"/>

// how to run:  tsc app.ts --out app.js && node app.js

var fs = require("fs");
var binary = fs.readFileSync("hsp-programs/hello/hello.ax").toString("binary");
var axdata = new BitterHSP.AXData(binary);
console.log(new BitterHSP.Compiler(axdata).compile());
