# Moneyora — Development Environment Setup

Target: Flutter (stable), Android 8.0+ (API 26) and iOS 14+.
Everything below was verified against this machine's current state on 2026-08-24.

---

## Machine audit

Re-verified 2026-09-01. Items marked done were resolved after the original
2026-08-24 audit.

| Item | Status | Action |
|---|---|---|
| Git | Installed | — |
| VS Code | Installed | — |
| Adoptium JDK 21 | Installed (`C:\Program Files\Eclipse Adoptium\jdk-21.0.8.9-hotspot`) | — |
| `JAVA_HOME` | **Set to JDK 21** | Done — see §3 |
| Java on PATH | Reports v25 | Harmless: Gradle and Flutter read `JAVA_HOME`, which now wins |
| Free disk space on `C:` | **67 GB** (was 6.6 GB) | Done — §0 no longer blocking |
| Free disk space on `D:` | 43 GB | Caches relocated here |
| `GRADLE_USER_HOME` / `ANDROID_SDK_ROOT` | `D:\dev\...` | Done |
| `PUB_CACHE` | **`C:\dev\pub-cache`** — must share a drive with the repo | Done — see §0.1 |
| Flutter SDK | **Not installed** | **Install — see §1** |
| VS Code Flutter/Dart extensions | **Not installed** | **Install — see §1** |
| Android SDK / Android Studio | **Not installed** | **Install — see §2** |
| Xcode / macOS | N/A (Windows) | iOS builds need a Mac or CI runner |

> Environment variables are read by processes **at launch**. After the changes
> above, VS Code and every open terminal must be fully restarted — not just a
> new terminal tab — before they see the new values.

---

## 0. Free up disk space FIRST

`C:` currently has **6.6 GB free**. A complete Flutter + Android toolchain needs
roughly **20 GB**, and it does not fail cleanly when it runs out — Gradle throws
unrelated-looking errors, and half-downloaded SDK components must be deleted by
hand before you can retry.

| Component | Approx. size |
|---|---|
| Flutter SDK (after first `flutter doctor`) | 3–4 GB |
| Android Studio | ~3 GB |
| Android SDK: platform + build-tools + cmdline-tools | 4–5 GB |
| One emulator system image | 2–3 GB |
| Gradle cache (`~/.gradle`, grows over the project) | 3–5 GB |
| Pub cache + this project's `build/` | 2–3 GB |
| **Total** | **~20 GB** |

Find what is actually large:

```powershell
Get-ChildItem C:\Users\ASUS -Directory -Force |
  ForEach-Object { [PSCustomObject]@{
      Name = $_.Name
      GB   = [math]::Round((Get-ChildItem $_.FullName -Recurse -File -Force -EA SilentlyContinue |
             Measure-Object Length -Sum).Sum / 1GB, 2) } } |
  Sort-Object GB -Descending | Select-Object -First 15
```

Ways to reclaim it, in order of return:

- **Windows Disk Cleanup** — run `cleanmgr`, click *Clean up system files*, then
  tick *Previous Windows installations* and *Delivery Optimization Files*.
  Often 5–15 GB on its own.
- **OneDrive Files On-Demand** — right-click the OneDrive folder → *Free up
  space*. Keeps the files, drops the local copies.
- Old `node_modules`, `.venv`, `target/`, `build/` folders in other projects.
- Docker is installed on this machine: `docker system prune -a` if unused.

If you cannot free 20 GB on `C:`, install onto a second drive — both Flutter and
the Android SDK support it:

```powershell
# Flutter at D:\dev\flutter, and relocate the two caches that grow the most
# PUB_CACHE must stay on the SAME DRIVE as the repository - see 0.1 below.
[Environment]::SetEnvironmentVariable('PUB_CACHE',        'C:\dev\pub-cache',   'User')
[Environment]::SetEnvironmentVariable('GRADLE_USER_HOME', 'D:\dev\gradle',      'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', 'D:\dev\android-sdk', 'User')
```

> **Never put the SDK or this project inside OneDrive.** The sync client locks
> files mid-build and corrupts `build/` in ways that look like compiler bugs.
> This repo lives at `C:\Users\ASUS\Documents\GitHub\Moneyora`, which is *not*
> the OneDrive-redirected Documents folder — that is correct, leave it there.

## 0.1 PUB_CACHE must share a drive with the repository

Move the Gradle cache and the Android SDK to a second drive freely. **Do not
move `PUB_CACHE` there** unless the repository lives on the same drive.

Kotlin's incremental compiler resolves plugin sources against the project
directory using a *relative* path, and on Windows there is no relative path
between two drive letters. With the repo on `C:` and the cache on `D:`, every
plugin written in Kotlin fails to build:

```
IllegalArgumentException: this and base files have different roots:
  D:\dev\pub-cache\...\google_mlkit_commons-0.13.0\...\GenericModelManager.kt
  and C:\Users\ASUS\Documents\GitHub\Moneyora\android
```

