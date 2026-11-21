# 杜比视界（Dolby Vision）排查完整记录

## 结论摘要

**电视硬件完全支持 DV，播放链路无转码，Kodi/Nova 的 DV 设置项全部正确。
问题出在：Android 显示接口对第三方 App 只暴露 SDR，播放器据此判定"电视不支持 DV"而自动降级。**

---

## 一、片源确认

通过 Jellyfin API 遍历全库，所有 DV 片源特征一致：

```
容器:   mp4
编码:   hevc / Main 10
分辨率: 3840x2160 (4K)
DV:     VideoRangeType=DOVI
        DvProfile = 5
        DvLevel  = 9
BL:     DvBlSignalCompatibilityId = 0   ← 单层 DV，无兼容基底层
```

片源路径样例：

```
/media/movie/[风味人间 第五季].Once.Upon.a.Bite.2024.S05.Complete.2160p.WEB-DL.50Fps.DoVi.H265.10bit.AAC-UBWEB/
    [...].2024.S05E07.2160p.WEB-DL.50Fps.DoVi.H265.10bit.AAC-UBWEB.mp4

/movie2/Chefs.Table.Legends.S01.DV.2160p.WEB.h265-GRACE/...
```

> **DV Profile 5 = 单层 DV（无 HDR10 兼容基底层）**。
> P5 比 P8 更依赖解码器**显式声明**走 DV 解码路径，否则会被当普通 HEVC 处理。
> 这是本项目所有绕路的起点。

---

## 二、播放链路确认（排除 Jellyfin 侧）

Jellyfin 会话快照：

```json
{
  "PlayState": {
    "PlayMethod": "DirectStream",     ← 直连，不是 DirectPlay 也不是转码
    "IsPaused": false,
    "PlaybackRate": 1.0
  },
  "TranscodingInfo": null              ← 完全没有转码
}
```

客户端能力声明：

```
DirectPlayProfiles: null
```

**结论：Jellyfin 没有做任何转码，DV 层不会在服务端被剥掉。** 问题不在 Jellyfin。

---

## 三、电视侧能力核查

### 3.1 解码器清单 —— 完整

`/vendor/etc/media_codecs.xml`：

```
OMX.MS.DOLBY_VISION.Decoder             type="video/dolby-vision"
OMX.MS.DOLBY_VISION.Decoder.secure      type="video/dolby-vision"
OMX.MS.AVC.DOLBY_VISION.Decoder         type="video/dolby-vision"
OMX.MS.AVC.DOLBY_VISION.Decoder.secure  type="video/dolby-vision"
OMX.MS.AV1.DOLBY_VISION.Decoder         type="video/dolby-vision"
OMX.MS.AV1.DOLBY_VISION.Decoder.secure  type="video/dolby-vision"
```

支持 4K、tunneled、secure。

### 3.2 内核驱动 —— 存在

```
/vendor/lib/modules/kdrv_dolby_vision.ko
```

### 3.3 显示接口 —— **根因所在**

```
dumpsys display
  mActiveColorMode = 0
  supportedColorModes [0]        ← 只有 SDR(0)，没有 HDR(2)/DV
  HdrCapabilities@4a3d456a
```

**这是整个问题的核心。**

第三方 App 读取 `Display.getHdrCapabilities()` / `getSupportedColorModes()`，
拿到的只有 SDR。播放器据此判断"这台电视不支持 DV"，
于是**在自动模式下主动降级**，不请求 `video/dolby-vision` 解码器，
改用 `OMX.MS.HEVC.Decoder` 硬解 → 电视收到的是普通 HEVC 信号 → **不弹 DV 标志**。

厂商私有驱动（`kdrv_dolby_vision.ko`）只对接自家播放器，标准 Android HDR 接口
没有把 DV 能力暴露给第三方。

---

## 四、Kodi 端设置核查 —— 全部正确，无需修改

从 Kodi APK 内源码提取的设置定义：

