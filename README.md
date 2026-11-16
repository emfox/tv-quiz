# tv-quiz

给家里的电视加一道"答题闸门"：看满一段时间的视频后弹出几道小学题，答对才继续看；同一个应用退出重进不影响计时，过午夜自动重置。整机不需要安装任何 APK。

## 为什么不是 App

- 这台 TCL 雷鸟（`65S535D Pro`，MT9652 / Android 9）有签名校验：第三方桌面在 `installPackageLI` 阶段被 `INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES` 拦掉，要做成系统应用只能往 `/system/product/app` 里塞。
- 控制需要的能力（读当前前台应用、拉起/关闭页面、写状态文件）在 root shell 里全都有，不必进 App 层。
- 题库要反复改，改一个 JSON 比重新打包安装省事得多。

于是最终形态是：**一个本地网页 + 一个 root shell 看门狗**，宿主用系统自带的 `com.tcl.browser`。

## 组成

```
config/gate.conf        唯一配置：档位、年级、题数、模式、名单、端口
config/profiles/        设备画像：浏览器包名、busybox 路径、自启方式
  ├── tcl.conf            TCL / 雷鸟（本仓库最初适配的机器）
  └── generic.conf        其它已 root 的安卓电视 / 盒子
quiz/                   出题与页面
  ├── gen.js              运行时出题（数学、英语），可 require
  ├── pick.js             组一轮题（按科目取、避开最近出过的），可 require
  ├── bank.json           静态题库（语文，1297 题）
  ├── index.html          答题界面（ES5，兼容电视的 WebView 66）
  ├── gen_bank.py         语文题库构建器（人工题 + 数据表展开）
  ├── cn_data.py          语文数据表（古诗/成语/反义/多音字/量词/病句/修辞/关联词/常识）
  ├── cli.js              命令行出题，用来预览和校验
  └── check.js sim.js adj_sample.js   自检脚本
gate/                   控制部分
  ├── gate.sh             看门狗（root 运行；设备差异全从 config.sh 读）
  ├── tvgate.rc.in        init 服务模板（initrc 自启用，@DEVICE_DIR@ 由安装脚本替换）
  ├── boot.sh.in          开机脚本模板（magisk / initd 自启用）
  └── cgi-bin/
      ├── pass.sh.in      通关标记 CGI
      └── log.sh.in       答题信标 CGI（写 quiz.log，事后核对答了几题）
tools/
  ├── install.sh          部署到电视（合并配置、推文件、装自启、重启服务）
  ├── status.sh           看服务/配置/当天次数/日志
  ├── probe.sh            采样前台应用，帮新机器填名单
  ├── uninstall.sh        卸载
  └── tvroot.sh           以 root 执行命令并回读输出（依赖固件里的 tvroot 服务）
```

设备上统一落在 `/data/local/tmp/tvquiz/`（可用 `DEVICE_DIR` 改）。

## 执行逻辑

1. **采样**：`gate.sh` 每 `STEP`（默认 10）秒用 `dumpsys window` 取当前前台包名。
2. **判定**：`MODE=except` 时，除 `SKIP`（桌面 / 设置 / 系统弹窗 / 安装器 / 升级）外一律计入；`MODE=watch` 时只计 `WATCH` 名单。命中就 `acc += STEP`，否则只累加"离开时长"，离开超过 `AWAY_RESET` 才把 `acc` 清零——所以回桌面再点开不会重新计时。
3. **到档位弹题**：`acc >= LIMITS[当天第几次]` 时，记下当前前台组件，然后
   `am start -a VIEW http://127.0.0.1:8088/?g=<年级>&n=<题数>&t=<时间戳>`。`t` 用来破 WebView 缓存。
4. **答题**：页面从 `bank.json` 取语文、用 `gen.js` 现场生成数学和英语，经 `pick.js` 组题，**一轮固定 `N` 题**。答错换一组新题重来，不会卡死。
   一轮 = 一次页面加载：**不做跨页面接续**（否则"答两题走开、回来补一题"就能通关）。
   每看一题 / 每答一次 / 通关各发一个信标到 `cgi-bin/log.sh`，写进 `quiz.log`。
