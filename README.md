# Codex Account Switcher

**English** | [简体中文](#简体中文)

## Download

**Latest macOS app:** [CodexAccountSwitcher-v0.2.0-macOS.zip](https://github.com/Purron/codex-account-switcher/releases/download/v0.2.0/CodexAccountSwitcher-v0.2.0-macOS.zip)

All downloads are available on the [GitHub Releases page](https://github.com/Purron/codex-account-switcher/releases).

> Note: the current build is not Apple notarized yet. On first launch, macOS may require opening it via right click -> Open or allowing it in Privacy & Security.

## Screenshot

![Codex Account Switcher menu screenshot](docs/screenshot-menu.png)

A local-first macOS menu bar app for switching between multiple OpenAI Codex accounts.

Codex Account Switcher saves the Codex CLI auth state and Codex Desktop app state for each profile. When you switch profiles, it quits Codex, restores the selected account state, and opens Codex again.

It is useful when you regularly move between personal, work, or team Codex accounts.

## Features

- Switch Codex accounts from the macOS menu bar
- Capture the currently signed-in Codex account as a local profile
- Save the active profile before switching away
- Restore `~/.codex/auth.json` for Codex CLI
- Restore `~/Library/Application Support/Codex` for Codex Desktop
- Show each saved profile's available Codex usage windows from the official Codex usage endpoint
- Keep all profile data on your machine

## Project Structure

```text
.
├── CodexAccountSwitcher.swift     # macOS menu bar app source
├── codex-account-switcher.sh      # Account capture and switch script
├── build-app.sh                   # Local build script
├── resources/                     # App icons and Info.plist
└── README.md
```

## Requirements

- macOS
- OpenAI Codex Desktop App
- Codex CLI, with at least one account already signed in
- Swift compiler, usually provided by Xcode Command Line Tools

This app does not read files owned by other apps. Usage display reads each saved profile's own Codex `auth.json`, calls Codex's official `https://chatgpt.com/backend-api/wham/usage` endpoint, and stores only a small cache under `~/Library/Application Support/CodexAccountSwitcher/usage-cache.json`.

## Quick Start

Sign in to your first Codex account, then run:

```bash
./codex-account-switcher.sh capture personal
```

Sign out and sign in to your second Codex account, then run:

```bash
./codex-account-switcher.sh capture work
```

Switch between profiles:

```bash
./codex-account-switcher.sh switch personal
./codex-account-switcher.sh switch work
```

List saved profiles:

```bash
./codex-account-switcher.sh list
```

Show the active profile:

```bash
./codex-account-switcher.sh active
```

## Build the Menu Bar App

```bash
chmod +x build-app.sh codex-account-switcher.sh
./build-app.sh
open "build/Codex Account Switcher.app"
```

After launch, the menu bar item shows the switcher icon and the current profile's main remaining usage percentage.

From the menu, you can:

- Switch accounts with profile cards
- Add a new saved profile with the plus button
- View the active profile's available usage windows, including named supplemental limits when provided
- Refresh usage from the menu
- Open the profile data folder
- Quit the switcher

## Data Location

Profiles are saved locally in:

```text
~/Library/Application Support/CodexAccountSwitcher
```

Each profile uses this structure:

```text
profiles/<name>/auth/auth.json
profiles/<name>/app-support/Codex
profiles/<name>/profile.env
```

## Security Notes

This tool only copies Codex auth and desktop state files on your local machine. It does not read, print, or upload token contents.

Be careful with profile data. `~/Library/Application Support/Codex` may contain cookies, Local Storage, window state, and other desktop app state. Do not commit profile data to GitHub or share it with anyone else.

Codex Desktop must be restarted when switching accounts. Electron and Chromium auth state does not hot-reload while the app is running, so this tool quits Codex before capture and switch operations.

## CLI Reference

```text
codex-account-switcher.sh capture <profile>
codex-account-switcher.sh switch <profile> [--no-open]
codex-account-switcher.sh list [--plain]
codex-account-switcher.sh active
codex-account-switcher.sh open-folder
```

Environment variables:

```text
SWITCHER_HOME       Profile storage directory
CODEX_AUTH_FILE     Codex CLI auth file, default ~/.codex/auth.json
CODEX_APP_SUPPORT   Codex Desktop state directory, default ~/Library/Application Support/Codex
CODEX_APP_NAME      macOS app name, default Codex
```

## Recapturing Old Profiles

If you captured profiles with an older version, sign in to each account again and capture it with the same profile name:

```bash
./codex-account-switcher.sh capture personal
./codex-account-switcher.sh capture work
```

This keeps `auth.json` and Codex Desktop state in the latest format.

---

# 简体中文

[English](#codex-account-switcher) | **简体中文**

## 下载

**最新版 macOS App：** [CodexAccountSwitcher-v0.2.0-macOS.zip](https://github.com/Purron/codex-account-switcher/releases/download/v0.2.0/CodexAccountSwitcher-v0.2.0-macOS.zip)

所有版本都可以在 [GitHub Releases 页面](https://github.com/Purron/codex-account-switcher/releases) 下载。

> 注意：当前版本还没有经过 Apple notarize。首次打开时，macOS 可能需要你右键 App 选择 Open，或在 Privacy & Security 里允许打开。

## 应用截图

![Codex Account Switcher 菜单截图](docs/screenshot-menu.png)

一个本地优先的 macOS 菜单栏工具，用来在多个 OpenAI Codex 账号之间快速切换。

Codex Account Switcher 会保存每个 profile 对应的 Codex CLI 登录态和 Codex Desktop 应用状态。切换 profile 时，它会自动退出 Codex、恢复目标账号状态，并重新打开 Codex。

适合同时使用个人账号、工作账号或不同团队账号的场景。

## 功能特性

- 从 macOS 菜单栏快速切换 Codex 账号
- 捕获当前 Codex 登录态为本地 profile
- 切换前自动保存当前 profile 的最新 Codex 状态
- 恢复 Codex CLI 的 `~/.codex/auth.json`
- 恢复 Codex Desktop 的 `~/Library/Application Support/Codex`
- 通过 Codex 官方用量接口展示每个已保存 profile 当前可用的用量窗口
- 所有 profile 数据都保存在本机

## 项目结构

```text
.
├── CodexAccountSwitcher.swift     # macOS 菜单栏 App 源码
├── codex-account-switcher.sh      # 账号捕获和切换脚本
├── build-app.sh                   # 本地构建脚本
├── resources/                     # App 图标和 Info.plist
└── README.md
```

## 系统要求

- macOS
- 已安装 OpenAI Codex Desktop App
- 已安装 Codex CLI，并至少登录过一个账号
- Swift 编译器，通常随 Xcode Command Line Tools 提供

本工具不会读取其他 App 的私有文件。用量展示只读取每个 profile 自己保存的 Codex `auth.json`，请求 Codex 官方的 `https://chatgpt.com/backend-api/wham/usage` 接口，并且只把剩余百分比、reset 时间和更新时间缓存到 `~/Library/Application Support/CodexAccountSwitcher/usage-cache.json`。

## 快速开始

先登录第一个 Codex 账号，然后执行：

```bash
./codex-account-switcher.sh capture personal
```

再退出当前 Codex 账号并登录第二个账号，然后执行：

```bash
./codex-account-switcher.sh capture work
```

之后就可以在两个账号之间切换：

```bash
./codex-account-switcher.sh switch personal
./codex-account-switcher.sh switch work
```

查看已保存 profile：

```bash
./codex-account-switcher.sh list
```

查看当前记录的 active profile：

```bash
./codex-account-switcher.sh active
```

## 构建菜单栏 App

```bash
chmod +x build-app.sh codex-account-switcher.sh
./build-app.sh
open "build/Codex Account Switcher.app"
```

打开后，菜单栏会显示切换器图标和当前 profile 的主要剩余额度百分比。

点击菜单栏图标可以：

- 通过 profile 卡片切换账号
- 点击加号保存新的 profile
- 查看当前 profile 的可用用量窗口，以及服务端提供的命名补充额度
- 在菜单里刷新用量
- 打开 profile 数据目录
- 退出切换器

## 数据保存位置

profile 默认保存在：

```text
~/Library/Application Support/CodexAccountSwitcher
```

每个 profile 内部结构如下：

```text
profiles/<name>/auth/auth.json
profiles/<name>/app-support/Codex
profiles/<name>/profile.env
```

## 安全说明

这个工具只在本机复制 Codex 的登录态文件和桌面端应用状态，不会读取、打印或上传 token 内容。

需要注意的是，`~/Library/Application Support/Codex` 可能包含 Cookie、Local Storage、窗口状态等桌面端状态。请只在你信任的本机环境中使用，不要把 profile 数据目录提交到 GitHub 或发送给别人。

切换已经打开的 Codex Desktop 时，必须退出并重启 Codex。Electron/Chromium 登录态不会在运行中热更新，所以本工具会在捕获和切换前主动退出 Codex。

## 脚本命令

```text
codex-account-switcher.sh capture <profile>
codex-account-switcher.sh switch <profile> [--no-open]
codex-account-switcher.sh list [--plain]
codex-account-switcher.sh active
codex-account-switcher.sh open-folder
```

支持的环境变量：

```text
SWITCHER_HOME       Profile 存储目录
CODEX_AUTH_FILE     Codex CLI auth 文件，默认 ~/.codex/auth.json
CODEX_APP_SUPPORT   Codex Desktop 状态目录，默认 ~/Library/Application Support/Codex
CODEX_APP_NAME      macOS App 名称，默认 Codex
```

## 重新捕获旧 Profile

如果你用旧版本捕获过 profile，建议重新登录每个账号后用同名 profile 捕获一次：

```bash
./codex-account-switcher.sh capture personal
./codex-account-switcher.sh capture work
```

这样可以确保 `auth.json` 和 Codex Desktop 状态都是最新格式。
