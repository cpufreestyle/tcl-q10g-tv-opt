# TCL Q10G 电视优化与杜比视界打通 — 交接文档

> 项目周期：2026-11-21 ~ 2026-11-22
> 目标设备：TCL Q10G（Android TV，国行固件，192.168.1.16）
> 核心诉求：**在电视端直接观看杜比视界（Dolby Vision）**，并顺带清理电视预装广告

---

## 0. 一句话现状

> 最后一次更新：2026-11-22 01:00

电视端 **Kodi + JellyCon + Nova 双播放器链路已全部打通**，中文界面完美，NAS 直连 SMB 播片正常；
**杜比视界仍未点亮**，根因已定位到"电视显示接口只向第三方 App 暴露 SDR"，
最佳解法不在本仓库，而在已有的 `cpufreestyle/dvpack` 打包链路（见 §6）。

**当前进度（接手从这里开始）**：

| 事项 | 状态 |
|---|---|
| 电视重启后 ADB | ✅ 已恢复（`adb devices` 显示 `192.168.1.16:5555 device`） |
| 临时 root | ❌ 常规路径全部无效，只剩 fastboot 刷机（见 §3.6 / `docs/ROOT-HOWTO.md`） |
| Nova「杜比视界模式 → 强制」 | 🟡 已进入首选项界面，leanback 磁贴不认 `input tap`，需 DPAD 导航 |
| 电视自带播放器能否点亮 DV | ⬜ **最高优先级，尚未验证**（这一步决定后面走哪条路） |

---

## 1. 设备与网络拓扑

| 项目 | 值 |
|---|---|
| 电视型号 | `tcl_m7642`（TCL Q10G） |
| 系统 | Android 9 / SDK 28 / `PPR2.180905.006.A1` |
| 固件版本 | `V8-T652T01-LF1V431`（`sitadebug` 自报） |
| Bootloader | **已解锁**（`ro.boot.verifiedbootstate=orange`，`ro.boot.flash.locked` 为空） |
| Root | 无。`ro.build.type=user` / `ro.secure=1` / `ro.debuggable=0`，SELinux `Enforcing` |
| ABI | `armeabi-v7a`（32 位） |
| 电视 IP | `192.168.1.16` |
| ADB | `adb connect 192.168.1.16:5555`（电视端需开启无线调试） |
| Launcher | `com.tcl.cyberui/.MainActivity` |
| Jellyfin | `192.168.1.68:8096`（Docker，跑在 Windows NUC 上） |
| Windows 主机 | `192.168.1.68`，NetBIOS 名 `DH-NUC9`，工作组 `WORKGROUP` |
| SMB 共享 | `192.168.1.68` 上有 `movie2`、`Users`、`C$`/`D$`/`E$`/`F$`、`ADMINS`、`DevelopmentFiles` |
| 片库路径 | `movie2/` 下即 Jellyfin「电影2」库，DV 片源在此 |

### 凭据（重要，接手必读）

> 明文凭据见仓库根目录的 `CREDENTIALS.local.md`（已被 `.gitignore` 排除，不随仓库分发）。
> 下面是账号角色与用途说明：

| 服务 | 用户名 | 密码 | 备注 |
|---|---|---|---|
| Jellyfin | `root` | 见 CREDENTIALS.local.md | 隐藏管理员，**唯一存在的账号** |
| Jellyfin | `kodi` | 见 CREDENTIALS.local.md | 接手时新建的普通账号，Kodi 免密登录用的就是它 |
| Windows SMB | 邮箱形式用户名 | 见 CREDENTIALS.local.md | Nova 直连网络共享用 |

> Jellyfin 的 root 原密码是**不可逆哈希**，无法找回、也无法用管理员令牌重置
> （改密接口强制校验当前密码）。如果 `<JELLYFIN_PW>` 失效，只能重新用 Quick Connect 授权拿令牌，
> 再用令牌新建账号——不要试图破解哈希。

---

## 2. 已完成的工作

### 2.1 完整备份（可回滚）

位置：`tv-backup-192.168.1.16/`

