///<reference path="node.d.ts"/>
///<reference path="axdata.ts"/>

// how to run:  tsc app.ts --out app.js && node app.js

var fs = require("fs");
var binary = fs.readFileSync("sample_01_start.ax").toString("binary");
var axdata = new BitterHSP.AXData(binary);
console.log(axdata.tokens);
