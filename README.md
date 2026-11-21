# TCL Q10G 电视优化 · 杜比视界打通

给国行 TCL Q10G（Android TV 9）做的系统清理 + 播放器建设 + 杜比视界排查。

## 当前状态

| 目标 | 状态 |
|---|---|
| 清理预装广告（停用 7 个包） | ✅ 完成，可回滚 |
| Kodi 21.3 + JellyCon 读 Jellyfin 库 | ✅ 完成，68 部影片 |
| Kodi 中文界面（无方块） | ✅ 完成 |
| Nova 直连 NAS/SMB 播片 | ✅ 完成 |
| 电视端临时 root | ❌ 常规路径全部无效，只剩 fastboot 刷机 |
| **电视端点亮杜比视界** | ⚠️ **未完成**，根因已定位 |

## 核心结论

电视硬件**完全支持** DV（`OMX.MS.DOLBY_VISION.Decoder` + `kdrv_dolby_vision.ko`），
但 Android 显示接口对第三方 App **只暴露 SDR**（`supportedColorModes [0]`），
播放器据此判定"电视不支持 DV"而自动降级成普通 HEVC 解码 → 电视不弹 DV 标志。

Kodi 端的所有 DV 设置项**本来就是正确的**（`allowedhdrformats=0,1` 即"允许全部 HDR 格式"），
调它们没有意义。

下一步优先做：**Nova → 首选项 → 视频 → 杜比视界模式 = 强制**，
以及**评估走已有的 `cpufreestyle/dvpack` 打包链路**（在 Mac 侧重封装成规范 P5 流）。

## 文档

| 文件 | 内容 |
|---|---|
| [docs/HANDOFF.md](docs/HANDOFF.md) | **完整交接文档** —— 设备信息、凭据、已完成工作、DV 排查全过程、踩坑记录 |
| [docs/INSTALL-GUIDE.md](docs/INSTALL-GUIDE.md) | 从零复现全部安装步骤 |
| [docs/DV-DEBUG.md](docs/DV-DEBUG.md) | 杜比视界排查详细记录与证据链 |
| [docs/ROOT-HOWTO.md](docs/ROOT-HOWTO.md) | 临时 root 可行性排查（结论：只能 fastboot，风险自担） |
| [artifacts/MANIFEST.md](artifacts/MANIFEST.md) | 二进制资源清单（版本 / 来源 / SHA-256） |

## 资源包（APK / 字体 / skin）

仓库只放文本：文档、配置、脚本。**APK、中文字体、改好的 skin 太大且属第三方产物，走 Release 分发**：

**[⬇️ v1.0-assets 资源包](https://github.com/cpufreestyle/tcl-q10g-tv-opt/releases/tag/v1.0-assets)**

| 附件 | 大小 | 内容 |
|---|---|---|
| `tcl-q10g-apps.zip` | 135MB | Kodi 21.3 Omega / Kodi 19.4 / Nova 6.6.5 / Just Player 0.217，全 armeabi-v7a + `SHA256SUMS.txt` |
| `tcl-q10g-kodi-skin-fonts.zip` | 72MB | Noto Sans CJK SC 字体、改好字体的 Estuary skin（252 文件）、guisettings 样本、`dv-diagnose.sh`、JellyCon 插件包 |

校验和与每个 APK 的用途见 [artifacts/MANIFEST.md](artifacts/MANIFEST.md)。资源包内**不含任何凭据**。

## 目录

```
artifacts/apk/         Kodi 21/19、Nova 6.6.5、Just Player 安装包（*仅本地 / Release*）
artifacts/configs/     guisettings.xml 修改样本
artifacts/fonts/       提取出的中文字体（Noto Sans CJK SC）（*仅本地 / Release*）
artifacts/screenshots/ 全流程截图（*仅本地*）
artifacts/scripts/     诊断脚本
jellyfin-addon/        JellyCon 插件文件与配置
kodi-font/skin.estuary/ 替换中文字体后的完整 skin（*仅本地 / Release*）
tv-backup-192.168.1.16/ 电视原始状态备份（回滚用）
```

带 `*` 的目录被 `.gitignore` 排除，内容见 Release 资源包。

## 关键凭据位置

见 `docs/HANDOFF.md` §1 的凭据表。

> 电视系统自带搜狗 TV 输入法会拦截 `adb shell input text`，
> 输入前需 `adb shell ime disable com.sohu.inputmethod.sogou.tv/.SogouIME`。
