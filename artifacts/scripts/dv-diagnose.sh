#!/bin/bash
# DV 解码诊断：播放 DV 视频时抓取 Kodi 实际选用的解码器
# 用法：先清空日志 -> 在电视上播放一个 DV 片子 -> 运行本脚本
ADB="adb -s 192.168.1.16:5555"

echo "=== 抓取 Kodi DV 解码相关日志 ==="
echo "过滤关键字: MediaCodec / dolby / dovi / dvhe / hdr / amc-dv"
echo
$ADB logcat -d -t 3000 2>/dev/null | grep -iE \
  "CDVDVideoCodecAndroidMediaCodec|dolby|dovi|dvhe|dvh1|amc-dv|hdr|Open.*codec|video/dolby" \
  | tail -80

echo
echo "=== 当前播放会话（Jellyfin） ==="
TOKEN="358ef5ade9ff499fa5696f61419c04fc"
python3 - <<'PY'
import json, urllib.request
try:
    req=urllib.request.Request('http://192.168.1.68:8096/Sessions',
        headers={'Authorization':'MediaBrowser Token="358ef5ade9ff499fa5696f61419c04fc"','Accept':'application/json'})
    ss=json.load(urllib.request.urlopen(req,timeout=6))
    for s in ss:
        if s.get('NowPlayingItem'):
            print('Playing:',s['NowPlayingItem'].get('Name'))
            print('PlayMethod:',s.get('PlayState',{}).get('PlayMethod'))
            print('Transcoding:',bool(s.get('TranscodingInfo')))
except Exception as e:
    print('Jellyfin 不可用:',e)
PY