| 文件 | 内容 |
|---|---|
| `packages_all.txt` | 全部已安装包 |
| `packages_disabled.txt` | 停用前状态 |
| `packages_user.txt` | 用户应用列表 |
| `build_props.txt` | 系统构建属性 |
| `settings_secure.txt` / `settings_global.txt` | 系统设置快照 |
| `current_launcher.txt` | 默认桌面 |

> 停用广告包前已完整备份，随时可 `pm enable` 还原。

### 2.2 去广告（停用 7 个预装包）

用 `pm disable-user --user 0 <pkg>` 停用：

```
com.tcl.bootadservice     com.tcl.useragreement    com.tcl.bi
com.tcl.wholenetsearch    com.tcl.tshop            com.tcl.gamecenter
com.tcl.common.weather
```

**未动** `com.tcl.c2dm.client`——它与系统共享 `android.uid.system`，停用会导致系统级崩溃。

### 2.3 Kodi 21.3 Omega（kodinerds 版）

- 安装包：`artifacts/apk/kodi21-omega-armv7a.apk`
- **国行 TCL 封锁 ADB 安装**（`Get install_switch_flag: 0`），`pm install` / `cmd package install` /
  `install-create` / `INSTALL_PACKAGE` intent 全部失败。详见 §5 绕过方法。
- 已配置 JellyCon 插件，中文界面完美，片名正常显示。

### 2.4 中文化（踩坑记录，务必先读）

**问题**：装了 `resource.language.zh_cn` 语言包后，界面所有中文显示成方块「□□」。

**根因**：Estuary skin 的字体文件在 **APK 内部只读**，且不含 CJK 字形。
Kodi 的 `userdata/fonts/` 覆盖机制对 Estuary **无效**（试过，不生效）。

**唯一有效解法**：

1. 从电视 `/system/fonts/NotoSansCJK-Regular.ttc` 提取简体中文子字体：
   ```python
   from fontTools.ttLib import TTCollection
   ttc = TTCollection('NotoSansCJK-Regular.ttc')
   ttc.fonts[2].save('NotoSans-Regular.ttf')   # index 2 = Noto Sans CJK SC
   ```
   产物：`artifacts/fonts/NotoSans-Regular.ttf`（16MB，CFF 格式，Kodi FreeType 可用）
2. 解包完整 skin 到本地，替换字体：
   ```bash
   unzip -q kodi-base.apk 'assets/addons/skin.estuary/*' -d kodi-skin-extract
   # 用 NotoSans-Regular.ttf 覆盖 skin.estuary/fonts/ 下的
   # NotoSans-Regular.ttf / NotoMono-Regular.ttf / Roboto-Thin.ttf
   ```
3. 推送到电视 `.../.kodi/addons/skin.estuary/`（252 个文件，8.8MB）
4. 修改 `guisettings.xml`：
   ```xml
   <setting id="locale.language">resource.language.zh_cn</setting>
   <setting id="locale.country">China</setting>
   <setting id="locale.use24hourclock">true</setting>
   ```

> **重要**：改 `guisettings.xml` 必须先 `am force-stop` Kodi，再 push，再启动。
> Kodi 运行中会把内存里的旧值写回文件，覆盖你的修改。

> 修改后的 skin 副本保留在 `kodi-font/skin.estuary/`，可直接重新推送。

### 2.5 JellyCon（Kodi 的 Jellyfin 插件）

- 仓库源：`http://kodi.jellyfin.org/py3/repository.jellyfin.kodi.zip`
- **必须删除官方 `plugin.video.jellyfin`**，只留 `plugin.video.jellycon`
  —— 两者同时存在会弹出冲突的登录框，登录永远失败。
- 免密登录原理：JellyCon 把令牌存在
  `.../.kodi/userdata/addon_data/plugin.video.jellycon/auth.json`，格式：
  ```json
  { "kodi": { "token": "<accessToken>", "user_id": "<userId>" } }
  ```
- 服务器配置在同目录 `settings.xml`：`server_address=http://192.168.1.68:8096`、`username=kodi`

### 2.6 Nova Video Player 6.6.5（直连 NAS 的主力）

- 安装包：`artifacts/apk/nova-6.6.5-armv7a.apk`
- 选择理由：该版本更新日志专门针对 **Dolby Vision profile 5**、改进 DV 解码器选择、加速 SMB 发现；
  支持直连 SMB / UPnP / HTTP 流，界面比 Kodi 现代。
