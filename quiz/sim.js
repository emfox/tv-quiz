/* Headless simulation of index.html: fake DOM + real script, plays 200 rounds
   (including mid-round page reloads) to check pool variety and persistence. */
'use strict';
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const dir = __dirname;
const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
if (scripts.length !== 1) throw new Error('expected one inline script, got ' + scripts.length);
const anchor = 'var all = [], plan = [], idx = 0, locked = false;';
if (scripts[0].indexOf(anchor) < 0) throw new Error('anchor not found');
const mainJs = scripts[0].replace(anchor,
  anchor + '\n  window.__dbg = function () { return { plan: plan, idx: idx }; };');
const genJs = fs.readFileSync(path.join(dir, 'gen.js'), 'utf8');
const pickJs = fs.readFileSync(path.join(dir, 'pick.js'), 'utf8');
const bank = JSON.parse(fs.readFileSync(path.join(dir, 'bank.json'), 'utf8'));

function El(tag) {
  this.tagName = tag;
  this.className = '';
  this.textContent = '';
  this.style = {};
  this.children = [];
  this._html = '';
  this._spans = {};
  this._listeners = {};
  const self = this;
  this.classList = {
    add(c) { if (self.className.split(' ').indexOf(c) < 0) self.className = (self.className + ' ' + c).trim(); },
    has(c) { return self.className.split(' ').indexOf(c) >= 0; }
  };
}
El.prototype.appendChild = function (c) { this.children.push(c); return c; };
El.prototype.querySelector = function (sel) {
  if (sel === '.opt') return this.children[0] || null;
  if (sel === '.t' || sel === '.k') return this._spans[sel] || (this._spans[sel] = new El('span'));
  return null;
};
El.prototype.querySelectorAll = function (sel) {
  return (sel === '#opts .opt' || sel === '.opt') ? this.children : [];
};
El.prototype.addEventListener = function (t, fn) { this._listeners[t] = fn; };
El.prototype.setAttribute = function (k, v) { this['@' + k] = v; };
El.prototype.focus = function () {};
El.prototype.click = function () { if (this._listeners.click) this._listeners.click({ preventDefault() {} }); };
Object.defineProperty(El.prototype, 'innerHTML', {
  get() { return this._html; },
  set(v) { this._html = v; if (v === '') this.children = []; }
});

const store = {};
const localStorageStub = {
  getItem: k => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: k => { delete store[k]; }
};

const stats = { pass: 0, pages: 0 };

function newPage(query) {
  stats.pages++;
  const els = {};
  ['subj', 'prog', 'q', 'opts', 'tip', 'done', 'doneMsg', 'dbg'].forEach(id => { els[id] = new El('div'); });
  els.done.style.display = 'none';
  const timers = [];
  const document = {
    getElementById: id => els[id],
    createElement: tag => new El(tag),
    querySelectorAll: sel => (sel === '#opts .opt' ? els.opts.children : [])
  };
  const sandbox = {
    console, Math, JSON, String, Number, Array, Object, Error, parseInt, parseFloat, isFinite,
    document,
    location: { search: query || '?g=5' },
    localStorage: localStorageStub,
    URLSearchParams,
    setTimeout: (fn, ms) => { timers.push({ fn, ms: ms || 0 }); return timers.length; },
    fetch: url => {
      if (url.indexOf('pass.sh') >= 0) { stats.pass++; return Promise.resolve({}); }
      return Promise.resolve({ json: () => Promise.resolve(bank) });
    }
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(genJs, sandbox);
  vm.runInContext(pickJs, sandbox);
  vm.runInContext(mainJs, sandbox);
  return { sandbox, els, timers };
}

function flush(pg) {
  let guard = 0;
  while (pg.timers.length) {
    if (++guard > 500) throw new Error('timer loop');
    pg.timers.sort((a, b) => a.ms - b.ms);
    pg.timers.shift().fn();
  }
}
const tick = () => new Promise(r => setImmediate(r));

function assert(cond, msg) { if (!cond) { problems.push(msg); } }
const problems = [];
const bySub = {};
const seenText = {};
const roundSizes = {};

(async () => {
  let questions = 0, resumeChecks = 0, resumeOk = 0;

  for (let r = 0; r < 200; r++) {
    const grade = r % 2 ? 6 : 5;
    let pg = newPage('?g=' + grade);
    await tick();
    flush(pg);

    let d = pg.sandbox.window.__dbg();
    assert(d.plan.length === 3, 'plan size ' + d.plan.length);
    roundSizes[d.plan.length] = (roundSizes[d.plan.length] || 0) + 1;
    const subs = new Set(d.plan.map(x => x.subject));
    assert(subs.size === 3, 'subjects ' + [...subs].join(','));
    d.plan.forEach(x => {
      assert(x.grade === grade, 'grade mismatch');
      assert(x.o.length === 4 && new Set(x.o).size === 4, 'opts bad: ' + x.q);
      assert(typeof x.a === 'number' && x.a >= 0 && x.a < 4, 'index bad');
      assert(!/NaN|undefined|Infinity/.test(x.q + x.o.join('')), 'token bad: ' + x.q);
    });

    /* answer question 1, then reload mid-round to test resume */
    let st = pg.sandbox.window.__dbg();
    let q = st.plan[st.idx];
    flush(pg);
    pg.els.opts.children[q.a].click();
    questions++;
    seenText[q.q] = (seenText[q.q] || 0) + 1;
    bySub[q.subject] = bySub[q.subject] || {};
    bySub[q.subject][q.q] = (bySub[q.subject][q.q] || 0) + 1;
    flush(pg);

    if (r % 3 === 0) {
      const before = pg.sandbox.window.__dbg();
      pg = newPage('?g=' + grade);
      await tick();
      flush(pg);
      const after = pg.sandbox.window.__dbg();
      resumeChecks++;
      if (after.idx === before.idx && after.plan[0].q === before.plan[0].q) resumeOk++;
      else assert(false, 'resume failed: ' + before.idx + ' -> ' + after.idx);
    }

    /* finish the round */
    for (;;) {
      const s2 = pg.sandbox.window.__dbg();
      if (!s2.plan[s2.idx]) break;
      const qq = s2.plan[s2.idx];
      flush(pg);
      pg.els.opts.children[qq.a].click();
      questions++;
      seenText[qq.q] = (seenText[qq.q] || 0) + 1;
      bySub[qq.subject] = bySub[qq.subject] || {};
      bySub[qq.subject][qq.q] = (bySub[qq.subject][qq.q] || 0) + 1;
      flush(pg);
    }
    assert(pg.els.done.style.display === 'flex', 'finish not reached');
    assert(store.tvquiz_state === undefined, 'state not cleared');
  }

  const distinct = Object.keys(seenText).length;
  const repeated = Object.keys(seenText).filter(k => seenText[k] > 1).length;
  console.log('pages:', stats.pages, 'rounds: 200', 'questions:', questions);
  console.log('round sizes:', JSON.stringify(roundSizes));
  console.log('resume ok:', resumeOk + '/' + resumeChecks);
  console.log('pass.sh calls:', stats.pass);
  console.log('distinct texts:', distinct, '| repeated texts:', repeated);
  Object.keys(bySub).forEach(function (s) {
    var ks = Object.keys(bySub[s]), rep = ks.filter(function (k) { return bySub[s][k] > 1; });
    console.log('  ' + s + ': asked ' + ks.reduce(function (a, k) { return a + bySub[s][k]; }, 0) +
      ' | distinct ' + ks.length + ' | repeated ' + rep.length);
  });
  console.log('problems:', problems.length);
  problems.slice(0, 10).forEach(p => console.log(' -', p));
})();
