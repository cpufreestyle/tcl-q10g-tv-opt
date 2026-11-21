# 安装复现指南

从零到可看片，完整步骤。全部在 `192.168.1.16:5555`（TCL Q10G）上验证过。

---

## 0. 前置

```bash
# 电视设置里开启「无线调试」→ 记下 IP:端口
adb connect 192.168.1.16:5555
adb -s 192.168.1.16:5555 shell 'getprop ro.product.model'   # tcl_m7642
```

---

## 1. 备份（务必先做）

```bash
mkdir -p tv-backup-192.168.1.16
adb -s 192.168.1.16:5555 shell pm list packages -f        > tv-backup-192.168.1.16/packages_all.txt
adb -s 192.168.1.16:5555 shell pm list packages -d        > tv-backup-192.168.1.16/packages_disabled.txt
adb -s 192.168.1.16:5555 shell pm list packages -3        > tv-backup-192.168.1.16/packages_user.txt
adb -s 192.168.1.16:5555 shell getprop                   > tv-backup-192.168.1.16/build_props.txt
adb -s 192.168.1.16:5555 shell settings list secure      > tv-backup-192.168.1.16/settings_secure.txt
adb -s 192.168.1.16:5555 shell settings list global      > tv-backup-192.168.1.16/settings_global.txt
adb -s 192.168.1.16:5555 shell 'cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.HOME' \
                                                      > tv-backup-192.168.1.16/current_launcher.txt
```

---

## 2. 停用预装广告（7 个包）

```bash
for p in com.tcl.bootadservice com.tcl.useragreement com.tcl.bi \
         com.tcl.wholenetsearch com.tcl.tshop com.tcl.gamecenter \
         com.tcl.common.weather; do
  adb -s 192.168.1.16:5555 shell pm disable-user --user 0 $p
done
```

⚠️ **不要动** `com.tcl.c2dm.client`——与系统共享 `android.uid.system`，停用会引发系统级故障。

回滚：
```bash
adb -s 192.168.1.16:5555 shell pm enable <pkg>
```

---

## 3. 安装 APK（国行 TCL 绕过封锁）

### 3.1 封锁现象

```bash
adb -s 192.168.1.16:5555 shell pm install -r app.apk
# Failure [INSTALL_FAILED_...]
# logcat: Get install_switch_flag: 0
```

`pm install` / `cmd package install` / `install-create` / `INSTALL_PACKAGE` intent 全部失败。

### 3.2 绕过：借当贝市场 APK 管理器

```bash
adb -s 192.168.1.16:5555 push app.apk /sdcard/Download/app.apk
adb -s 192.168.1.16:5555 shell am start -n com.dangbeimarket/.ui.apkmanager.ApkManagerActivity
```

电视端遥控器操作：

1. 等待扫描完成（会逐目录扫描，可能要 10 秒）
2. 用方向键找到目标 APK（第一行第三个通常是刚推的）
3. 按 **DPAD_UP** 高亮对话框里的「安装应用」→ 按 **ENTER**
   （当贝自定义对话框 `input tap` 坐标不准，必须用方向键）
4. 系统原生安装确认页出现后：
   ```bash
   adb -s 192.168.1.16:5555 shell input tap 1850 1015   # 点「安装」
   ```
5. 验证：
   ```bash
   adb -s 192.168.1.16:5555 shell pm list packages | grep -i nova
   ```

---

## 4. Kodi 21.3 Omega

### 4.1 安装

安装包：`artifacts/apk/kodi21-omega-armv7a.apk`（kodinerds 版，65MB）

> 从 kodinerds 下载需要 POST 表单，参数为
> `c_item[]=download=addons/omega/zip/...Omega.apk`

按 §3.2 安装。

### 4.2 允许未知来源安装插件

```bash
adb -s 192.168.1.16:5555 pull \
  /sdcard/Android/data/net.kodinerds.maven.kodi21/files/.kodi/userdata/guisettings.xml ./gs.xml
# 编辑加入：
#   <setting id="addons.unknownsources">true</setting>
#   <setting id="services.webserver">true</setting>
adb -s 192.168.1.16:5555 shell am force-stop net.kodinerds.maven.kodi21
adb -s 192.168.1.16:5555 push ./gs.xml \
  /sdcard/Android/data/net.kodinerds.maven.kodi21/files/.kodi/userdata/guisettings.xml
```

> **改配置铁律**：先 `am force-stop` → push → 再启动。
> Kodi 运行中会把内存旧值写回文件，覆盖你的修改。

### 4.3 中文字体（关键步骤）

**问题**：装完 `resource.language.zh_cn` 后中文全是方块「□□」。

**根因**：Estuary skin 字体在 APK 内只读且无 CJK 字形，`userdata/fonts/` 覆盖无效。

```bash
# 1. 拉取系统中文字体集合
adb -s 192.168.1.16:5555 pull /system/fonts/NotoSansCJK-Regular.ttc ./NotoSansCJK-Regular.ttc

# 2. 提取简体中文子字体（index 2 = Noto Sans CJK SC）
pip install fonttools
python3 - <<'PY'
from fontTools.ttLib import TTCollection
ttc = TTCollection('NotoSansCJK-Regular.ttc')
ttc.fonts[2].save('NotoSans-Regular.ttf')
PY

# 3. 解包 skin 并替换全部字体
unzip -q kodi-base.apk 'assets/addons/skin.estuary/*' -d kodi-skin-extract
cd kodi-skin-extract/assets/addons/skin.estuary
for f in NotoSans-Regular.ttf NotoMono-Regular.ttf Roboto-Thin.ttf; do
  cp ../../../../NotoSans-Regular.ttf fonts/$f
done

# 4. 推送整个 skin（会覆盖内置同名 skin）
adb -s 192.168.1.16:5555 shell am force-stop net.kodinerds.maven.kodi21
adb -s 192.168.1.16:5555 push kodi-skin-extract/assets/addons/skin.estuary \
  /sdcard/Android/data/net.kodinerds.maven.kodi21/files/.kodi/addons/skin.estuary
```

