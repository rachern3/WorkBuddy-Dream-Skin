# WorkBuddy Dream Skin

给官方 WorkBuddy 桌面端换一张会呼吸的脸。

这是一个外部主题/壁纸引擎：通过 WorkBuddy 自带的本机 CDP 调试入口注入 CSS，
不修改 `WorkBuddy.app`、`app.asar` 或官方代码签名。侧栏、任务、输入框、文档预览
仍然是原生可交互控件。

> 非腾讯官方产品。WorkBuddy 及相关权利归其权利人。

![Gothic Void Crusade 在 WorkBuddy 首页的真实注入效果](docs/workbuddy-home-preview.png)

## 当前状态

- macOS Apple Silicon：已在 WorkBuddy 5.2.6 / Electron 37.10.3 实机验证
- macOS Intel：脚本结构兼容，等待实机回归
- Windows：主题运行时可复用，启动器与安装器尚未发布

当前是 `0.1.0` 技术预览版，目标是先把“不改官方客户端、可验证、可恢复”的
macOS 链路做稳，再补菜单栏应用和 Windows 安装包。

## 安装

要求：

- macOS 12 或更高版本
- 已安装官方 `WorkBuddy.app`
- 启动前请确认 WorkBuddy 没有正在执行的任务，然后正常退出 WorkBuddy

下载仓库后，双击：

```text
Install WorkBuddy Dream Skin.command
```

安装器把独立引擎复制到：

```text
~/.workbuddy-dream-skin/studio
```

主题状态保存在：

```text
~/Library/Application Support/WorkBuddyDreamSkin
```

它不会把主题文件写进 WorkBuddy 的用户配置目录。

## 使用

- `Start WorkBuddy Dream Skin.command`：以主题模式启动官方 WorkBuddy
- `Verify WorkBuddy Dream Skin.command`：校验签名、CDP 身份、样式和背景层
- `Restore WorkBuddy.command`：移除运行时并用普通模式重新打开 WorkBuddy

启动器发现 WorkBuddy 已在普通模式运行时会拒绝强制关闭，避免中断后台任务。

## 自定义主题

复制 `presets/gothic-void-crusade`，替换其中的 `background.jpg` 并编辑
`theme.json`，然后运行：

```bash
./scripts/start-workbuddy-dream-skin-macos.sh --theme /absolute/path/to/theme
```

背景图必须小于等于 16 MiB。推荐 2560×1440 的纯背景图，不要把带 UI 的截图
当作背景。任务页与设置页会自动降低壁纸透明度，以保证文档和代码可读。

## 安全边界

- CDP 仅允许绑定 `127.0.0.1`
- 校验官方 Bundle ID、严格代码签名和腾讯 Team ID
- 只连接 WorkBuddy 主 Renderer，不注入登录页、网页预览或 WebView
- Restore 只停止本项目创建并记录的 launchd 作业
- CDP 对同一系统用户下的其他本机进程没有认证；主题运行时不要执行不可信程序

更多实现与升级兼容策略见 [架构说明](docs/architecture.md)。

## 开发

```bash
npm test
npm run check
```

## 许可与归属

代码采用 MIT License。项目思路与部分结构源自
[Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin)，详见
[NOTICE.md](NOTICE.md)。内置 Gothic Void Crusade 预设请保留原作者归属；导入其他
图片前请自行确认使用与分发权。
