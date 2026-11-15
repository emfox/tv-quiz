/* Local self-test for gen.js: run with node check.js */
'use strict';
const fs = require('fs');
const vm = require('vm');

const sandbox = { window: {}, Math: Math };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(__dirname + '/gen.js', 'utf8'), sandbox);
const GEN = sandbox.window.TVGEN;

let bad = 0, total = 0;
const texts = {}, poolSizes = [];

function check(q, tag) {
  total++;
  if (!q.q || !q.o || q.o.length !== 4) { bad++; console.log('BAD shape', tag, JSON.stringify(q)); return; }
  if (q.a < 0 || q.a > 3) { bad++; console.log('BAD index', tag, q.q); return; }
  if (new Set(q.o).size !== 4) { bad++; console.log('DUP opts', tag, q.q, q.o); return; }
  const s = q.o.join(' ');
  if (/NaN|undefined|Infinity|e\+|e-/.test(s + q.q)) { bad++; console.log('BAD token', tag, q.q, q.o); return; }
  if (!q.why) { bad++; console.log('NO why', tag, q.q); }
  const key = q.subject + '|' + q.q;
  texts[key] = (texts[key] || 0) + 1;
}

for (const g of [5, 6]) {
  for (let i = 0; i < 1500; i++) {
    const pool = GEN.make(g);
    poolSizes.push(pool.length);
    pool.forEach(q => check(q, 'g' + g));
  }
}

poolSizes.sort((a, b) => a - b);
console.log('pool size min/median/max:', poolSizes[0], poolSizes[poolSizes.length >> 1], poolSizes[poolSizes.length - 1]);
console.log('items checked:', total, 'bad:', bad);

const dup = Object.keys(texts).filter(k => texts[k] > 1);
console.log('distinct question texts:', Object.keys(texts).length, '| repeated texts:', dup.length,
  '| worst repeat:', Math.max.apply(null, Object.keys(texts).map(k => texts[k])));

console.log('\n--- grade 5 math samples (correct marked with *) ---');
for (let i = 0; i < 26; i++) {
  const q = GEN.mathFor(5);
  if (!q) { i--; continue; }
  console.log(q.q, '=>', q.o.map((o, j) => j === q.a ? '*' + o : o).join(' | '));
}
console.log('\n--- grade 6 math samples ---');
for (let i = 0; i < 26; i++) {
  const q = GEN.mathFor(6);
  if (!q) { i--; continue; }
  console.log(q.q, '=>', q.o.map((o, j) => j === q.a ? '*' + o : o).join(' | '));
}
console.log('\n--- english samples ---');
for (let i = 0; i < 12; i++) {
  const q = GEN.englishFor(i % 2 ? 5 : 6);
  console.log('[' + q.grade + ']', q.q, '=>', q.o.map((o, j) => j === q.a ? '*' + o : o).join(' | '));
}