### 4.4 语言设置

```xml
<setting id="locale.language">resource.language.zh_cn</setting>
<setting id="locale.country">China</setting>
<setting id="locale.use24hourclock">true</setting>
```

改完重启 Kodi，界面即成清晰简体中文。

---

## 5. JellyCon（Jellyfin 插件）

### 5.1 添加仓库

仓库地址：`http://kodi.jellyfin.org/py3/repository.jellyfin.kodi.zip`

> 注意：Kodi 官方仓库里**没有** Jellyfin；SlyGuy 仓库也没有。必须用 Jellyfin 官方仓库。

安装后：
- **删除官方 `plugin.video.jellyfin`**（保留 `plugin.video.jellycon`）
  —— 两者共存会弹冲突登录框，导致登录永远失败。

### 5.2 免密登录（令牌直写）

JellyCon 把令牌存在：
`/sdcard/Android/data/net.kodinerds.maven.kodi21/files/.kodi/userdata/addon_data/plugin.video.jellycon/auth.json`

```json
{
  "kodi": {
    "token": "<kodi 账号的 AccessToken>",
    "user_id": "<kodi 账号的 UserId>"
  }
}
```

同目录 `settings.xml` 配置服务器：
```xml
<setting id="server_address">http://192.168.1.68:8096</setting>
<setting id="username">kodi</setting>
<setting id="force_transcode_h265">false</setting>
```

> 用户名会被输入框截断，建议**直接编辑 settings.xml** 改，不要手打。

---

## 6. Nova Video Player 6.6.5

安装包：`artifacts/apk/nova-6.6.5-armv7a.apk`

选择理由：更新日志专门针对 DV profile 5、改进 DV 解码器选择、加速 SMB 发现；
支持直连 SMB / UPnP / HTTP 流。

安装后：

1. 首次启动授予「照片、媒体文件和文件」权限
2. 左侧 **网络和文件 → 网络** → 自动扫描到 `DH-NUC9`（WORKGROUP）
3. 进入 → 弹出 SMB 登录框（用户名 / 密码 / 域名）

### 6.1 输入凭据（输入法坑）

搜狗 TV 输入法会拦截 `adb shell input text`，把字母转成中文候选。

```bash
# 临时禁用输入法
adb -s 192.168.1.16:5555 shell ime disable com.sohu.inputmethod.sogou.tv/.SogouIME

# 点用户名框 → 输入 → 用 TAB（KEYCODE_TAB=61）切到密码框 → 输入 → 再 TAB 到「确定」→ ENTER
adb -s 192.168.1.16:5555 shell 'input tap 540 268; input text "<SMB_USER>"'
adb -s 192.168.1.16:5555 shell 'input keyevent 61; input text "<SMB_PW>"'
adb -s 192.168.1.16:5555 shell 'input keyevent 61; input keyevent 61; input keyevent 61; input keyevent 66'

# 恢复输入法
adb -s 192.168.1.16:5555 shell ime enable com.sohu.inputmethod.sogou.tv/.SogouIME
adb -s 192.168.1.16:5555 shell settings put secure default_input_method com.sohu.inputmethod.sogou.tv/.SogouIME
```

> `input tap` 切输入框有延迟，容易把密码打进用户名框。
> 用 **TAB 键**在输入框间移动更可靠。

登录成功后会看到共享：`ADMINS` `C$` `D$` `DevelopmentFiles` `E$` `F$` `movie2` `Users`。
**`movie2` 就是 DV 片源库。**

### 6.2 杜比视界模式设置（★ 下一步必做）

**首选项 → 视频 → 「杜比视界模式」** 默认是「自动」。
自动模式下 Nova 读取电视显示能力，因电视只报 SDR 而**降级为普通 HEVC 播放**。

改为 **「强制」（DOVI_MODE_FORCE）**，跳过能力检测强制请求 DV 解码器。

同时**取消勾选「优先使用另外的视频播放器」**——它会把播放交给外部 App，切断 Nova 自己的 DV 解码链路。

> 自动化难点：该面板用 `input tap` 点击无响应。
> 用 `uiautomator dump` 精确定位控件 bounds，再配合 DPAD 导航 + ENTER 选中。

```bash
adb -s 192.168.1.16:5555 shell uiautomator dump /sdcard/wd.xml
adb -s 192.168.1.16:5555 pull /sdcard/wd.xml /tmp/wd.xml
```

---

## 7. 验证

```bash
# 播放状态
adb -s 192.168.1.16:5555 shell 'dumpsys media_session | grep state=PlaybackState'
#   state=3 即正在播放

# 图层色彩信息（DV 会有 secure + hdr10 + BT2020）
adb -s 192.168.1.16:5555 shell dumpsys SurfaceFlinger | grep -A20 PlayerActivity

# 显示能力（关键：supportedColorModes 只有 SDR）
adb -s 192.168.1.16:5555 shell dumpsys display | grep -A15 HdrCapabilities
```

> ⚠️ 播放 DV 时 `adb exec-out screencap` 只能得到 ~10KB 黑图（secure layer），
> **这是正常现象**。判断 DV 是否点亮只能肉眼看电视屏幕右上角的标志。
