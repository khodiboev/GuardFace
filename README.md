# GuardFace

**Step away, and your screen covers itself. Come back, and it clears.**

GuardFace is a tiny macOS menu bar app that uses your Mac's camera to tell whether you're sitting in front of it. When you leave, or when a second face appears behind you, it frosts the screen over, or locks the Mac. It uncovers only when you're back, alone, in view.

<!-- Demo: add a GIF here, e.g. ![demo](docs/demo.gif) -->

## Features

- **Two triggers.** The screen reacts when nobody is in front of the camera (you stepped away) or when two or more faces appear (someone is looking over your shoulder).
- **Two modes, your choice.**
  - **Blur the screen** — a frosted curtain covers every display, with a lock icon and a message. It clears by itself when you're back and alone.
  - **Lock the Mac** — the Mac locks like the ⌃⌘Q shortcut; you unlock it with your password or Touch ID.
- **Choose how fast it reacts.** Right away, after 2 seconds, or after 5 seconds, so a quick reach for your coffee doesn't trigger it.
- **Private by design.** Only face *counts* are used. No faces are identified, nothing is recorded, nothing leaves your Mac, and the camera turns off when the Mac is locked or asleep.
- **Lightweight.** A native Swift app with no third-party dependencies.

## Which mode should I use?

- **Lock the Mac** is real protection. While the Mac is locked, nobody can see or touch anything without your password or Touch ID.
- **Blur the screen** is a quick privacy curtain. It hides what's on screen and swallows normal mouse clicks and keystrokes aimed at the windows underneath, so someone can't blindly type behind it. But a frosted window is **not** a full lock: some input paths on macOS can still reach apps underneath, so for anything sensitive, use **Lock the Mac**.

## Requirements

- macOS 14.6 (Sonoma) or later
- A Mac with a camera (built-in, external, or an iPhone via Continuity Camera)

## Installation (no coding needed)

1. Go to the [**Releases**](../../releases) page and download `GuardFace.zip`.
2. Unzip it and drag **GuardFace.app** into your **Applications** folder.
3. Open the app. macOS will warn that it "cannot verify the developer", because the app is not notarized by Apple. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to GuardFace.
5. Click **Allow** when the app asks for camera access.
6. Optional: click the menu bar icon and turn on **Launch at login**.

If **Open Anyway** doesn't appear, run this in Terminal and open the app again:

```bash
xattr -cr /Applications/GuardFace.app
```

## Usage

Click the eye icon in the menu bar (it closes while the screen is covered):

| Menu item | What it does |
|---|---|
| Enabled | Turn watching on or off |
| When unattended | **Blur the screen** or **Lock the Mac** |
| React after | Right away, after 2 seconds, or after 5 seconds |
| Launch at login | Start GuardFace automatically |
| Quit | Quit the app |

To unlock the blur, just sit back in front of the camera so you're the only face in view. To unlock a real Mac lock, use your password or Touch ID.

## How it works

1. **Count faces.** A few times per second, Apple's Vision framework (`VNDetectFaceRectanglesRequest`) counts confident faces in the camera frame. The images are never stored or identified.
2. **Decide.** Zero faces means you left; two or more means someone joined. Either one, held longer than your "React after" setting, is treated as unattended.
3. **React.** In blur mode, a frosted `NSVisualEffectView` window is shown on every screen and catches input. In lock mode, the Mac is locked immediately.
4. **Recover.** The blur clears the moment you're alone in front of the camera again; a real lock is opened with your password or Touch ID.

## Build from source

1. Clone the repository and open the project:

   ```bash
   git clone https://github.com/khodiboev/GuardFace.git
   cd GuardFace
   open GuardFace.xcodeproj
   ```

2. In Xcode, select the **GuardFace** target, then go to **Signing & Capabilities**:
   - Set **Team** to your own Apple ID (a free *Personal Team* works).
   - Change the **Bundle Identifier** to something unique, e.g. `com.yourname.GuardFace`.
   - Keep **App Sandbox** off: the "Lock the Mac" feature doesn't work inside the sandbox.

3. Press **⌘R** to build and run.

## Troubleshooting

| Problem | Fix |
|---|---|
| "No camera access" in the menu | System Settings → Privacy & Security → **Camera** → enable GuardFace |
| It covers the screen when you're sitting there | Choose a longer **React after**, or improve the lighting so your face is detected |
| It doesn't react when you leave | Make sure **Enabled** is on and the camera isn't used exclusively by another app |
| "Lock the Mac" doesn't lock | Make sure App Sandbox is off; the app falls back to the screensaver if the system lock call is unavailable |

## Project structure

```
GuardFace/
├── GuardFaceApp.swift     # App entry point + menu bar menu
├── GuardController.swift  # Camera, face counting, blur/lock decisions
└── CurtainOverlay.swift   # Frosted curtain that covers and blocks the screen
```

## License

[MIT](LICENSE)