- 已实测：自动扫描到 `DH-NUC9` → 登录 → 看到 `movie2` 等共享 → 播放 DV 片源正常（画面能出）。
- **它绕开了 Jellyfin**，不依赖 Jellyfin 容器是否存活。

---

## 3. 杜比视界：完整排查链与根因

### 3.1 排查过程中被推翻的错误结论（重要，别重复踩）

| 一度以为 | 实际情况 | 证据 |
|---|---|---|
| 国行固件不开放 DV 给第三方 App | **错**，电视有完整 DV 硬解 | `/vendor/etc/media_codecs.xml` 列出 `OMX.MS.DOLBY_VISION.Decoder`（`video/dolby-vision`）及 AVC-DV / AV1-DV 变体，含 `.secure` 版本 |
| Kodi 的 `allowedhdrformats=0,1` 没包含 DV | **错**，默认就是"允许全部" | Kodi APK 内源码注释：`<option label="39200">0</option> <!-- Dolby Vision -->`、`<option label="39201">1</option> <!-- HDR10+ -->`、`<default>0,1</default> <!-- Allow all HDR formats -->` |
| `supportedColorModes [0]` 说明电视不支持 HDR | **错**，这是第三方 App 可见能力，不代表硬件 | 硬件有 `kdrv_dolby_vision.ko` 驱动 + DV 解码器 |
| Jellyfin 转码丢了 DV | **错**，全程 DirectStream 无转码 | `PlayState.PlayMethod=DirectStream`，`TranscodingInfo=null` |

### 3.2 真正根因（已定位）

电视显示接口对第三方 App 只暴露 SDR：

```
dumpsys display →
  mActiveColorMode=0
  supportedColorModes [0]        ← 仅 SDR，无 HDR(2)/DV
  HdrCapabilities@4a3d456a
```

而 Nova 判断能否上 DV 用的是 `displaySupportsDoVi`（读显示 HDR 能力）。
电视报"不支持" → Nova 在 **AUTO 模式**下自动降级，把 DV 流当普通 HEVC 播，
**永远不会请求 `video/dolby-vision` 解码器** → 电视不弹 DV 标志。

### 3.3 片源信息（全部 DV，无一例外）

```
容器: mp4
编码: hevc, Profile Main 10
分辨率: 3840x2160 (4K)
DV: VideoRangeType=DOVI, DvProfile=5, DvLevel=9
BL 基底层: 无（BlPresent=0）—— 单层 DV
```

DV Profile 5 是**单层 DV（无兼容基底层）**，比 Profile 8 更依赖解码器显式声明 DV。

### 3.4 已尝试且无效的方案

- Kodi 全部 DV 相关设置项（`winsystem.ishdrdisplay`、`allowedhdrformats`、`convertdovi`）——**本来就是对的**
- JellyCon 强制直连（`force_transcode_h265=false`）——本来就直连
- Nova 播放 DV 片源——能播，但电视不弹标志

### 3.5 下一步（未完成，按优先级）

1. **Nova 首选项 → 视频 → 「杜比视界模式」** 设为 **「强制」（DOVI_MODE_FORCE）**，
   跳过 `displaySupportsDoVi` 检测，强制请求 DV 解码器。
   - 状态：**进行中**。选项位置已定位（当前值「自动」）。
   - ⚠️ **验证过的坑**：Nova 主界面是 leanback 骨架，首选项是**横向磁贴**（`网络 / 首选项 / 传统界面 / 帮助`），
     `input tap` 点磁贴**不会移动焦点**，屏幕无任何变化。
     必须用 `input keyevent DPAD_RIGHT/DOWN` 把焦点移过去再 `DPAD_CENTER`。
   - 当前界面快照：`shots/nova1.png`
   - 同时建议**取消勾选「优先使用另外的视频播放器」**——它会让 Nova 把播放交给外部
     App（Kodi 等），切断自己的 DV 解码链路。
2. **用电视自带播放器播一个 DV 片源**（**分水岭**）：
   - 自带播放器能点亮 → 是第三方 App 的通道问题，§6 的 dvpack 路线可走
   - 自带播放器也不亮 → 电视 DV 侧/片源封装问题，先查电视设置里的 HDR/DV 开关