```xml
<setting id="videoplayer.allowedhdrformats" type="list[integer]">
    <default>0,1</default>   <!-- Allow all HDR formats -->
    <option label="39200">0</option>   <!-- Dolby Vision -->
    <option label="39201">1</option>   <!-- HDR10+ -->
</setting>
```

当前 `guisettings.xml` 实际值：

| 设置项 | 值 | 判定 |
|---|---|---|
| `winsystem.ishdrdisplay` | `true` | ✅ 正确 |
| `videoplayer.allowedhdrformats` | `0,1` | ✅ 正确（= 允许全部，含 DV） |
| `videoplayer.convertdovi` | `false` | ✅ 正确（保留原始 DV 元数据） |
| `videoplayer.usemediacodec` | `true` | ✅ 正确 |
| `videoplayer.usemediacodecsurface` | `true` | ✅ 正确 |

> **曾经走过的弯路**：以为 `allowedhdrformats=0,1` 不含 DV 而去改它。
> 源码注释明确写着 `0=Dolby Vision`、`1=HDR10+`、默认 `0,1` = 全部允许。**改它是错的。**

kodinerds 官方说明亦印证：

> "By default, the video bitstream is kept intact, so all metadata is kept.
> If you don't want HDR10+, uncheck HDR10+. If you don't want Dolby Vision, uncheck it."

---

## 五、Nova 端 —— 找到可操作开关

Nova APK（`org.courville.nova` 6.6.5）内含完整的 DV 控制逻辑：

```
DOVI_MODE_AUTO
DOVI_MODE_FORCE
DOVI_MODE_OFF
KEY_DOLBY_VISION_MODE
KEY_DISABLE_DOLBY_VISION
preference_dolby_vision_mode
preference_force_dolby_vision
preference_remove_dolby_vision
displaySupportsDoVi / setDoViMode / getDoViMode
video/dolby-vision
CONFIG setColorMode COLOR_MODE_HDR requested
CONFIG HDR dolby vision supported
```

资源字符串：

```
Dolby Vision mode        → 杜比视界模式
Force Dolby Vision       → 强制杜比视界
Disable dolby vision     → 禁用杜比视界
HDR screen capabilities: → HDR 屏幕功能:
UUDolby Vision color profile is not supported. Playing anyway; colors may be incorrect.
```

**UI 现状**：首选项 → 视频 → 「杜比视界模式」= **「自动」**。

这就是问题所在：自动模式下 `displaySupportsDoVi=false`（电视只报 SDR），
Nova 主动降级。

**解法**：改为「强制」（DOVI_MODE_FORCE），绕过能力检测强制请求 DV 解码器。

同时发现另一个隐患：**「优先使用另外的视频播放器」已勾选**——
它会让 Nova 把播放交给外部 App（Kodi 等），切断自己的 DV 解码链路。**必须取消勾选。**

### 自动化难点

Nova 首选项面板用 `input tap` 点击**无响应**（面板是自绘的 Android View）。
可行手段：`uiautomator dump` 拿控件 bounds → DPAD 导航 → ENTER。

已验证 uiautomator 可用：

```bash
adb -s 192.168.1.16:5555 shell uiautomator dump /sdcard/wd.xml
adb -s 192.168.1.16:5555 pull /sdcard/wd.xml /tmp/wd.xml
```

难点在于面板内容会跟随焦点自动滚动，导致"当前行"与"焦点项"错位，
需要边 dump 边下移做闭环检测（每步 dump → 检查是否出现「杜比视界」→ 命中即停）。

---

## 六、播放时的图层证据

SurfaceFlinger 快照（Nova 播放中）：

```
SurfaceView ... PlayerActivity
  size = 3840x2160          ← 4K
  isSecure = 1             ← secure layer
  hdr10 = 1                ← 显示控制器报告 HDR10 激活
  dataspace = BT2020 SMPTE_170M   ← 广色域
  color format = 0x40002900
```

说明 Nova 确实按 HDR 源在处理，色彩链路是通的，**但没有走 DV 解码器**。