5. **放行**：答对后页面 `fetch('cgi-bin/pass.sh')` 写 `pass.stamp`；看门狗每 3 秒查它，看到就
   `force-stop <BROWSER>`，再把第 3 步记下的组件 `am start -n` 拉回前台。拉回的是**同一个任务**（`taskId` 不变），所以播放进度是接着的。
6. **次数**：只有答对放行才把当天次数 +1，写进 `state`（`d=日期 n=次数`）；日期变了就归零，等于每天从第一档重新开始。

答题过程中退出、按 Home、切别的应用都会被拉回；电视自动息屏时不会去唤醒它，而是中止本轮。

## 答题日志（核对"这轮答了几题"）

页面每看一题、每答一次、通关时各发一个 GET 到 `cgi-bin/log.sh`，按行追加到
`/data/local/tmp/tvquiz/quiz.log`：

```
11-16 19:12:03 v=start&want=3&n=3&g=5&q=%3Fg%3D5%26n%3D3%26t%3D...
11-16 19:12:05 v=show&i=1&n=3
11-16 19:12:09 v=ans&i=1&n=3&ok=1
11-16 19:12:13 v=show&i=2&n=3
...
11-16 19:12:31 v=pass&n=3&ans=3
```

- `start` 里的 `n` 是这一轮实际题目数（正常应等于 `config.sh` 的 `N`）；
- `pass&ans=` 是这一轮答对的题数，**必须等于 `n`** 才可能通关；
- 只有 `pass` 且 `ans == n` 才是"老老实实答完"。

```sh
adb shell tail -20 /data/local/tmp/tvquiz/quiz.log
```

## 配置

参数分两类：

- **偏好**放在 `config/gate.conf`（档位、年级、题数、名单……）；
- **设备事实**放在 `config/profiles/<名>.conf`（浏览器包名、busybox 路径、自启方式），由 `PROFILE` 选择。

`install.sh` 把两份合并成一份，拷到电视上作为 `config.sh`；同名参数以 `gate.conf` 为准
（想临时覆盖某个设备参数，直接在 `gate.conf` 里写一行即可）。

| 参数 | 默认 | 说明 |
|---|---|---|
| `ADB_HOST` | `192.168.10.60:5555` | 电视的 adb 地址，只给 `tools/*.sh` 用 |
| `DEVICE_DIR` | `/data/local/tmp/tvquiz` | 设备上的安装目录 |
| `PROFILE` | `tcl` | 设备画像名，对应 `config/profiles/<名>.conf` |
| `BROWSER` | 见 profile | 打开答题页的浏览器包名；`auto` = 安装时在设备上探测 |
| `BB` | 见 profile | busybox 路径（只有 httpd/wget 用它）；`auto` = 运行时探测 6 个常见位置 |
| `BOOT_MODE` | 见 profile | `initrc` / `magisk` / `initd` / `none` / `auto` |
| `ROOT_MODE` | `auto` | `auto` / `tvroot` / `su`，只影响安装脚本挑哪条 root 通道 |
| `LIMITS` | `600 600 480 480 300` | 当天第 1、2…次弹题前的宽限秒数，最后一档重复；过午夜归零 |
| `GRADE` | `5` | 出题年级，`5` 或 `6` |
| `N` | `3` | 每轮题数（1–6） |
| `MODE` | `except` | `except` 全量计入（推荐）；`watch` 只计 `WATCH` |
| `AWAY_RESET` | `1800` | 离开多久后累计时长清零 |
| `STEP` | `10` | 采样间隔（秒），决定计时精度 |
| `QUIZ_TIMEOUT` | `420` | 单轮答题超时（秒），超时关页面重弹 |
| `PORT` | `8088` | 本地 httpd 端口 |
| `DBG` | `0` | `1` = 页面角落显示答案 + 每次采样写 tick 日志（测试用） |
| `SKIP` | 见文件 | `MODE=except` 时不计入的包 |
| `WATCH` | 见文件 | `MODE=watch` 时计入的包 |

改完跑一次 `tools/install.sh`（会重启看门狗）即生效。只改 `LIMITS`/`GRADE`/`N`/`DBG` 这类启动时读取的参数，必须重启；`state` 和 `pause` 是运行时文件，随时可改：