3. **改走 `cpufreestyle/dvpack` 链路**（更可靠，见 §6）
4. 若 1、2、3 都不行，则基本可确认是国行固件对第三方 DV 的限制，放弃第三方播放 DV

### 3.6 关于临时 root（结论：做不到）

完整排查记录见 **`docs/ROOT-HOWTO.md`**（含每一步的原始报错）。摘要：

| 路径 | 结果 |
|---|---|
| `adb root` | ❌ `adbd cannot run as root in production builds` |
| `adb remount` | ❌ 需先 root |
| setuid 二进制（`busybox` / `fast_connect` / `hostapd_cli`） | ❌ 无可用提权逻辑 |
| `sitadebug`（MTK 工程后门，setuid root） | ⚠️ **最接近**：确实进了认证流程，但要求 **MTK/TCL 签发的 PKCS7 授权证书**，且 `sitatvservice` 启动本身要 root（死循环） |
| `run-as`（读 App 私有配置） | ❌ 所有第三方 App 均 `not debuggable`（Nova 的 `shared_prefs` 因此读不到） |
| Magisk via fastboot | ✅ 理论可行（bootloader 已解锁），但需 **USB 线 + 匹配 boot 镜像**，有变砖风险 |

> **踩过的坑**：为测试 fastboot 执行了 `adb reboot bootloader`，电视进了 fastboot 而**无线 fastboot 未启用**，
> 远程拉不回来，最后靠**断电重启**恢复。以后要进 fastboot，必须先插 USB 线或确认网络 fastboot 可用。

因此 DV 只能走「应用内开关」或「Mac 侧重封装（dvpack）」两条不需要 root 的路。

---

## 4. 目录结构

```
.
├── README.md                    ← 项目速览
├── CREDENTIALS.local.md         ← 明文凭据（已 gitignore，**不随仓库分发**）
├── .gitignore
├── artifacts/
│   ├── apk/                     ← Kodi 21/19、Nova 6.6.5、Just Player
│   ├── configs/                 ← guisettings.xml 样本（改前/改后）
│   ├── fonts/                   ← 提取出的中文字体 NotoSans-Regular.ttf
│   ├── screenshots/             ← 全流程截图（226 张）
│   └── scripts/                 ← dv-diagnose.sh 等
├── docs/
│   ├── HANDOFF.md               ← 本文件
│   ├── INSTALL-GUIDE.md         ← 复现全部安装步骤
│   ├── DV-DEBUG.md              ← DV 排查详细记录
│   └── ROOT-HOWTO.md            ← 临时 root 可行性排查（结论：只能 fastboot）
├── jellyfin-addon/              ← JellyCon 插件文件与配置
│   ├── jellycon-settings.xml    ← 服务器地址/用户名配置
│   ├── auth.json                ← 免密登录令牌
│   └── *.py                     ← 拉下来的 JellyCon 源码（查阅用）
├── kodi-font/
│   └── skin.estuary/            ← 替换中文字体后的完整 skin（可直接推送）
├── shots/                       ← 调试过程中的临时界面截图（未提交）
├── tv-backup-192.168.1.16/      ← 电视原始状态备份 + 截图
└── .workbuddy/memory/           ← 工作日志
```

---

## 5. 关键技术备忘

### 5.1 国行 TCL ADB 安装封锁的绕过方法

`pm install` 全线失败（`install apk has be disabled from pm by system default`）。
**唯一可行路径**：借当贝市场的 APK 管理器

```bash
# 1. 推送 APK 到电视
adb push app.apk /sdcard/Download/app.apk

# 2. 启动当贝 APK 管理器（它会扫描本地 APK）
adb shell am start -n com.dangbeimarket/.ui.apkmanager.ApkManagerActivity

# 3. 遥控器操作：找到目标 APK → DPAD_UP 高亮「安装应用」→ ENTER
#    注意：当贝自定义对话框对 input tap 坐标不准，必须用方向键 + ENTER

# 4. 系统安装确认页是 Android 原生 PackageInstaller，需 input tap 1850 1015 点「安装」
```

### 5.2 搜狗 TV 输入法会拦截 ADB 文本输入

`adb shell input text` 会把字母转成中文候选（`qm0819` → 「去吗？」）。

