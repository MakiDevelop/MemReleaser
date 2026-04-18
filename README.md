# MemReleaser

MemReleaser is a macOS menu bar memory guard app for catching pressure before apps start freezing.

It does three things:

1. Samples system memory, compression, and swap usage.
2. Aggregates multi-process apps like Chrome or Brave at the `.app` level.
3. Recommends which idle heavyweight apps to quit first, with optional notifications and critical auto-release.

It also keeps a short rolling history so you can tell whether a bad moment is a transient spike, a high baseline, or an app that is actively ballooning.

## What it does not do

It does not pretend to "clean RAM" globally. On macOS, the useful action is usually to reduce the working set by quitting or suspending heavyweight apps, browser profiles, VMs, containers, or idle developer tools.

## Reliability-focused features

- 30-minute in-app trend chart for available memory and swap.
- 15-minute growth detector for apps that are actively ballooning.
- Persistent ignore rules keyed by stable app identity, preferring bundle identifier over transient process paths.
- Launch at Login settings backed by `SMAppService.mainApp`.

## Local development

```bash
swift test
swift run MemReleaser
```

`swift run` is good for local iteration, but Launch at Login typically only works from a real app bundle.

## Build as a real macOS app

Generate an Xcode project:

```bash
xcodegen generate
open MemReleaser.xcodeproj
```

The generated project sets `LSUIElement=YES`, so the app behaves like a menu bar utility without a Dock icon. The generated `.xcodeproj` is intentionally ignored from git; `project.yml` is the checked-in source of truth.

## Launch at Login

Launch at Login is implemented with Apple's `SMAppService.mainApp` API. According to Apple documentation, `mainApp` is the service object for launching the main app at login, and `register()` / `unregister()` manage that registration:

- https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp
- https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29

If the app reports that login launch is unavailable, run it from the generated Xcode app bundle instead of `swift run`.
