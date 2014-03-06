///<reference path="node.d.ts"/>
///<reference path="axdata.ts"/>

// how to run:  tsc app.ts --out app.js && node app.js

var fs = require("fs");
var binary = fs.readFileSync("hsp-programs/d3m_techdemo/d3m_techdemo.ax").toString("binary");
var axdata = new BitterHSP.AXData(binary);
//console.log(axdata.variableNames);
console.log(axdata.labelNames);
