/* Sample the comparative/superlative items: node adj_sample.js */
'use strict';
const fs = require('fs');
const vm = require('vm');
const sandbox = { window: {}, Math: Math };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(__dirname + '/gen.js', 'utf8'), sandbox);
const G = sandbox.window.TVGEN;

const seen = {}, out = [];
for (let i = 0; i < 30000; i++) {
  const q = G.englishFor(5);
  if (!q || !/比较级|最高级/.test(q.q)) continue;
  const base = (q.q.match(/“(.+?)”/) || q.q.match(/（(.+?)）/)) [1];
  seen[base] = (seen[base] || 0) + 1;
  if (out.filter(x => x.base === base).length < 2) out.push({ base, q });
}
out.slice(0, 20).forEach(({ q }) => {
  console.log(q.q.padEnd(44) + ' ' + q.o.map((o, j) => (j === q.a ? '[' + o + ']' : o)).join(' | '));
});
console.log('\nbases covered:', Object.keys(seen).length, Object.keys(seen).sort().join(' '));