**解法**：临时禁用输入法，让 `input text` 走硬件键盘通道：

```bash
adb shell ime disable com.sohu.inputmethod.sogou.tv/.SogouIME
# ... 输入完成后务必恢复：
adb shell ime enable com.sohu.inputmethod.sogou.tv/.SogouIME
adb shell settings put secure default_input_method com.sohu.inputmethod.sogou.tv/.SogouIME
```

### 5.3 Kodi JSON-RPC 不可达

端口 8080 有监听，但局域网与 `adb forward` 均连不上。**改用配置文件直接改设置**
（务必先 force-stop Kodi）。

### 5.4 Jellyfin API 认证格式（12.x）

```python
body = {"Username": "root", "Pw": "<JELLYFIN_PW>"}
headers = {
  "Content-Type": "application/json",
  "Authorization": 'MediaBrowser Client="JellyCon", Device="TCL Q10G", '
                    'DeviceId="q10g-kodi21", Version="1.0.2"'
}
POST /Users/AuthenticateByName
```

旧版 `X-Emby-Authorization` + `Password` 字段会返回 400。

### 5.5 Quick Connect（拿管理员令牌）

```
POST /QuickConnect/Initiate    → 返回 secret + 6 位授权码
GET  /QuickConnect/Connect?Secret=<secret>   → 轮询直到 Authenticated=true
```
拿到 root 的 `AccessToken` 后即可调管理员接口（但**改不了密码**）。

### 5.6 ADB 截图抓不到 DV 播放画面

播放 DV/HDR 时视频走 secure layer，`adb exec-out screencap` 只能拿到 10KB 黑图，
**这是正常现象，不代表电视没画面**。判断播放状态改用：

```bash
adb shell dumpsys media_session | grep "state=PlaybackState"   # 3=PLAYING
adb shell dumpsys SurfaceFlinger | grep -A20 PlayerActivity     # 看 colorSpace / hdr10
```

---

## 6. 强烈建议：改用 `cpufreestyle/dvpack` 打通 DV

仓库：`https://github.com/cpufreestyle/dvpack`（已有，public）

其 README 开篇即描述了同类问题：

> 解决 NUC 上的 Jellyfin 转码（QuickSync 转 4K·10bit·DV）**丢 DV 层、徽标不亮、颜色不对**的问题：
> 打包在 Mac 侧完成，只搬码流不重编码，电视拿到的是带 dvcC/RPU 的规范 P5 流。

**核心思想**：不要让电视端 App 自己处理 DV 的 profile 协商——
在 Mac 侧把片源**重封装**成规范的带 `dvcC`/`RPU` 的 P5 流，电视拿到就是标准 DV。

### 迁移到 Android TV 的思路

dvpack 现在的客户端是 tvOS（`dvplay`，Swift）+ HLS 输出。Android TV 侧要做的：

1. **打包端**：dvpack 的 `pack` / `remux` / `p5` 模块可直接复用（只搬码流，不重编码）。
   输出目标从 HLS 换成 **DASH/CMAF** 或直接 MP4，因为多数 Android 播放器对 DASH 支持更好；
   若走 HLS，电视端需支持 `EXT-X-MAP` + `dvcC` 初始化段。
2. **播放端**：Kodi 的 JellyCon / Nova 都能播 HTTP 直链，但**关键仍是电视端 App 能否点亮 DV**——
   与 §3.2 的根因相同：第三方 App 拿不到 `video/dolby-vision` 解码器。
   → 若 Nova 的「强制 DV 模式」也无效，说明这条路在电视端走不通，
   应改为**用电视自带播放器播 dvpack 推的 HLS/DASH 地址**。
3. **关键前提**：先在电视端用**自带播放器**播一个 DV 片源，确认电视自己能否点亮 DV。
   这是整个项目的分水岭：
   - 自带播放器能点亮 → 第三方 App 的 DV 通道问题，dvpack + 电视自带播放器可解
   - 自带播放器也不亮 → 电视 DV 侧问题，检查电视设置里的 HDR/DV 开关与片源封装

### dvpack 现有 CLI 参考

```bash
python -m dvpack check  <原片.mkv>              # 只探测判定
python -m dvpack init  <pack目录|init.mp4>      # dovi_tool 口径诊断
python -m dvpack pack  <原片.mkv> -o _out/demo --seconds 60
python -m dvpack serve _out/dv_p7_fix          # 起局域网服务
```

