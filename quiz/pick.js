/* Round builder: picks one question per subject from a pool, avoiding recently
   asked ones. Pure function, no DOM -- used by the page and the CLI alike.

   pool: [{subject:'数学'|'语文'|'英语', q, o, a, why, grade}, ...]
   want: how many questions in this round (default 3)
   recent: array of question texts that should be avoided if possible
   subjects: subjects to cover first (default 数学/语文/英语) */
(function (root) {
  'use strict';

  var SUBJECTS = ['数学', '语文', '英语'];

  function shuffle(a) {
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  function buildRound(opts) {
    opts = opts || {};
    var pool = opts.pool || [];
    var want = opts.want || 3;
    var rec = opts.recent || [];
    var subs = opts.subjects || SUBJECTS;
    var picked = [], used = {};

    subs.forEach(function (s) {
      var cand = pool.filter(function (q) { return q.subject === s && !used[q.q]; });
      var fresh = cand.filter(function (q) { return rec.indexOf(q.q) < 0; });
      if (fresh.length) cand = fresh;
      shuffle(cand);
      if (cand.length) { picked.push(cand[0]); used[cand[0].q] = 1; }
    });

    var rest = shuffle(pool.filter(function (q) { return !used[q.q]; }));
    for (var i = 0; i < rest.length && picked.length < want; i++) picked.push(rest[i]);
    return shuffle(picked).slice(0, want);
  }

  var api = { buildRound: buildRound, shuffle: shuffle, SUBJECTS: SUBJECTS };
  root.TVQUIZ = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window
  : (typeof globalThis !== 'undefined' ? globalThis : this));
