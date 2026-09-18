<p align="center"><img src="icon/icon-1024.png" width="128" alt="Glaze icon"></p>

<h1 align="center">Glaze</h1>

<p align="center">Look away from your Mac and the screen glazes over. Look back and it clears.</p>

Glaze is a small macOS app that uses the built-in camera to check whether you are facing the screen. Turn your head away, or leave the desk, and every display turns to frosted glass. Shapes and colors still show through, but text doesn't. Turn back and it clears right away.

It's built for vibe coding: an agent keeps typing in your terminal while you're up getting coffee or talking to someone, and your screen isn't sitting there for anyone walking by to read.

## What counts as "looking away"

| You... | Glaze |
|---|---|
| turn your head left or right past 20° | frosts after 1 s |
| tilt your head up past 10° | frosts after 1 s |
| leave the camera's view | frosts after 1 s |
| look down at the keyboard or your phone | stays clear |
| face the screen again | clears on the next frame |

The 1-second delay means a quick glance aside doesn't trigger it. Angles are measured from your own "facing the screen" pose, which you set once with **Calibrate**. That also makes an external monitor to the side of the laptop camera work: calibrate while facing the monitor.

## Controls

The menu-bar icon can end up hidden behind the notch, so everything is also on hotkeys and on the Dock icon's right-click menu.

| Key | Action |
|---|---|
| `Esc` | clear the frost now (only grabbed while frosted or calibrating) |
| `⌃⌥K` | calibrate: face the screen for 4 s |
| `⌃⌥X` | pause / resume |
| `⌃⌥B` | preview the frost for 2 s |
| `⌃⌥Q` | quit |

Right-click the Dock icon for Pause, Calibrate, Preview and Quit.

## Install

Requires macOS 14 or newer and a camera. Build from source with the Xcode command-line tools (`xcode-select --install`):

```sh
git clone https://github.com/Longado/glaze.git
cd glaze
./build.sh
open Glaze.app
```

The app is ad-hoc signed, not notarized. If macOS blocks the first launch, right-click `Glaze.app` → **Open**. Allow camera access when asked, then press `⌃⌥K` once to calibrate.

## Privacy

The camera is read four times a second, face angles are computed with Apple's on-device Vision framework, and each frame is dropped right after. Nothing is saved, and the app makes no network requests. The camera turns off while the screen is locked or asleep, and while Glaze is paused.

## Limits

- The default angles come from one person at one desk. If Glaze frosts when you don't want it to (or doesn't when you do), calibrate first. The thresholds are constants at the top of `Calib.swift`.
- Leaning in close to a camera below the screen can read as tilting your head up.
- In dim light the face detector loses you more often, and "no face" counts as looking away.

## Development

```sh
swiftc Calib.swift tests/main.swift -o /tmp/calibcheck && /tmp/calibcheck   # calibration logic check
open --env GLAZE_DEBUG=1 --stderr /tmp/glaze.log Glaze.app && tail -f /tmp/glaze.log   # live yaw/pitch readout
python3 icon/make_icon.py   # regenerate the pixel icon (needs Pillow)
```

---

## 中文说明

Glaze 用 Mac 自带的摄像头判断你是否在看屏幕。头往左或往右转、明显抬头，或者人离开座位，所有屏幕都会变成磨砂玻璃：能看出轮廓，但看不清字。转回来立刻恢复。低头打字、低头看手机都不会触发。

- 第一次用先按 `⌃⌥K` 校准：正对屏幕坐 4 秒。
- 屏幕磨砂时按 `Esc` 立刻清除，`⌃⌥X` 暂停或恢复，`⌃⌥Q` 退出。在 Dock 图标上右键也能找到这些操作。
- 画面只在内存里分析，不保存也不上传。锁屏或暂停时摄像头会关闭。

## License

MIT