---

## 7. 未完成 / 待确认清单

- [ ] **用电视自带播放器播 DV 片源，确认电视自身能否点亮 DV**（**最高优先级 / 分水岭**）
- [ ] **Nova「杜比视界模式」改为「强制」** —— 界面已进到首选项，磁贴需 DPAD 导航（见 §3.5）
- [ ] 取消 Nova「优先使用另外的视频播放器」勾选
- [ ] 若 Nova 强制模式无效 → 评估 dvpack 链路迁移到 Android TV（见 §6）
- [ ] 临时 root：仅在必须改系统分区时才考虑 fastboot + Magisk，需自备 USB 线（见 §3.6）
- [ ] Jellyfin `kodi` 账号是否需要保留/清理
- [ ] Nova 设为开机默认播放器 / `movie2` 加为首页快捷方式
- [ ] JellyCon 在 Kodi 里的媒体库扫描是否需要重建（库名「电影2」中文显示已正常）

---

## 8. 常用命令速查

```bash
# 连接电视
adb connect 192.168.1.16:5555
adb -s 192.168.1.16:5555 shell 'dumpsys display | grep -A15 HdrCapabilities'

# 停用/恢复广告包
adb -s 192.168.1.16:5555 shell 'pm disable-user --user 0 com.tcl.bootadservice'
adb -s 192.168.1.16:5555 shell 'pm enable com.tcl.bootadservice'

# 重启 Kodi 并推送配置
adb -s 192.168.1.16:5555 shell 'am force-stop net.kodinerds.maven.kodi21'
adb -s 192.168.1.16:5555 push <file> /sdcard/Android/data/net.kodinerds.maven.kodi21/files/.kodi/userdata/guisettings.xml
adb -s 192.168.1.16:5555 shell 'monkey -p net.kodinerds.maven.kodi21 -c android.intent.category.LAUNCHER 1'

# 播放状态
adb -s 192.168.1.16:5555 shell 'dumpsys media_session | grep state=PlaybackState'

# 截图（DV 播放时为黑图，属正常）
adb -s 192.168.1.16:5555 exec-out screencap -p > out.png
```

---

## 9. 环境信息

```
电视:   TCL Q10G / tcl_m7642 / Android 9 (SDK 28) / armeabi-v7a
Mac:    darwin，Python 3 + fontTools（pip install fonttools）
工具:   adb、ffmpeg/ffprobe（brew）、uiautomator dump（用于精确定位 UI 控件）
仓库:   git + gh CLI（账号 cpufreestyle 已登录）
```

---

## 10. 变更记录（时间线）

| 时间 | 事件 |
|---|---|
| 11-21 晚 | 备份 → 停用 7 个广告包 → 装 Kodi 21 + JellyCon → 中文界面修复 → 装 Nova 6.6.5 → SMB 直连 NAS → DV 片源可播但不亮标 |
| 11-21 深夜 | DV 根因定位：`supportedColorModes [0]` 仅 SDR，第三方 App 拿不到 `video/dolby-vision` 通道 |
| 11-22 00:2x | 交接文档 / 安装指南 / DV 排查记录落盘；仓库 `cpufreestyle/tcl-q10g-tv-opt` 建立 |
| 11-22 00:4x | 临时 root 排查（`docs/ROOT-HOWTO.md`）：`adb root`、setuid、`sitadebug`、`run-as` 全部无效；测试 fastboot 时 `reboot bootloader` 把电视留在 fastboot |
| 11-22 00:5x | **电视断电重启恢复**；ADB 未自动回连，手动 `adb connect 192.168.1.16:5555` 成功 |
| 11-22 01:0x | 进入 Nova leanback 首选项区域，确认 `input tap` 对磁贴无效、改走 DPAD；本文件同步更新 |

### 下次接手的最短路径

```bash
adb connect 192.168.1.16:5555 && adb devices
# 1) 先用电视自带播放器播 DV 片源 → 看是否亮标（分水岭）
# 2) 再试 Nova 强制 DV：DPAD 导航到 首选项 → 视频 → 杜比视界模式 → 强制
```
