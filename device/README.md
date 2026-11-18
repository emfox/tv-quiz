# device —— 这台电视的 root / init 小工具

tv-quiz 本身要靠 root shell 跑，但「怎么拿到 root」「怎么装 init 服务」跟答题逻辑无关，
单独收在这里。以后东西多了再拆成独立仓库。

## 两条 root 通道，能力不一样

这台 65S535D Pro 刷的是改过的固件，给了两个入口，**它们不等价**，用错会以为「root 了但没效果」。

| | `su`（默认） | `tvroot`（`-t`） |
|---|---|---|
| 来源 | `/factory/su`，setuid 的 mksh 副本，改过的 `init.rc` 每次开机重建 | `/init.rc:911` 的 init 服务，init fork 出来 |
| `Uid:` | `2000 0 0 0`（真 uid 仍是 shell） | `0 0 0 0` |
| `CapEff:` | **`0`** | `3fffffffff`（全给） |
| SELinux 域 | `u:r:shell:s0` | init 域 |
| 能不能 remount | **不能**（`not user mountable in fstab`） | 能 |
| 能不能 `stop`/`setprop` 动 init 服务 | 不能（toybox 查真 uid，看到 2000） | 能 |
| 能读别人属主的文件 | **不能**：没有 `CAP_DAC_OVERRIDE`，uid 0 只是个数字，mode 位照样卡 | 能 |
| 延迟 | 无 | 每次 2 秒轮询（服务在 `sleep 2`） |

所以：`dumpsys` / `am` / 读写自己那份状态文件 → 用默认通道，快；remount、装 init 服务、
改属性 → 必须 `-t`。

★ 原厂没有 `su`。`/factory/su` 是 init 每次开机从 `/system/bin/sh` 复制出来的一份 mksh（见
`/init.rc:903-908`），只给 euid 0、真 uid 还是 2000 ⟹ `su -c cmd` 会自己降权。`device/su/` 里的
wrapper 解决这个问题，见下面「`/system/bin/su` 是谁」。

## 文件

| 文件 | 干什么 |
|---|---|
| `root.sh` | 唯一入口。`'命令'` / `-f 脚本` / 从 stdin 读；`-t` 切到 tvroot 通道。命令走文件推送，不用跟引号搏斗 |
| `su/su.c` | 1 KB 的 freestanding wrapper：`setresgid(0,0,0)` + `setresuid(0,0,0)` 后 exec `/system/bin/sh` |
| `su/Makefile` | 交叉编译成 32 位 ARM 静态 ELF（设备 ABI 是 armeabi-v7a） |
| `su/install.sh` | 编译 + 安装到 `/system/bin/su`，6755，装完自动 remount 回只读 |
| `launcher/install.sh` | 装防抢桌面的 init 服务到 `/vendor/etc/init/lchome.rc` |
| `launcher/lchome.rc.in` | 上面那个服务的模板，`@DEVICE_DIR@` 由 `install.sh` 替换 |
| `launcher/lchome.sh` | 服务体：等 `sys.boot_completed=1` 再等 10 秒，发标准 HOME intent（换任何桌面都能用） |
| `launcher/tvhome.rc` | 更简单的备选：开机 8 秒后直接 `am start` Projectivy，不通用于别的桌面 |
| `launcher/lchome.rc.in` | 上面那个服务的模板，`@DEVICE_DIR@` 由 `install.sh` 替换 |
| `launcher/lchome.sh` | 服务体：等 `sys.boot_completed=1` 再等 10 秒，发标准 HOME intent（换任何桌面都能用） |
| `launcher/tvhome.rc` | 更简单的备选：开机 8 秒后直接 `am start` Projectivy，不通用于别的桌面 |

## 前置

```sh
ADB=/path/to/adb            # 默认用 PATH 上的 adb
TV_HOST=192.168.10.60:5555  # 默认这台
adb connect "$TV_HOST"
```

## 用法

```sh
device/root.sh 'id'
device/root.sh -t 'mount -o remount,rw /'
device/root.sh -f some-script.sh              # su 通道；要 remount 就加 -t
printf 'mount | head -3\n' | device/root.sh
device/su/install.sh                          # 编译并安装 /system/bin/su
device/launcher/install.sh                    # 装 lchome，重启后生效
```

## `/system/bin/su` 是谁

原厂固件没有 `su`。`/factory/su` 确实是很好的 root 通道，但它是 mksh 的副本、只改 euid，
所以 `su -c cmd` 里的 `sh` 又会自己降权（见坑 1）。`device/su/` 装的是一个 1 KB 的 wrapper：

```
setresgid(0,0,0) → setresuid(0,0,0) → execve("/system/bin/sh", {"sh", "-c", cmd, ...}, envp)
```

真 uid 也变成 0 之后，mksh 的 `euid != ruid` 判断不再成立，**`su -c` 不用带 `-p` 了**，
脚本里写 `su -c ...` 的老习惯也能正常工作。装法：`device/su/install.sh`。

固化：写进 `/system/bin/su`（`/` 是 ext4 实体分区，`chmod 6755`），**重启后还在，而且不依赖
每次开机重建的 `/factory/su`**。`/factory/su` 本身不动，`root.sh` 也按绝对路径用它，所以
wrapper 装坏了不会把人锁在外面。

**仍然做不到 remount。** shell 域的 `CapBnd` 只有 `0xc0`（`CAP_SETGID|CAP_SETUID`），
能力边界集不能靠 exec 一个 setuid 二进制突破，所以 `su` 里永远不会有 `CAP_SYS_ADMIN`。
要 remount 或动 init 服务，只能 `device/root.sh -t`。实测 `su -c 'stop x'` 已经不再报
`must be root`（uid 检查过了），但会死在 `failed to set property 'ctl.stop'`——SELinux 拦的。

装坏了回退成软链（能跑，但 `-p` 得自己带）：

```sh
device/root.sh -t 'mount -o remount,rw /; rm -f /system/bin/su; ln -sf /factory/su /system/bin/su; mount -o remount,ro /'
```

## 四个坑（都是实测踩出来的）

1. **走 `/factory/su` 时 `-p` 不能省，也不能再套一层 `sh`。** mksh 见到 `euid != ruid` 就
   `setuid(getuid())` 降权。`-p` 保住 euid 0；但 `/factory/su -p -c 'sh foo.sh'` 里那个内层 `sh`
   又没带 `-p`，照样降回 2000。正确写法是直接把脚本交给特权 mksh：`/factory/su -p /path/foo.sh`。
   `root.sh` 就是这么做的。（装了 `device/su` 的 wrapper 之后就没这回事了，真 uid 已经是 0。）
2. **推给 root 的文件得是 644。** `adb push` 落盘属主是 `shell`，root 通道没有 `CAP_DAC_OVERRIDE`，
   `chmod 700` 会让它自己都读不了（`sh: Permission denied`）。
3. **判进程要锚定。** `pgrep -f '^/system/bin/sh /path/x.sh'`，`^` 不能省：不带锚点会把执行扫描的
   那条命令自己也匹配上，于是「根本没在跑」也报「在跑」。
4. **tvroot 通道的完成信号是「`tvroot.cmd` 消失」**，不是 `DONE` 标记——服务跑完才删文件，
   而 `tvroot.out` 是原地截断重写的，盯着 `DONE` 会读到上一次的旧输出。
