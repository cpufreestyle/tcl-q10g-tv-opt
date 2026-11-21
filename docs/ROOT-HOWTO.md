# 临时 Root 排查记录

目标：给 TCL Q10G（Android 9 / SDK 28 / MTK m7642）搞到 root，用于：
1. 直接改播放器配置、装 Magisk 类模块
2. 让第三方 App 拿到 DV 解码器通道（配合 `docs/DV-DEBUG.md` 的根因）

**结论：常规路径全部不可行。唯一有希望的是 fastboot 刷机（需 USB 线 + 官方固件/解锁镜像）。**

---

## 一、基础条件判定

```bash
adb -s 192.168.1.16:5555 shell 'getprop ro.debuggable; getprop ro.secure;
                                 getprop ro.build.type; getprop ro.boot.flash.locked;
                                 getprop ro.boot.verifiedbootstate; getenforce'
```

| 属性 | 值 | 含义 |
|---|---|---|
| `ro.debuggable` | `0` | 非 userdebug，**adb root 不可能** |
| `ro.secure` | `1` | 生产版本 |
| `ro.build.type` | `user` | user build |
| `ro.boot.flash.locked` | （空） | **未锁定** |
| `ro.boot.verifiedbootstate` | `orange` | **Bootloader 已解锁 / 校验未通过** |
| `ro.boot.bootstate` | （空） | — |
| SELinux | `Enforcing` | 强制模式 |

### 关键推论

`ro.boot.verifiedbootstate=orange` + `flash.locked` 为空 → **Bootloader 处于解锁状态**。
这意味着 fastboot 可以刷写任意分区，是**唯一现实的 root 路径**。

但 `user` build 意味着：即使解锁 bootloader，也**没有** `adb root`，
必须刷入第三方 recovery + Magisk，或直接刷改固件。

---

## 二、已尝试且失败的路径

### 2.1 adb root

```bash
$ adb -s 192.168.1.16:5555 root
adbd cannot run as root in production builds
```

### 2.2 重启 adbd（shell 无权限）

```bash
$ adb shell setprop ctl.restart adbd
setprop: failed to set property 'ctl.restart' to 'adbd'
```

### 2.3 adb remount

```bash
$ adb remount
Not running as root. Try "adb root" first.
```

### 2.4 系统分区只读

```
/dev/block/mmcblk0p23 on /vendor type ext4 (ro,seclabel,...)
```

`/system` 未出现在可写列表。

### 2.5 setuid 二进制 —— 全部无效

扫描结果（`find /system /vendor -perm -4000`）：

| 文件 | 权限 | 结果 |
|---|---|---|
| `/vendor/bin/sitadebug` | `-rwsr-x---` root:shell | ❌ 需授权证书（见下） |
| `/vendor/bin/fast_connect` | `-rwsr-x---` root:shell | ❌ Permission denied |
| `/vendor/bin/hostapd_cli` | `-rwsr-x---` root:shell | ❌ 无可用提权路径 |
| `/vendor/bin/iwpriv_wifi_operation` | `-rwsr-x---` root:shell | ❌ 同上 |
| `/vendor/bin/dhcp6c.script` / `dhcp6cPD.script` | setuid | ❌ 仅 DHCP 场景可用 |

> `/vendor/bin/busybox` 是 `root:shell` 但**无 setuid 位**，无法提权。

### 2.6 sitadebug（MTK 工程后门）—— 最有希望但差一步

这是**唯一真正接近成功的路径**。`sitadebug --help` 原文：

```
usage: sitadebug [UID[,GID[,GID2]...]] [COMMAND [ARG...]]
Switch to WHO (default 'root') and run the given command (default sh).

usage: sitadebug install
usage: sitadebug -i
You can enter the above two commands to install the certificate to the Terminal.
The next time you use it, you don't need to insert a usb drive,
but simply enter the sitadebug command to get permission.

usage: sitadebug debug [ciphertext]
usage: sitadebug -d [ciphertext]
You can enter the above two commands to switch root.
...
the above command can be used to input ciphertext through the serial port,
and the root authority can be obtained after authentication.
```

实际执行：

```bash
$ adb shell /vendor/bin/sitadebug -d
Sitadebug version: 3.0
main version is: V8-T652T01-LF1V431
The mac address is: 2c:e0:32:4e:85:1a
Certificate application start time:0. System time:1795278659.
Certificate application end time:0.
Certificate movement model:. Certificate mac:
sitadebug can't execute: Permission denied!
```

**分析**：
- 它确实进入了认证流程，输出「Certificate application start/end time:0」——
  说明它去找一份**厂商签发的授权证书**（有效期 0 = 没找到）