**The message that surfaces is not that one.** Gradle reports pages of
`Could not close incremental caches` and `Daemon compilation failed`, and the
real cause appears only in a *suppressed* exception far down the trace — which
is why this cost an evening. Two `flutter clean` runs and a daemon restart
changed nothing, because nothing was corrupt.

To move an existing cache without re-downloading it:

```powershell
robocopy 'D:\dev\pub-cache' 'C:\dev\pub-cache' /E /MOVE
[Environment]::SetEnvironmentVariable('PUB_CACHE', 'C:\dev\pub-cache', 'User')
```

Then open a new terminal, since environment variables are read at process
start.

`GRADLE_USER_HOME` and `ANDROID_SDK_ROOT` are unaffected — neither holds Kotlin
sources that are compiled relative to the project.

---

## 1. Install the Flutter SDK

### Option A — via VS Code (recommended)

The Flutter extension downloads and configures the SDK for you, and wires up the
PATH, debugger, and hot reload in one pass. Neither the Flutter nor the Dart
extension is installed on this machine yet.

1. **Extensions** (`Ctrl+Shift+X`) → search **"Flutter"** → install the one
   published by **Dart Code**. It pulls in the Dart extension automatically.
2. `Ctrl+Shift+P` → **`Flutter: New Project`**.
3. When it reports that no SDK was found, choose **Download SDK**.
4. Pick a location: **`C:\dev`** (or `D:\dev`). Never a path containing spaces,
   never inside OneDrive, never inside this repo.
5. Let it finish, then reload the window.

Confirm it reached your PATH from a **fresh external terminal** — the extension
sometimes only exposes it to VS Code's integrated terminal:

```powershell
flutter --version
```

If that fails, add it to PATH manually using the command in Option B.

> This installs **Flutter only.** You still need the Android SDK (§2) before you
> can build or run anything. The extension does not handle that part.

### Option B — manual

Do **not** unzip Flutter into `C:\Program Files\` or any path containing spaces —
Gradle and the Dart build tools break on both.

```powershell
# Recommended location
mkdir C:\dev
cd C:\dev
# Download the Windows stable zip from https://docs.flutter.dev/get-started/install/windows
# then extract so you end up with C:\dev\flutter\bin\flutter.bat
```

Add to PATH (user-level, no admin needed):

```powershell
[Environment]::SetEnvironmentVariable(
    'Path',
    [Environment]::GetEnvironmentVariable('Path','User') + ';C:\dev\flutter\bin',
    'User')
```

Close and reopen the terminal, then:

```powershell
flutter --version
flutter doctor -v
```

> **Team tip:** once there is more than one machine involved, switch to
> [FVM](https://fvm.app) (`dart pub global activate fvm`) and pin the SDK version
> in `.fvmrc`. A Flutter version mismatch between your laptop and CI is the
> single most common source of "works on my machine" build failures.

## 2. Install the Android SDK

Install **Android Studio** (it bundles the SDK, platform-tools, and an emulator),
then in *Settings → Languages & Frameworks → Android SDK*, tick:

- Android SDK Platform 34 or 35 (compile target)
- Android SDK Build-Tools
- Android SDK Command-line Tools ← **required**, `flutter doctor` fails without it
- Android SDK Platform-Tools
- Android Emulator

Then accept the licences:

```powershell
flutter doctor --android-licenses
```

## 3. Pin the JDK to 21

`java -version` on this machine currently reports **25**. Gradle's Android plugin
does not support JDK 25; builds will fail with cryptic `Unsupported class file
major version` errors. Adoptium **JDK 21** is already installed at
`C:\Program Files\Eclipse Adoptium\jdk-21.0.8.9-hotspot`. Point Flutter at it:

```powershell
flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-21.0.8.9-hotspot"
```

Verify with `flutter doctor -v` — it should report the Java 21 path.

## 4. Bootstrap the project

From the repo root, **once**:

```powershell
.\scripts\bootstrap.ps1
```

This generates `android/`, `ios/`, and `lib/main.dart`, then adds every
dependency from SDD §10.1 at its current resolvable version.

## 5. Run it

```powershell
flutter devices          # confirm an emulator or a USB device is visible
flutter run              # debug
flutter run --release    # perf-realistic; use this to check NFR-PER-001 (<2s cold start)
```

## 6. Daily commands

| Command | When |
|---|---|
| `flutter analyze` | Before every commit |
| `dart format .` | Before every commit |
| `flutter test` | Before every push |
| `bash scripts/check_architecture.sh` | Before every push |
| `flutter pub outdated` | Weekly |
| `dart run build_runner build --delete-conflicting-outputs` | After editing codegen-annotated files |
| `flutter clean && flutter pub get` | When the build goes weird |

---

## Physical-device note

Test on a **real Android device early**, not just the emulator. Three of your
requirements cannot be validated on an emulator:

- **FR-RCP-004** ML Kit OCR — emulator cameras render synthetic images
- **FR-SET-005** biometrics — emulator fingerprint is simulated
- **NFR-PER-001** <2s cold start — emulator timings are meaningless

Enable Developer Options → USB debugging on your phone and run `flutter devices`.