```sh
tools/install.sh                                        # 推文件 + 重启服务
tools/status.sh                                         # 看状态

adb shell touch /data/local/tmp/tvquiz/pause             # 暂停（不弹题）
adb shell rm    /data/local/tmp/tvquiz/pause             # 恢复
adb shell 'echo set=1 >> /data/local/tmp/tvquiz/state'   # 把当天次数手动改成 1，10 秒内生效
```

## 安装 / 更新 / 卸载

电视要开机、和电脑同网段、adb 调试已打开。

```sh
tools/install.sh                    # 首次安装或更新
tools/install.sh --profile generic  # 换一份设备画像
tools/install.sh --no-restart       # 只推文件，不打断正在跑的闸门
tools/install.sh --list-profiles    # 看有哪些画像
tools/status.sh                     # 服务、配置、当天次数、日志
tools/uninstall.sh [--with-boot]    # 卸载（--with-boot 连开机自启一起删）
adb 不在 PATH 时：ADB=/path/to/adb tools/install.sh
```

`install.sh` 会依次：连设备 → 合并 profile + `gate.conf` → 探测浏览器 / busybox / 自启方式 →
推 `quiz/`、`gate/`、合并后的配置 → 装开机自启（已存在则不覆盖）→ 重启看门狗 → 打印状态。
装自启和重启进程要 root，走 `tools/tvroot.sh`（固件里的 `tvroot` init 服务）或 `su`；
没有 root 时只推文件，并提示需要手动启动或重启电视。

## 出题模块单独用

出题不依赖电视、不依赖看门狗，三种用法：

```sh
# 1) 命令行打印题目
node quiz/cli.js                      # 5 年级，一轮 3 题
node quiz/cli.js --grade 6 --n 4
node quiz/cli.js --subject 英语 --n 2 --rounds 3
node quiz/cli.js --json               # JSON 输出，方便喂给别的程序

# 2) 当库用
const GEN  = require('./quiz/gen.js');    // make(grade) mathFor(grade) englishFor(grade)
const PICK = require('./quiz/pick.js');   // buildRound({pool, want, recent, subjects})
const bank = require('./quiz/bank.json').questions;
const round = PICK.buildRound({ pool: GEN.make(5).concat(bank.filter(q => q.grade === 5)), want: 3 });

# 3) 浏览器直接开
cd quiz && python3 -m http.server 8099    # 打开 http://127.0.0.1:8099/?g=5&n=3
```

网页和命令行用的是同一份 `pick.js` / `gen.js`，所以预览出来的题就是电视上会出的题。

## 加题

- **语文**：往 `quiz/cn_data.py` 的数据表里加一行，答案由表格本身保证；`python3 quiz/gen_bank.py` 重新生成 `bank.json`（构建时会检查"同一题干必须同一答案"）。
- **数学 / 英语**：在 `quiz/gen.js` 对应函数里加模板或词表；数学用整数/分数构造保证答案正确，英语的比较级/最高级与名词复数干扰项取**同一个词的错误形式**（`more big`、`biger`、`boxs`…），不从别的词借。

自检：

```sh
node quiz/check.js        # 13 万题结构校验：选项 4 个不重复、无 NaN、答案索引合法
node quiz/sim.js          # 假 DOM 跑 200 轮真实页面：抽题、断电恢复、通关回调
node quiz/adj_sample.js   # 抽样比较级/最高级题，肉眼过一遍
```

## 移植到其它设备

### 依赖分层：只剩一个硬门槛

| 依赖 | 通用性 | 在哪儿解决 |
|---|---|---|
| 控制循环（读前台 / 拉起 / 关闭 / 写文件） | ✅ 纯 shell，`shell` 用户就能做 | `gate/gate.sh` |
| 宿主浏览器 | ⭕ 换个包名即可 | `BROWSER`（`auto` 时安装脚本探测） |
| busybox（**只有** httpd / wget 需要） | ⭕ 六个常见路径自动探测 | `BB=auto` |
| `dumpsys` / `am` 输出格式随版本变 | ⭕ 已兼容新旧 ROM | `focus_line()`、`quiz_visible()` |
| 开机自启 | ❌ 要 root + 一个自启位置 | `BOOT_MODE` |
| 改脚本后重启看门狗 | ❌ 要 root | `ROOT_MODE` |