- 二进制内含完整 OpenSSL 栈 + `PKCS7`/`CMS`/`X509` 符号 → 密文是**RSA 签名的 PKCS7 数据**
- 需要 `/system/build.prop` 里的 sita 授权配置 + `sitatvservice`（`/vendor/tvos/bin/sitatvservice`）配合
- `init.svc.sitatvservice` 当前为 `stopped`，但 `start sitatvservice` 报 `must be root` —— **死循环**

**绕过密文的可能性**：证书由 MTK/TCL 签发，密文可能硬编码在固件某处或随工程包下发。
可继续尝试的方向：
- 在固件分区里搜 sita 证书（需 fastboot 或刷机后查）
- 抓取 `sitatvservice` 的 IPC 协议（它是本地 socket 服务）

### 2.7 run-as

```bash
$ adb shell run-as org.courville.nova
run-as: package not debuggable: org.courville.nova
```

所有第三方 App 均非 debuggable。

---

## 三、唯一现实路径：Fastboot 刷机

### 前提条件（已满足 ✓）

- ✅ Bootloader 已解锁（`verifiedbootstate=orange`）
- ✅ `fastboot` 工具可用（`/opt/homebrew/bin/fastboot`）

### 缺失条件

- ❌ **USB 数据线**（fastboot over network 未启用，`reboot bootloader` 后无线 fastboot 不起）
- ❌ **匹配的固件/镜像**（解锁镜像 或 带 root 的 custom ROM）
- ❌ 明确的解锁流程（MTK m7642 平台的 TCL 具体方案）

### 实施步骤（待 USB 线接入）

```bash
# 1. 电视关机 → 开机时按住 音量- + 电源（MTK/TCL 组合键，视机型）
#    或从已开机的状态：
adb reboot bootloader

# 2. USB 连接 Mac，确认 fastboot 识别
fastboot devices
fastboot getvar unlocked            # 应为 yes
fastboot getvar current-slot         # A/B 分区检查
fastboot getvar product

# 3. 刷入 Magisk（推荐，保留原系统）
fastboot flash boot magisk_patched_boot.img
fastboot reboot
# 首次开机 Magisk App 里 "修补" 一次，或直接 adb shell su

# 4. 或刷第三方 Recovery
fastboot flash recovery twrp_xxx.img
fastboot reboot
```

### ⚠️ 风险提示

- **变砖风险**：TCL MTK 平台的 fastboot 分区布局与解锁流程不公开，
  盲刷可能导致无法开机，需拆机短接或专用工具救砖
- **保修**：解锁 bootloader 通常会使厂商保修失效
- **DRM**：部分 TV 平台的 Widevine L1 会因 bootloader 解锁降级为 L3
  （ Kodi/Nova 本地播放不受影响，仅影响 Netflix 等 DRM 平台）

---

## 四、给 DV 问题的替代方案（无需 root）

既然 root 不可得，DV 的解决应回到播放器内部开关：

1. **Nova → 首选项 → 视频 → 杜比视界模式 = 强制**（详见 `docs/DV-DEBUG.md` §5）
   —— Nova 内置 `DOVI_MODE_FORCE`，正是用来绕过 `displaySupportsDoVi` 检测的
2. **取消「优先使用另外的视频播放器」**
3. 若仍不行 → 走 `cpufreestyle/dvpack` 链路，把 DV profile 协商挪到 Mac 端

---

## 五、当前电视状态（需人工恢复）

排查过程中执行了 `adb reboot bootloader`，电视进入 fastboot 后
**无线 fastboot 未启用**（`fastboot devices` 无输出），导致无法用 adb 拉回正常启动。

**恢复方法（任选其一）**：

1. **物理断电重启**（最简单）：拔电源线等 10 秒再插上
2. 若电视有实体电源键：长按电源键 10 秒强制重启
3. 接 USB 线让 Mac 用 `fastboot reboot` 拉回：
   ```bash
   fastboot devices && fastboot reboot
   ```

> 恢复后需重新开启「无线调试」并 `adb connect 192.168.1.16:5555`。
> **注意：以后如需进入 fastboot，务必先确认无线 fastboot 或备好 USB 线。**

---

## 六、结论速查

| 路径 | 可行性 |
|---|---|
| `adb root` | ❌ user build，永久不可能 |
| `adb remount` | ❌ 需 root |
| setuid busybox | ❌ 无 setuid 位 |
| setuid 厂商工具 | ❌ 无可用提权逻辑 |
| `sitadebug` 后门 | ⚠️ **最接近**，缺厂商授权证书 + sitatvservice 需 root |
| `run-as` | ❌ 无 debuggable 包 |
| Magisk via fastboot | ✅ **可行**，需 USB 线 + 固件 + 承担变砖风险 |
| 刷第三方 ROM | ⚠️ 同上，风险更高 |

**优先级建议**：先走「无需 root」的 Nova 强制 DV 模式路线（成本几分钟），
fastboot 刷机留作最后手段。
