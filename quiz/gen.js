/* Runtime question generators for the TV quiz gate (ES5, Chrome 66 safe).
   Math and English are generated per round so numbers/words never freeze. */
(function (root) {
  'use strict';

  var seq = 0;

  function ri(a, b) { return a + Math.floor(Math.random() * (b - a + 1)); }
  function pick(a) { return a[ri(0, a.length - 1)]; }
  function r2(x) { return Math.round(x * 100) / 100; }
  function fnum(x) { return String(Math.round(x * 1e6) / 1e6); }

  function gcd(a, b) {
    a = Math.abs(a); b = Math.abs(b);
    while (b) { var t = a % b; a = b; b = t; }
    return a || 1;
  }
  function frac(n, d) {
    if (d < 0) { n = -n; d = -d; }
    var g = gcd(n, d);
    n = n / g; d = d / g;
    return d === 1 ? String(n) : n + '/' + d;
  }
  function shuffle(a) {
    for (var i = a.length - 1; i > 0; i--) {
      var j = ri(0, i), t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  function mk(subject, grade, q, correct, wrongs, why) {
    var opts = [], i, v;
    correct = String(correct);
    if (!correct || correct === 'NaN' || correct.indexOf('Infinity') >= 0) return null;
    opts.push(correct);
    for (i = 0; i < wrongs.length && opts.length < 4; i++) {
      v = String(wrongs[i]);
      if (v !== correct && v !== 'NaN' && opts.indexOf(v) < 0) opts.push(v);
    }
    if (opts.length < 4 && /^-?\d+(\.\d+)?$/.test(correct)) {
      var base = parseFloat(correct), d = Math.abs(base) > 4 ? 1 : 0.5;
      var cand = [base * 2, base / 2, base + d, base - d, base + 2 * d, base - 2 * d,
                  base + 10, base / 10];
      for (i = 0; i < cand.length && opts.length < 4; i++) {
        var c = cand[i];
        if (!isFinite(c) || c <= 0) continue;
        v = fnum(r2(c));
        if (v !== correct && opts.indexOf(v) < 0) opts.push(v);
      }
    }
    if (opts.length < 4) return null;
    shuffle(opts);
    var a = opts.indexOf(correct);
    if (a < 0) return null;
    return {
      id: 'g' + (++seq) + '-' + ri(1000, 9999),
      grade: grade, subject: subject, q: q, o: opts, a: a, why: why || ''
    };
  }

  /* ---------------- grade 5 math ---------------- */

  var T5 = [
    function () {
      var a = ri(15, 95) / 10, b = ri(105, 985) / 100;
      if (b * 100 % 10 === 0) b = r2(b + 0.01);
      return mk('数学', 5, fnum(a) + ' + ' + fnum(b) + ' = ？', fnum(r2(a + b)),
        [fnum(r2(a + b + 0.1)), fnum(r2(a + b - 1)), fnum(r2(a * b))],
        '小数点对齐，再按整数加法计算。');
    },
    function () {
      var a = ri(50, 99) / 10, b = ri(105, 480) / 100;
      if (b * 100 % 10 === 0) b = r2(b + 0.01);
      return mk('数学', 5, fnum(a) + ' - ' + fnum(b) + ' = ？', fnum(r2(a - b)),
        [fnum(r2(a - b + 0.1)), fnum(r2(a + b)), fnum(r2(a - b - 1))],
        '小数点对齐，不够减时向前一位借一当十。');
    },
    function () {
      var a = ri(11, 89) / 10, n = ri(2, 9);
      if (a * 10 % 10 === 0) a = r2(a + 0.1);
      return mk('数学', 5, fnum(a) + ' × ' + n + ' = ？', fnum(r2(a * n)),
        [fnum(r2(a * n / 10)), fnum(r2(a * n * 10)), fnum(r2(a * n + 0.1 * n))],
        '先按整数相乘，再看因数中一共有几位小数。');
    },
    function () {
      var n = ri(2, 9), qv = ri(11, 89) / 10, a;
      if (qv * 10 % 10 === 0) qv = r2(qv + 0.1);
      a = r2(qv * n);
      return mk('数学', 5, fnum(a) + ' ÷ ' + n + ' = ？', fnum(qv),
        [fnum(r2(qv / 10)), fnum(r2(qv * 10)), fnum(r2(qv + 1))],
        '除数是整数时，按整数除法算，商的小数点与被除数对齐。');
    },
    function () {
      var d1 = pick([2, 3, 4, 5, 6, 8, 10, 12]), d2 = pick([2, 3, 4, 5, 6, 8, 10, 12]);
      var n1 = ri(1, d1 - 1), n2 = ri(1, d2 - 1);
      return mk('数学', 5, frac(n1, d1) + ' + ' + frac(n2, d2) + ' = ？（结果写成分数）',
        frac(n1 * d2 + n2 * d1, d1 * d2),
        [frac(n1 * n2, d1 * d2), frac(n1 + n2, d1 + d2), frac(Math.abs(n1 * d2 - n2 * d1), d1 * d2)],
        '先通分，把分子相加，最后能约分的要约分。');
    },
    function () {
      var d1 = pick([2, 3, 4, 5, 6, 8, 10, 12]), d2 = pick([2, 3, 4, 5, 6, 8, 10, 12]);
      var n1 = ri(1, d1 - 1), n2 = ri(1, d2 - 1);
      if (n1 * d2 < n2 * d1) { var t = n1; n1 = n2; n2 = t; t = d1; d1 = d2; d2 = t; }
      return mk('数学', 5, frac(n1, d1) + ' - ' + frac(n2, d2) + ' = ？（结果写成分数）',
        frac(n1 * d2 - n2 * d1, d1 * d2),
        [frac(n1 - n2, Math.abs(d1 - d2) || 1), frac(n1 * d2 + n2 * d1, d1 * d2), frac(n1 * n2, d1 * d2)],
        '先通分，把分子相减，结果要化成最简分数。');
    },
    function () {
      var n = pick([40, 60, 80, 120, 160, 200, 240, 300, 400, 500]);
      var p = pick([5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 80]);
      var v = r2(n * p / 100);
      return mk('数学', 5, n + ' 的 ' + p + '% 是多少？', fnum(v),
        [n * p, fnum(r2(n * p / 10)), fnum(r2(n - v))],
        p + '% = ' + frac(p, 100) + '，用 ' + n + ' 乘它。');
    },
    function () {
      var w = ri(4, 20), h = ri(3, 15);
      return mk('数学', 5, '一个长方形长 ' + w + ' 厘米、宽 ' + h + ' 厘米，面积是多少平方厘米？',
        w * h, [2 * (w + h), w + h, fnum(r2(w * h / 2))], '长方形面积 = 长 × 宽。');
    },
    function () {
      var b = 2 * ri(2, 9), h = ri(3, 15);
      return mk('数学', 5, '一个三角形底 ' + b + ' 厘米、高 ' + h + ' 厘米，面积是多少平方厘米？',
        b * h / 2, [b * h, b + h, fnum(r2(b * h / 4))], '三角形面积 = 底 × 高 ÷ 2。');
    },
    function () {
      var a = ri(2, 12), h = ri(2, 12);
      return mk('数学', 5, '一个平行四边形的底是 ' + a + ' 厘米、高是 ' + h + ' 厘米，面积是多少平方厘米？',
        a * h, [a * h * 2, fnum(r2(a * h / 2)), a + h], '平行四边形面积 = 底 × 高。');
    },
    function () {
      var a = ri(3, 12), b = ri(3, 12), h = 2 * ri(2, 7);
      return mk('数学', 5, '一个梯形上底 ' + a + ' 厘米、下底 ' + b + ' 厘米、高 ' + h + ' 厘米，面积是多少平方厘米？',
        (a + b) * h / 2, [(a + b) * h, a + b + h, (a + b) * h / 4], '梯形面积 = （上底 + 下底）× 高 ÷ 2。');
    },
    function () {
      var x = ri(2, 12), a = ri(2, 9), b = ri(1, 20);
      if (ri(0, 1)) {
        var c = a * x + b;
        return mk('数学', 5, '解方程：' + a + 'x + ' + b + ' = ' + c + '，x = ？', x,
          [fnum(r2((c + b) / a)), fnum(r2(c / a)), c - b],
          '先把 ' + b + ' 移到等号右边，再两边同时除以 ' + a + '。');
      }
      var c2 = a * x - b;
      if (c2 <= 0) return null;
      return mk('数学', 5, '解方程：' + a + 'x - ' + b + ' = ' + c2 + '，x = ？', x,
        [fnum(r2((c2 - b) / a)), fnum(r2(c2 / a)), c2 + b],
        '先把减去的 ' + b + ' 移到右边变加，再两边同时除以 ' + a + '。');
    },
    function () {
      var cnt = pick([3, 4, 5]), avg = ri(55, 95), nums = [], i, s = 0;
      for (i = 0; i < cnt - 1; i++) { var v = avg + ri(-9, 9); nums.push(v); s += v; }
      var last = avg * cnt - s;
      if (last < 20 || last > 130) return null;
      nums.push(last);
      shuffle(nums);
      return mk('数学', 5, '求 ' + nums.join('、') + ' 的平均数。', avg,
        [s + last + 1, Math.max.apply(null, nums) - Math.min.apply(null, nums), fnum(r2((s + last) / (cnt + 1)))],
        '平均数 = 总数 ÷ 个数。');
    },
    function () {
      var pair = pick([['米', '厘米', 100], ['千克', '克', 1000], ['时', '分', 60],
                       ['平方米', '平方分米', 100], ['千米', '米', 1000], ['吨', '千克', 1000],
                       ['升', '毫升', 1000]]);
      var v = ri(11, 95) / 10, k = pair[2];
      return mk('数学', 5, fnum(v) + ' ' + pair[0] + ' = ？' + pair[1], fnum(r2(v * k)),
        [fnum(r2(v * k / 10)), fnum(r2(v * k * 10)), fnum(v)],
        '1 ' + pair[0] + ' = ' + k + ' ' + pair[1] + '，高级单位化低级单位要乘 ' + k + '。');
    },
    function () {
      var a = ri(2, 10), b = ri(2, 10), h = ri(2, 10);
      return mk('数学', 5, '一个长方体长 ' + a + ' 厘米、宽 ' + b + ' 厘米、高 ' + h + ' 厘米，体积是多少立方厘米？',
        a * b * h, [a * b + h, 2 * (a * b + a * h + b * h), a + b + h], '长方体体积 = 长 × 宽 × 高。');
    },
    function () {
      var a = ri(4, 40), b = ri(4, 40), g = gcd(a, b);
      if (a === b) return null;
      if (ri(0, 1)) {
        return mk('数学', 5, a + ' 和 ' + b + ' 的最大公因数是？', g,
          [a * b, a * b / g, a + b], '把两个数分解质因数，取公有质因数的积。');
      }
      return mk('数学', 5, a + ' 和 ' + b + ' 的最小公倍数是？', a * b / g,
        [g, a + b, a * b], '最小公倍数 = 两数之积 ÷ 最大公因数。');
    },
    function () {
      var v1 = ri(50, 80), v2 = ri(40, 70), t = ri(2, 6);
      return mk('数学', 5, '甲车每小时行 ' + v1 + ' 千米，乙车每小时行 ' + v2 +
        ' 千米，两车同时从两地相对开出，' + t + ' 小时后相遇，两地相距多少千米？',
        (v1 + v2) * t, [(v1 - v2) * t > 0 ? (v1 - v2) * t : v1 + v2,
                        v1 + v2 + t, (v1 + v2) * t / 2],
        '相遇问题：总路程 = 两车速度和 × 相遇时间。');
    },
    function () {
      var a = pick([2, 3, 4, 5, 6, 7, 8, 9]);
      return mk('数学', 5, '简便计算：125 × 8 × ' + a + ' = ？', 1000 * a,
        [1000 + a, 125 * 8 + a, 1000 * a + 100], '先算 125 × 8 = 1000，再乘 ' + a + '。');
    },
    function () {
      var d = pick([2, 4, 5, 8, 10, 20, 25, 50]), n = ri(1, d - 1);
      return mk('数学', 5, frac(n, d) + ' 化成小数是？', fnum(r2(n / d)),
        [fnum(r2(n / d * 10)), fnum(r2(n / d / 10)), fnum(r2(d / n))],
        '用分子除以分母，能化成有限小数的分母只含质因数 2 和 5。');
    },
    function () {
      var a = ri(6, 20) * 2, b = ri(3, 9);
      return mk('数学', 5, '把 ' + a + ' 个苹果平均放进 ' + b + ' 个盘子，每个盘子放几个？',
        fnum(r2(a / b)), [a - b, a * b, fnum(r2(a / b + 1))],
        '平均分用除法：总数 ÷ 份数 = 每份数。');
    }
  ];

  /* ---------------- grade 6 math ---------------- */

  var T6 = [
    function () {
      var d1 = pick([2, 3, 4, 5, 6, 8]), d2 = pick([2, 3, 4, 5, 6, 8]);
      var n1 = ri(1, d1 - 1), n2 = ri(1, d2 - 1);
      return mk('数学', 6, frac(n1, d1) + ' × ' + frac(n2, d2) + ' = ？（结果写成分数）',
        frac(n1 * n2, d1 * d2),
        [frac(n1 + n2, d1 + d2), frac(n1 * d2 + n2 * d1, d1 * d2), frac(n1 * n2, d1 + d2)],
        '分子乘分子、分母乘分母，能约分先约分。');
    },
    function () {
      var d1 = pick([2, 3, 4, 5, 6, 8]), d2 = pick([2, 3, 4, 5, 6, 8]);
      var n1 = ri(1, d1 - 1), n2 = ri(1, d2 - 1);
      return mk('数学', 6, frac(n1, d1) + ' ÷ ' + frac(n2, d2) + ' = ？（结果写成分数）',
        frac(n1 * d2, d1 * n2),
        [frac(n1 * n2, d1 * d2), frac(n1 * d1, n2 * d2), frac(n1 + n2, d1 * d2)],
        '除以一个分数，等于乘它的倒数。');
    },
    function () {
      var r = ri(1, 12);
      return mk('数学', 6, '一个圆的半径是 ' + r + ' 厘米，它的周长是多少厘米？（π 取 3.14）',
        fnum(r2(2 * 3.14 * r)),
        [fnum(r2(3.14 * r * r)), fnum(r2(3.14 * r)), fnum(r2(6.28 * r * r))],
        '圆的周长 C = 2πr。');
    },
    function () {
      var r = ri(1, 12);
      return mk('数学', 6, '一个圆的半径是 ' + r + ' 厘米，它的面积是多少平方厘米？（π 取 3.14）',
        fnum(r2(3.14 * r * r)),
        [fnum(r2(6.28 * r)), fnum(r2(3.14 * r)), fnum(r2(3.14 * r * r * 2))],
        '圆的面积 S = πr²，注意是半径的平方。');
    },
    function () {
      var r = ri(1, 6), h = ri(2, 10);
      return mk('数学', 6, '一个圆柱底面半径 ' + r + ' 厘米、高 ' + h +
        ' 厘米，体积是多少立方厘米？（π 取 3.14）',
        fnum(r2(3.14 * r * r * h)),
        [fnum(r2(3.14 * r * h)), fnum(r2(2 * 3.14 * r * h)), fnum(r2(3.14 * r * r * h / 3))],
        '圆柱体积 V = πr²h。');
    },
    function () {
      var r = ri(2, 6), h = pick([3, 6, 9, 12, 15]);
      return mk('数学', 6, '一个圆锥底面半径 ' + r + ' 厘米、高 ' + h +
        ' 厘米，体积是多少立方厘米？（π 取 3.14）',
        fnum(r2(3.14 * r * r * h / 3)),
        [fnum(r2(3.14 * r * r * h)), fnum(r2(3.14 * r * h / 3)), fnum(r2(2 * 3.14 * r * h))],
        '圆锥体积 V = πr²h ÷ 3，是等底等高圆柱的三分之一。');
    },
    function () {
      var n = pick([80, 120, 150, 200, 240, 300, 400, 500]), zhe = ri(5, 9);
      return mk('数学', 6, '一件商品原价 ' + n + ' 元，打 ' + zhe + ' 折后是多少元？',
        fnum(r2(n * zhe / 10)),
        [fnum(r2(n * (10 - zhe) / 10)), n, fnum(r2(n * zhe / 100))],
        '打 ' + zhe + ' 折就是按原价的 ' + zhe * 10 + '% 出售。');
    },
    function () {
      var a = ri(2, 24), b = ri(2, 24), g = gcd(a, b);
      var p = a / g, q = b / g;
      if (p === a && q === b) return null;
      return mk('数学', 6, '把 ' + a + ' : ' + b + ' 化成最简整数比是？', p + ':' + q,
        [q + ':' + p, a + ':' + b, (p * 2) + ':' + (q * 3)],
        '比的前项和后项同时除以它们的最大公因数。');
    },
    function () {
      var a = ri(1, 20), b = ri(1, 20);
      if (a === b) return null;
      var hi = -a, lo = -b;   /* -a vs -b : larger a means smaller value */
      return mk('数学', 6, '比较大小：' + hi + ' ○ ' + lo + '，○ 里应填？', hi > lo ? '>' : '<',
        ['<', '>', '='], '负数在数轴上越靠左越小，绝对值大的反而小。');
    },
    function () {
      var pct = pick([20, 25, 40, 50, 80, 125, 150]), part = ri(2, 20) * 5;
      var whole = r2(part * 100 / pct);
      if (Math.abs(whole - Math.round(whole)) > 1e-9) return null;
      return mk('数学', 6, '一个数的 ' + pct + '% 是 ' + part + '，这个数是多少？', fnum(whole),
        [fnum(r2(part * pct / 100)), part * pct, fnum(r2(whole / 2))],
        '已知部分求整体：部分 ÷ 百分数。');
    },
    function () {
      var r = ri(1, 8), h = ri(2, 12);
      return mk('数学', 6, '一个圆柱底面半径 ' + r + ' 厘米、高 ' + h +
        ' 厘米，它的侧面积是多少平方厘米？（π 取 3.14）',
        fnum(r2(2 * 3.14 * r * h)),
        [fnum(r2(3.14 * r * h)), fnum(r2(3.14 * r * r)), fnum(r2(2 * 3.14 * r * r))],
        '圆柱侧面积 = 底面周长 × 高 = 2πrh。');
    },
    function () {
      var r = ri(1, 6), h = ri(2, 10);
      return mk('数学', 6, '一个圆柱底面半径 ' + r + ' 厘米、高 ' + h +
        ' 厘米，它的表面积是多少平方厘米？（π 取 3.14）',
        fnum(r2(2 * 3.14 * r * r + 2 * 3.14 * r * h)),
        [fnum(r2(3.14 * r * r + 2 * 3.14 * r * h)), fnum(r2(2 * 3.14 * r * h)),
         fnum(r2(3.14 * r * r * h))],
        '表面积 = 两个底面积 + 侧面积。');
    },
    function () {
      var a = ri(2, 9), b = ri(2, 9), c = ri(2, 12);
      if (b * c % a !== 0) return null;
      var x = Math.round(b * c / a);
      return mk('数学', 6, '解比例：' + a + ' : ' + b + ' = ' + c + ' : x，x = ？', x,
        [Math.round(b * c), Math.round(a * c / b) || 1, x * 2],
        '比例中两个外项之积等于两个内项之积：' + a + 'x = ' + b * c + '。');
    },
    function () {
      var a = pick([200, 250, 300, 400, 500, 800]), drop = pick([10, 20, 25, 40, 50]);
      var b = r2(a * (100 - drop) / 100);
      return mk('数学', 6, '一件商品原价 ' + a + ' 元，现价 ' + fnum(b) + ' 元，现价比原价降低了百分之几？',
        drop + '%', [drop * 2 + '%', (100 - drop) + '%', fnum(r2(drop / 2)) + '%'],
        '降低的百分数 = （原价 - 现价）÷ 原价。');
    },
    function () {
      var p = pick([1000, 2000, 3000, 5000, 8000]), rate = pick([1.5, 2, 2.5, 3]), y = pick([2, 3, 5]);
      return mk('数学', 6, '把 ' + p + ' 元存入银行，年利率 ' + fnum(rate) + '%，存 ' + y +
        ' 年，到期利息是多少元？', fnum(r2(p * rate / 100 * y)),
        [fnum(r2(p * rate / 100)), fnum(r2(p * rate / 100 * y + p)), fnum(r2(p * y))],
        '利息 = 本金 × 利率 × 存期。');
    },
    function () {
      var pair = pick([['立方分米', '升', 1], ['毫升', '立方厘米', 1],
                       ['立方米', '立方分米', 1000], ['升', '毫升', 1000]]);
      var v = ri(11, 95) / 10, k = pair[2];
      return mk('数学', 6, fnum(v) + ' ' + pair[0] + ' = ？' + pair[1], fnum(r2(v * k)),
        [fnum(r2(v * k / 10)), fnum(r2(v * k * 100)), fnum(v)],
        '1 ' + pair[0] + ' = ' + k + ' ' + pair[1] + '。');
    },
    function () {
      var a = ri(1, 5), b = ri(1, 7), total = (a + b) * ri(4, 20);
      return mk('数学', 6, '把 ' + total + ' 本书按 ' + a + ' : ' + b + ' 分给甲、乙两个班，甲班分到多少本？',
        total * a / (a + b), [total * b / (a + b), total / 2, total - a - b],
        '按比分配：先求总份数 ' + (a + b) + '，再求每份是多少。');
    },
    function () {
      var n = pick([20, 30, 40, 60, 80, 100]), dn = pick([2, 4, 5, 8]), nn = ri(1, dn - 1);
      var left = r2(n * (dn - nn) / dn);
      return mk('数学', 6, '一袋大米重 ' + n + ' 千克，吃了 ' + frac(nn, dn) + '，还剩多少千克？',
        fnum(left), [fnum(r2(n * nn / dn)), n - nn, fnum(r2(left / 2))],
        '剩下的占总数的 ' + frac(dn - nn, dn) + '，用 ' + n + ' 乘它。');
    },
    function () {
      var n = pick([12, 18, 24, 36, 48]), dn = pick([2, 3, 4, 6]), nn = ri(1, dn - 1);
      return mk('数学', 6, n + ' 的 ' + frac(nn, dn) + ' 是多少？', fnum(r2(n * nn / dn)),
        [fnum(r2(n / nn * dn)), n - nn, fnum(r2(n * nn / dn) + n)],
        '求一个数的几分之几，用这个数乘分数。');
    }
  ];

  /* ---------------- english data ---------------- */

  var W5 = [
    ['always', '总是'], ['usually', '通常'], ['often', '经常'], ['sometimes', '有时'],
    ['breakfast', '早餐'], ['dinner', '晚餐'], ['weekend', '周末'],
    ['spring', '春天'], ['summer', '夏天'], ['autumn', '秋天'], ['winter', '冬天'],
    ['season', '季节'], ['weather', '天气'], ['favourite', '最喜爱的'],
    ['birthday', '生日'], ['present', '礼物'], ['party', '聚会'],
    ['jacket', '夹克衫'], ['sweater', '毛衣'], ['shoes', '鞋'],
    ['mountain', '山'], ['river', '河'], ['lake', '湖'], ['forest', '森林'],
    ['village', '村庄'], ['bridge', '桥'], ['field', '田野'],
    ['holiday', '假日'], ['hospital', '医院'], ['cinema', '电影院'],
    ['library', '图书馆'], ['museum', '博物馆'], ['restaurant', '餐馆'],
    ['supermarket', '超市'], ['zoo', '动物园'], ['park', '公园'],
    ['farmer', '农民'], ['doctor', '医生'], ['nurse', '护士'],
    ['driver', '司机'], ['singer', '歌手'], ['cook', '厨师'],
    ['clever', '聪明的'], ['shy', '害羞的'], ['helpful', '乐于助人的'],
    ['funny', '滑稽的'], ['delicious', '美味的'], ['healthy', '健康的'],
    ['fresh', '新鲜的'], ['sweet', '甜的'], ['sour', '酸的'],
    ['homework', '作业'], ['exercise', '锻炼'], ['lesson', '课'],
    ['dance', '跳舞'], ['draw', '画画'], ['sing', '唱歌'],
    ['home', '家'], ['house', '房子'], ['room', '房间'],
    ['water', '水'], ['milk', '牛奶'], ['bread', '面包'],
    ['egg', '鸡蛋'], ['rice', '米饭'], ['noodle', '面条'],
    ['far', '远的'], ['near', '近的'], ['early', '早的'],
    ['busy', '忙的'], ['quiet', '安静的'], ['clean', '干净的'],
    ['carrot', '胡萝卜'], ['onion', '洋葱'], ['banana', '香蕉'], ['orange', '橙子'],
    ['grape', '葡萄'], ['watermelon', '西瓜'], ['tomato', '西红柿'], ['potato', '土豆'],
    ['chicken', '鸡肉'], ['beef', '牛肉'], ['soup', '汤'], ['salad', '沙拉'],
    ['hamburger', '汉堡包'], ['sandwich', '三明治'], ['juice', '果汁'], ['tea', '茶'],
    ['Monday', '星期一'], ['Friday', '星期五'], ['January', '一月'], ['July', '七月'],
    ['morning', '早晨'], ['afternoon', '下午'], ['evening', '傍晚'], ['night', '夜晚']
  ];

  var W6 = [
    ['science', '科学'], ['subject', '科目'], ['hobby', '爱好'],
    ['dancing', '跳舞（动名词）'], ['reading', '阅读'], ['drawing', '绘画'],
    ['post office', '邮局'], ['bookstore', '书店'], ['crossing', '十字路口'],
    ['traffic', '交通'], ['tomorrow', '明天'], ['tonight', '今晚'],
    ['yesterday', '昨天'], ['dictionary', '字典'], ['magazine', '杂志'],
    ['newspaper', '报纸'], ['comic', '漫画'], ['engineer', '工程师'],
    ['pilot', '飞行员'], ['policeman', '警察'], ['scientist', '科学家'],
    ['environment', '环境'], ['pollution', '污染'], ['recycle', '回收利用'],
    ['protect', '保护'], ['planet', '行星'], ['dangerous', '危险的'],
    ['important', '重要的'], ['interesting', '有趣的'], ['difficult', '困难的'],
    ['different', '不同的'], ['travel', '旅行'], ['journey', '旅程'],
    ['knowledge', '知识'], ['language', '语言'], ['culture', '文化'],
    ['invent', '发明'], ['discover', '发现'], ['receive', '收到'],
    ['remember', '记得'], ['medicine', '药'], ['illness', '疾病'],
    ['festival', '节日'], ['celebrate', '庆祝'], ['tradition', '传统'],
    ['vegetable', '蔬菜'], ['energy', '能量'], ['machine', '机器'],
    ['message', '消息'], ['opinion', '意见'], ['reason', '原因'],
    ['promise', '承诺'], ['surprise', '惊喜'], ['umbrella', '雨伞'],
    ['wonderful', '精彩的'], ['practice', '练习'], ['prepare', '准备'],
    ['problem', '问题'], ['several', '几个'], ['special', '特别的'],
    ['together', '一起'], ['neighbour', '邻居'], ['nature', '自然'],
    ['picnic', '野餐'], ['attention', '注意'], ['decision', '决定'],
    ['describe', '描述'], ['explain', '解释'], ['imagine', '想象'],
    ['between', '在……之间'], ['behind', '在……后面'], ['beside', '在……旁边'],
    ['above', '在……上方'], ['below', '在……下方'], ['inside', '在……里面'],
    ['across', '穿过'], ['along', '沿着'], ['during', '在……期间'],
    ['before', '在……之前'], ['until', '直到'], ['because', '因为'],
    ['although', '虽然'], ['however', '然而'], ['maybe', '也许'],
    ['finally', '最后'], ['already', '已经'], ['still', '仍然'],
    ['almost', '几乎'], ['enough', '足够的'], ['whole', '整个的']
  ];

  /* [base, -s, -ing, past] */
  var VERBS = [
    ['play', 'plays', 'playing', 'played'], ['study', 'studies', 'studying', 'studied'],
    ['watch', 'watches', 'watching', 'watched'], ['go', 'goes', 'going', 'went'],
    ['have', 'has', 'having', 'had'], ['do', 'does', 'doing', 'did'],
    ['eat', 'eats', 'eating', 'ate'], ['like', 'likes', 'liking', 'liked'],
    ['run', 'runs', 'running', 'ran'], ['swim', 'swims', 'swimming', 'swam'],
    ['see', 'sees', 'seeing', 'saw'], ['buy', 'buys', 'buying', 'bought'],
    ['take', 'takes', 'taking', 'took'], ['write', 'writes', 'writing', 'wrote'],
    ['give', 'gives', 'giving', 'gave'], ['come', 'comes', 'coming', 'came'],
    ['make', 'makes', 'making', 'made'], ['get', 'gets', 'getting', 'got'],
    ['teach', 'teaches', 'teaching', 'taught'], ['fly', 'flies', 'flying', 'flew'],
    ['wait', 'waits', 'waiting', 'waited'], ['help', 'helps', 'helping', 'helped'],
    ['clean', 'cleans', 'cleaning', 'cleaned'], ['visit', 'visits', 'visiting', 'visited'],
    ['live', 'lives', 'living', 'lived'], ['dance', 'dances', 'dancing', 'danced'],
    ['stop', 'stops', 'stopping', 'stopped'], ['carry', 'carries', 'carrying', 'carried'],
    ['finish', 'finishes', 'finishing', 'finished'], ['listen', 'listens', 'listening', 'listened'],
    ['open', 'opens', 'opening', 'opened'], ['walk', 'walks', 'walking', 'walked'],
    ['talk', 'talks', 'talking', 'talked'], ['draw', 'draws', 'drawing', 'drew'],
    ['sing', 'sings', 'singing', 'sang'], ['cook', 'cooks', 'cooking', 'cooked'],
    ['want', 'wants', 'wanting', 'wanted'], ['know', 'knows', 'knowing', 'knew'],
    ['think', 'thinks', 'thinking', 'thought'], ['find', 'finds', 'finding', 'found'],
    ['ride', 'rides', 'riding', 'rode'], ['drive', 'drives', 'driving', 'drove'],
    ['sleep', 'sleeps', 'sleeping', 'slept'], ['speak', 'speaks', 'speaking', 'spoke'],
    ['stand', 'stands', 'standing', 'stood'], ['sit', 'sits', 'sitting', 'sat'],
    ['begin', 'begins', 'beginning', 'began'], ['bring', 'brings', 'bringing', 'brought'],
    ['catch', 'catches', 'catching', 'caught'], ['choose', 'chooses', 'choosing', 'chose'],
    ['fall', 'falls', 'falling', 'fell'], ['feel', 'feels', 'feeling', 'felt'],
    ['forget', 'forgets', 'forgetting', 'forgot'], ['hear', 'hears', 'hearing', 'heard'],
    ['hold', 'holds', 'holding', 'held'], ['keep', 'keeps', 'keeping', 'kept'],
    ['leave', 'leaves', 'leaving', 'left'], ['lose', 'loses', 'losing', 'lost'],
    ['meet', 'meets', 'meeting', 'met'], ['send', 'sends', 'sending', 'sent'],
    ['spend', 'spends', 'spending', 'spent'], ['wear', 'wears', 'wearing', 'wore']
  ];

  var NOUNS = [
    ['book', 'books'], ['box', 'boxes'], ['bus', 'buses'], ['baby', 'babies'],
    ['city', 'cities'], ['knife', 'knives'], ['leaf', 'leaves'], ['child', 'children'],
    ['man', 'men'], ['woman', 'women'], ['tooth', 'teeth'], ['foot', 'feet'],
    ['mouse', 'mice'], ['sheep', 'sheep'], ['fish', 'fish'], ['photo', 'photos'],
    ['potato', 'potatoes'], ['tomato', 'tomatoes'], ['family', 'families'],
    ['class', 'classes'], ['watch', 'watches'], ['apple', 'apples'],
    ['strawberry', 'strawberries'], ['hero', 'heroes'], ['deer', 'deer'],
    ['dish', 'dishes'], ['brush', 'brushes'], ['church', 'churches'],
    ['glass', 'glasses'], ['dress', 'dresses'], ['story', 'stories'],
    ['country', 'countries'], ['party', 'parties'], ['hobby', 'hobbies'],
    ['wolf', 'wolves'], ['shelf', 'shelves'], ['wife', 'wives'],
    ['zoo', 'zoos'], ['radio', 'radios'], ['piano', 'pianos'], ['goose', 'geese']
  ];

  var ADJS = [
    ['big', 'bigger'], ['small', 'smaller'], ['tall', 'taller'], ['happy', 'happier'],
    ['easy', 'easier'], ['heavy', 'heavier'], ['good', 'better'], ['bad', 'worse'],
    ['many', 'more'], ['hot', 'hotter'], ['thin', 'thinner'], ['fat', 'fatter'],
    ['beautiful', 'more beautiful'], ['interesting', 'more interesting'],
    ['old', 'older'], ['young', 'younger'], ['long', 'longer'], ['fast', 'faster'],
    ['early', 'earlier'], ['late', 'later'], ['busy', 'busier'], ['few', 'fewer'],
    ['cold', 'colder'], ['warm', 'warmer'], ['strong', 'stronger'], ['weak', 'weaker'],
    ['dirty', 'dirtier'], ['safe', 'safer'], ['careful', 'more careful'],
    ['difficult', 'more difficult'], ['popular', 'more popular'], ['quiet', 'quieter'],
    ['noisy', 'noisier'], ['slow', 'slower'], ['wet', 'wetter'], ['dry', 'drier'],
    ['lucky', 'luckier'], ['funny', 'funnier'], ['kind', 'kinder']
  ];

  function enWord(grade) {
    var mine = grade === 5 ? W5 : W6, other = grade === 5 ? W6 : W5;
    var all = mine.concat(other), e = pick(mine);
    function draw(idx) {
      var out = [], i = 0;
      while (out.length < 3 && i < 60) {
        i++;
        var o = pick(all)[idx];
        if (o !== e[idx] && out.indexOf(o) < 0) out.push(o);
      }
      return out;
    }
    if (ri(0, 1)) {
      return mk('英语', grade, '单词 “' + e[0] + '” 的意思是？', e[1], draw(1),
        e[0] + ' = ' + e[1] + '。');
    }
    return mk('英语', grade, '“' + e[1] + '” 用英语怎么说？', e[0], draw(0),
      e[1] + ' = ' + e[0] + '。');
  }

  function enVerb(grade) {
    var v = pick(VERBS), kind = pick(['s', 'ing', 'past']);
    var wrongs, q, correct, why;
    function others(forms) {
      var out = [], i = 0;
      while (out.length < 3 && i < 30) {
        i++;
        var w = pick(VERBS);
        if (forms.indexOf(w[0]) >= 0) continue;
        var f = w[ri(1, 3)];
        if (f !== forms[0] && out.indexOf(f) < 0) out.push(f);
      }
      return out;
    }
    if (kind === 's') {
      correct = v[1];
      wrongs = [v[0], v[3], v[2]];
      q = 'He ___ every day.（' + v[0] + '）';
      why = '一般现在时主语是第三人称单数，动词加 -s 或 -es。';
    } else if (kind === 'ing') {
      correct = 'is ' + v[2];
      wrongs = [v[1], v[3], v[0] + 'ing'];
      q = 'Look! The boy ___ now.（' + v[0] + '）';
      why = '现在进行时：be + 动词的 -ing 形式。';
    } else {
      correct = v[3];
      wrongs = [v[0], v[1], v[2]];
      q = 'Yesterday he ___ with his friends.（' + v[0] + '）';
      why = '一般过去时用动词的过去式。';
    }
    return mk('英语', grade, q, correct, wrongs, why);
  }

  /* Plausible wrong plurals of the SAME noun: forgetting -es / y->ies / f->ves,
     leaving it unchanged, or double marking. Unrelated plurals give the answer
     away by the stem alone, so they are only used to fill the last slot. */
  function pluralPool(base, correct) {
    var out = [];
    function add(x, allowBase) {
      if (x && x !== correct && (allowBase || x !== base) && out.indexOf(x) < 0) out.push(x);
    }
    add(base, true);
    add(base + 's');
    /* fish/deer/sheep: -es would be a real variant, not a mistake */
    if (correct !== base) add(base + 'es');
    if (/[^aeiou]y$/.test(base)) {
      add(base.slice(0, -1) + 'ies');
      add(base.slice(0, -1) + 'ys');
    }
    if (/fe$/.test(base)) add(base.replace(/fe$/, 'ves'));
    if (/f$/.test(base)) add(base.replace(/f$/, 'ves'));
    if (correct !== base && correct.indexOf(base.slice(0, 2)) !== 0) add(correct + 's');
    return out;
  }

  function nounClass(w) {
    if (/[^aeiou]y$/.test(w)) return 'y';
    if (/(s|x|ch|sh)$/.test(w)) return 'es';
    if (/(f|fe)$/.test(w)) return 'f';
    if (/o$/.test(w)) return 'o';
    if (/(man|child|foot|tooth|goose)$/.test(w)) return 'irr';
    return 'plain';
  }

  function enNoun(grade) {
    var n = pick(NOUNS), wrongs = pluralPool(n[0], n[1]);
    var cls = nounClass(n[0]), i, o;
    /* top up with same-pattern nouns first, they at least sound alike */
    for (i = 0; i < 40 && wrongs.length < 3; i++) {
      o = pick(NOUNS);
      if (nounClass(o[0]) !== cls) continue;
      if (o[1] !== n[1] && wrongs.indexOf(o[1]) < 0) wrongs.push(o[1]);
    }
    for (i = 0; i < 40 && wrongs.length < 3; i++) {
      o = pick(NOUNS);
      if (o[1] !== n[1] && wrongs.indexOf(o[1]) < 0) wrongs.push(o[1]);
    }
    shuffle(wrongs);
    return mk('英语', grade, '“' + n[0] + '” 的复数形式是？', n[1], wrongs.slice(0, 3),
      '名词复数：一般加 -s，以 s/x/ch/sh 结尾加 -es，辅音+y 变 ies，f/fe 变 ves；' +
      '不规则的（man/woman/child/foot/tooth/goose）要单独记。');
  }

  var SUP_IRREG = { good: 'best', bad: 'worst', many: 'most' };
  var IRREG_CMP_WRONG = {
    good: ['gooder', 'more good', 'best'],
    bad: ['badder', 'more bad', 'worst'],
    many: ['manyer', 'much', 'most']
  };
  var IRREG_SUP_WRONG = {
    good: ['goodest', 'most good', 'better'],
    bad: ['baddest', 'most bad', 'worse'],
    many: ['manyest', 'most many', 'much']
  };
  /* adjectives that read naturally in "This one is ___ than that one." */
  var SENT_OK = { big: 1, small: 1, tall: 1, long: 1, hot: 1, cold: 1, fast: 1, slow: 1,
                  old: 1, young: 1, heavy: 1, easy: 1, busy: 1, dirty: 1, strong: 1,
                  quiet: 1, kind: 1, funny: 1, lucky: 1, safe: 1, wet: 1, dry: 1,
                  thin: 1, fat: 1, warm: 1, weak: 1, noisy: 1 };

  function supOf(base, cmp) {
    if (SUP_IRREG[base]) return SUP_IRREG[base];
    if (cmp.indexOf('more ') === 0) return 'most ' + base;
    return cmp.slice(0, -2) + 'est';
  }

  /* Wrong forms of the same word: kids get confused by doubling, y->i, and by
     mixing in more/most or the other degree, not by an unrelated adjective. */
  function cmpPool(base, cmp) {
    var sup = supOf(base, cmp), out = [];
    function add(x) {
      if (x && x !== cmp && x !== base && out.indexOf(x) < 0) out.push(x);
    }
    if (IRREG_CMP_WRONG[base]) return IRREG_CMP_WRONG[base].slice();
    add('more ' + base);
    add(base + 'er');
    if (cmp.indexOf('more ') !== 0) add('more ' + cmp);
    add(sup);
    add(base + 'est');
    return out;
  }

  function supPool(base, cmp) {
    var sup = supOf(base, cmp), out = [];
    if (IRREG_SUP_WRONG[base]) return IRREG_SUP_WRONG[base].slice();
    function add(x) {
      if (x && x !== sup && x !== base && out.indexOf(x) < 0) out.push(x);
    }
    add(cmp);
    add(base + 'est');
    add('most ' + base);
    if (cmp.indexOf('more ') !== 0) add('most ' + cmp);
    add(base + 'er');
    return out;
  }

  function enAdj(grade) {
    var a = pick(ADJS), base = a[0], cmp = a[1], sup = supOf(base, cmp);
    var asSup = ri(0, 1) === 1;
    var correct = asSup ? sup : cmp;
    var pool = asSup ? supPool(base, cmp) : cmpPool(base, cmp);
    var i, o, f, v;
    for (i = 0; i < 30 && pool.length < 3; i++) {
      o = pick(ADJS);
      f = supOf(o[0], o[1]);
      v = asSup ? f : o[1];
      if (v !== correct && pool.indexOf(v) < 0) pool.push(v);
    }
    shuffle(pool);
    var q;
    if (SENT_OK[base] && ri(0, 1)) {
      q = asSup ? 'This is the ___ one of all.（' + base + '）'
                : 'This one is ___ than that one.（' + base + '）';
    } else {
      q = asSup ? '“' + base + '” 的最高级是？' : '“' + base + '” 的比较级是？';
    }
    return mk('英语', grade, q, correct, pool.slice(0, 3),
      base + ' → 比较级 ' + cmp + '，最高级 ' + sup + '。一般加 -er/-est（重读闭音节双写末尾字母，辅音+y 变 i），' +
      '多音节词用 more/most，不规则变化要单独记。');
  }

  function mathFor(grade) {
    var t = grade === 6 ? T6 : T5;
    return pick(t)();
  }

  function englishFor(grade) {
    var k = ri(1, 4);
    if (k === 1) return enVerb(grade);
    if (k === 2) return enNoun(grade);
    if (k === 3) return enAdj(grade);
    return enWord(grade);
  }

  function make(grade) {
    var out = [], i, q;
    for (i = 0; i < 24; i++) { q = mathFor(grade); if (q) out.push(q); }
    for (i = 0; i < 24; i++) { q = englishFor(grade); if (q) out.push(q); }
    return out;
  }

  var api = { make: make, mathFor: mathFor, englishFor: englishFor };
  root.TVGEN = api;
  /* also usable from node: require('./gen.js') */
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window
  : (typeof globalThis !== 'undefined' ? globalThis : this));