代码里已经没有厂商相关的硬编码：包名、路径、自启方式全在 `config/` 里。真正卡人的只有
**"一个能开机自启的 root 进程"**——这也是做成 APK（Device Owner + 无障碍）才能绕开的那道墙。

### 开机自启的三种落点

| `BOOT_MODE` | 落点 | 适用 |
|---|---|---|
| `initrc` | `/vendor/etc/init/tvgate.rc` | 能写 `/vendor` 的固件（本机 TCL 走这条，由 init 托管、能自动重启） |
| `magisk` | `/data/adb/service.d/50-tvquiz.sh` | Magisk / KernelSU / APatch，最省事 |
| `initd` | `/system/etc/init.d/99-tvquiz` | 老 ROM / 部分定制固件（需要能 remount rw） |
| `none` | — | 都没有时，重启后手动跑 `gate.sh` |

`auto` 会按 `service.d` → `/vendor/etc/init` → `init.d` 的顺序探测。

### 换机器的步骤

```sh
# 1) 看看有哪些画像
tools/install.sh --list-profiles

# 2) 采样：跑起来之后拿遥控器把该计时的应用（影视、直播、HDMI）和
#    不该计时的界面（桌面、设置）各停几秒
tools/probe.sh --host 192.168.1.9:5555 -t 60

# 3) 把输出粘进 config/gate.conf（不想要名单也可以保持 MODE=except）
tools/probe.sh -t 60 --emit watch >> /tmp/new.conf

# 4) 部署，按设备探测的结果装自启
tools/install.sh --profile generic --host 192.168.1.9:5555
tools/status.sh  --host 192.168.1.9:5555
```

`probe.sh -t 60` 的输出（按停留时长排序，同时给出 `am start -n` 要用的完整组件名）：

```
按停留时长排序：
     36s    24次  com.tcl.vod
     17s    11次  com.tcl.tv
      9s     6次  com.spocky.projengmenu

完整组件名（am start -n 用）：
  com.tcl.vod/com.tcl.vod.MainActivity
  com.tcl.tv/com.tcl.tv.TVActivity
  com.spocky.projengmenu/com.spocky.projengmenu.ui.home.MainActivity
```

### 没有 root 能做到什么

推文件、`gate.sh` 手动前台运行都能跑起来（计数、弹题、答题、放行都正常），差的只是
**开机自启**和**改配置后重启服务**。重新开机就得手动：

```sh
adb shell "nohup /data/local/tmp/tvquiz/gate.sh >/dev/null 2>&1 &"
```

（部分 ROM 会回收这种后台进程，所以正式用还是要 root 自启。）

## 已知限制

- 需要一个能开机自启的 **root 进程**：这是唯一的硬门槛（见上节）。
- 宿主是**浏览器**：本机用 `com.tcl.browser`，换机器要换成能访问 `http://127.0.0.1` 的浏览器
  （`com.android.htmlviewer` 不行，它没有 INTERNET 权限）。浏览器被禁用或清数据就失效。
- 闸门本身没有界面，全靠文件与配置驱动；改启动时读的参数要重启看门狗。
- 不答就一直拦着（`QUIZ_TIMEOUT` 后重开新的一轮），没有"放弃"出口；需要的话可以加"连续 N 轮超时后自动息屏"。
- 一轮答题**不接续**：页面重开/看门狗重弹都从第 1 题开始。早先为了"页面重开能接着答"存了进度，
  结果"答两题走开、回来补一题"就能通关（就是"只做一题就过了"），已去掉。
- 电视**时钟会跳**：掉电后 RTC 回到 `2000-01-01`，对时后跳到当天。早先这会被当成"跨日"清零当天次数
  （拔电源即可重置档位）；现在只有"新日期更晚且两个日期都合理（≥2024）"才清零，否则日志写
  `clock jumped ... count kept`。
- HDMI 输入在系统里就是 `com.tcl.tv`，所以外接 Switch / 电视果同样计时；答题那几分钟主机不会暂停。
- 这台机器的 `root` 来自刷过的固件里的 `tvroot` init 服务（`CapEff=3fffffffff`）；原厂固件上
  `su` 是空壳（`CapBnd=0xc0`）。换机器时只要 `su` 能拿到完整权限（Magisk 等）就行。
