#!/usr/bin/env node
/* 出题模块的命令行入口：不依赖电视、不依赖浏览器，用来预览/校验题目。

   用法：
     node quiz/cli.js                       # 5 年级，一轮 3 题
     node quiz/cli.js --grade 6 --n 4
     node quiz/cli.js --subject 数学 --rounds 5
     node quiz/cli.js --json                # 输出 JSON，方便喂给别的程序
*/
'use strict';

const fs = require('fs');
const path = require('path');

const GEN = require('./gen.js');
const PICK = require('./pick.js');

const KEYS = ['A', 'B', 'C', 'D'];

function parseArgs(argv) {
  const out = { grade: 5, n: 3, rounds: 1, subject: '', json: false, bank: true };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--grade' || a === '-g') out.grade = parseInt(next(), 10);
    else if (a === '--n') out.n = parseInt(next(), 10);
    else if (a === '--rounds' || a === '-r') out.rounds = parseInt(next(), 10);
    else if (a === '--subject' || a === '-s') out.subject = next();
    else if (a === '--json') out.json = true;
    else if (a === '--no-bank') out.bank = false;
    else if (a === '--help' || a === '-h') { out.help = true; }
    else { console.error('未知参数: ' + a); out.help = true; }
  }
  if (![5, 6].includes(out.grade)) out.grade = 5;
  out.n = Math.min(6, Math.max(1, out.n || 3));
  out.rounds = Math.max(1, out.rounds || 1);
  return out;
}

function loadBank() {
  try {
    const raw = JSON.parse(fs.readFileSync(path.join(__dirname, 'bank.json'), 'utf8'));
    return raw.questions || [];
  } catch (e) {
    return [];
  }
}

function poolFor(opts) {
  const pool = GEN.make(opts.grade);
  if (opts.bank) {
    const cn = loadBank().filter(q => q.grade === opts.grade);
    return pool.concat(cn);
  }
  return pool;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0].replace('/* ', ''));
    process.exit(0);
  }

  let pool = poolFor(opts);
  const subjects = opts.subject ? [opts.subject] : undefined;
  /* --subject 只出单科，否则 buildRound 会用其它科目补满 */
  if (opts.subject) pool = pool.filter(q => q.subject === opts.subject);
  const rounds = [];

  for (let r = 0; r < opts.rounds; r++) {
    const round = PICK.buildRound({ pool, want: opts.n, subjects, recent: [] });
    if (!round.length) {
      console.error('题池为空：grade=' + opts.grade + ' subject=' + (opts.subject || '全部'));
      process.exit(1);
    }
    rounds.push(round);
  }

  if (opts.json) {
    console.log(JSON.stringify(opts.rounds === 1 ? rounds[0] : rounds, null, 1));
    return;
  }

  rounds.forEach((round, ri) => {
    if (rounds.length > 1) console.log('=== 第 ' + (ri + 1) + ' 轮 ===');
    round.forEach((q, i) => {
      console.log((i + 1) + '. [' + q.subject + '] ' + q.q);
      q.o.forEach((o, j) => {
        console.log('   ' + (j === q.a ? '*' : ' ') + ' ' + KEYS[j] + '. ' + o);
      });
      if (q.why) console.log('   解析：' + q.why);
    });
    console.log('');
  });

  const cnt = {};
  rounds.forEach(r => r.forEach(q => { cnt[q.subject] = (cnt[q.subject] || 0) + 1; }));
  console.log('题池 ' + pool.length + ' 题 | 本轮 ' + rounds.length + ' 组 | 科目分布 ' +
    Object.keys(cnt).map(k => k + ':' + cnt[k]).join(' '));
}

main();
