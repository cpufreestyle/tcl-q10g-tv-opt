# 二进制资源清单（MANIFEST）

这些文件体积大，**不放进 git**，随 GitHub Release **`v1.0-assets`** 分发：

| Release 附件 | 内容 |
|---|---|
| `tcl-q10g-apps.zip` | 4 个 APK（Kodi 21 / Kodi 19 / Nova / Just Player） |
| `tcl-q10g-kodi-skin-fonts.zip` | 中文字体、改好的 Estuary skin、guisettings 样本、诊断脚本、JellyCon 插件包 |

下载：<https://github.com/cpufreestyle/tcl-q10g-tv-opt/releases/tag/v1.0-assets>

> 为什么要打包而不入库：APK 与字体本身已是压缩/二进制格式，进 git 会让仓库永久背上 ~230MB，
> 且 APK 属于第三方版权产物，用 Release 分发更合适（可随时替换、删除）。

## APK

| 文件 | 版本 | 用途 | SHA-256 |
|---|---|---|---|
| `kodi21-omega-armv7a.apk` | Kodi 21.3 Omega（kodinerds 构建） | 主力播放器 + JellyCon | `b93a7e3d1dc878540daacf17c634753daa5331b87cc2963c74d171d7a19bc762` |
| `kodi19-matrix-armv7a.apk` | Kodi 19.4 Matrix | 备用（DV 兼容性对照测试） | `d8fb063bf75a7db6ca0b095012583be10d69a4ae401dfabc3c28fc979649fdeb` |
| `nova-6.6.5-armv7a.apk` | Nova Video Player 6.6.5 | 直连 SMB/NAS 主力 | `9fb146566d8fb70ec5ed03ea180aa10abf294eea7a52a4eafc17634eb20e7143` |
| `Just.Player.v0.217.apk` | Just Player 0.217 | 轻量对照测试（ExoPlayer 系） | `231cae9e3d8e0b0be74dc5fc541086af6bf33d46aea3493e890ddfa7d7b04b54` |

均需 **armeabi-v7a（32 位）** —— Q10G 的 ABI 只有 32 位，arm64 包装不上。
电视端 ADB 装包被封，安装方法见 `docs/INSTALL-GUIDE.md` §1（借当贝 APK 管理器）。

## 字体

| 文件 | 说明 | SHA-256 |
|---|---|---|
| `NotoSansCJK-Regular.ttc` | 从电视 `/system/fonts/` 原样拉出，全量 TTC（含 SC/TC/JP/KR） | `aea63eb09eb66980e12511d9502bd9a3fc030ab8ae319afb9d43d2cc4bfbe494` |
| `NotoSans-Regular.ttf` | 从上面 TTC 抽出的 **index 2 = Noto Sans CJK SC**（16MB，CFF） | `874a4200dee0ecba04a3d6647953705e046b0c48df3dedf4067f73469c7b3e4c` |

Kodi 必须用抽出来的 `.ttf`，直接丢 `.ttc` 进去不生效（原因见 `docs/HANDOFF.md` §2.4）。

## 其它

- `kodi-font/skin.estuary/` —— 替换字体后的完整 skin，252 个文件，可直接整目录推到
  `.../.kodi/addons/skin.estuary/`
- `artifacts/configs/kodi-guisettings*.xml` —— 改前 / 改后的 `guisettings.xml` 样本
- `artifacts/scripts/dv-diagnose.sh` —— 播 DV 时抓解码日志
- `jellyfin-addon/` —— JellyCon 插件源码与配置样本（**不含** `auth.json`、`qc_*.txt` 等令牌文件）

> 凭据一律不进仓库、也不进 Release。明文凭据只在本地 `CREDENTIALS.local.md`。