> `adb exec-out screencap` 在播放 DV 时只有 ~10KB 黑图（secure layer 抓不到），
> 这不代表电视没画面。

---

## 七、已排除的错误结论汇总

| 一度以为 | 实际情况 | 证据 |
|---|---|---|
| 国行固件封锁第三方 DV | **错**，解码器齐全 | `media_codecs.xml` 中 `OMX.MS.DOLBY_VISION.Decoder` 等 6 个变体 |
| Kodi `allowedhdrformats` 没含 DV | **错**，默认就是全允许 | APK 内源码注释 `<default>0,1</default> <!-- Allow all HDR formats -->` |
| `supportedColorModes [0]` = 电视无 DV 硬件 | **错**，那是第三方可见能力 | 硬件有 `kdrv_dolby_vision.ko` |
| Jellyfin 转码丢 DV | **错**，全程 DirectStream | `TranscodingInfo=null` |
| 海康客户端能开 DV | **错**，用户实测也不行 | 同属第三方 App，同样拿不到 DV 通道 |

---

## 八、下一步路线

### 路线 A：Nova 强制 DV 模式（成本最低，先做）

1. 首选项 → 视频 → 杜比视界模式 = **强制**
2. 取消勾选「优先使用另外的视频播放器」
3. 播放 `Chefs.Table.Legends.S01.DV.2160p`，肉眼确认电视右上角 DV 标志

### 路线 B：dvpack 打包链路（最可靠）

已有仓库 `cpufreestyle/dvpack`，其 README 开篇：

> 解决 NUC 上的 Jellyfin 转码（QuickSync 转 4K·10bit·DV）**丢 DV 层、徽标不亮、颜色不对**的问题：
> 打包在 Mac 侧完成，只搬码流不重编码，电视拿到的是带 dvcC/RPU 的规范 P5 流。

思路：把 DV 的 profile 协商从电视端挪到 Mac 端。
dvpack 的 `pack` / `remux` / `p5` 模块只搬码流不重编码，可直接复用；
需把输出从 HLS 调整为 DASH/CMAF 或 MP4（Android 播放器对 DASH 支持更好）。

⚠️ 但**路线 B 仍受制于路线 A 的结论**：若第三方 App 根本拿不到 DV 解码器，
那么无论流是原片还是重封装，电视端都一样不解 DV。
→ 因此**必须先确认路线 A 是否走通**。

### 路线 C：电视自带播放器（验证基准，必须先做）

**用电视自带播放器播一个 DV 片源**（通过 U 盘或电视能识别的共享路径），
看是否弹 DV 标志。

- **弹了** → 电视 DV 硬件与设置正常，问题是第三方 App 的 DV 通道 → 路线 A/B 有希望
- **不弹** → 电视 DV 侧问题（固件/设置/片源封装）→ 检查电视 HDR/DV 开关与片源 dvcC 封装

**这是整个项目的分水岭，建议优先做。**

---

## 九、诊断脚本

`artifacts/scripts/dv-diagnose.sh` —— Jellyfin 恢复后播放时运行，直接判断
Kodi 用的是 HEVC 还是 DV 解码器。

核心命令：

```bash
# 播放期间抓活动解码器
adb -s 192.168.1.16:5555 shell dumpsys media.codec | grep -iE "dolby|dovi|dvhe|hevc"

# 色彩能力
adb -s 192.168.1.16:5555 shell dumpsys display | grep -A15 HdrCapabilities

# 图层
adb -s 192.168.1.16:5555 shell dumpsys SurfaceFlinger | grep -A20 PlayerActivity
```

> 注意 `dumpsys media.codec` 在这台电视上**不工作**（无输出）。
> `dumpsys media.player` 可用。
> 电视的 logcat 会被 SELinux audit 日志刷满，
> 抓日志前先 `adb logcat -c`，并用 `grep -vE "audit\(|avc:|type=1400"` 过滤噪音。
