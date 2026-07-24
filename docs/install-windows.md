# Windows 安装说明

## 要求

- Windows 10 或 Windows 11，64 位系统
- 已从腾讯 WorkBuddy 官网安装并至少启动登录一次
- 安装皮肤前确认没有正在执行的 WorkBuddy 任务

## 从 GitHub Release 安装

1. 下载 `WorkBuddy-Dream-Skin-vX.Y.Z-Windows.zip`。
2. 如果“属性”窗口里有“解除锁定”，先勾选它，再解压 ZIP。
3. 双击 `Install WorkBuddy Dream Skin - Windows.cmd`。
4. 首次启用时允许 WorkBuddy 重启一次。

安装器会验证 `WorkBuddy.exe` 的 Authenticode 签名、腾讯发行信息和产品元数据，
然后把独立引擎复制到：

```text
%LOCALAPPDATA%\WorkBuddyDreamSkin\engine
```

背景与会话状态保存在：

```text
%LOCALAPPDATA%\WorkBuddyDreamSkin
```

桌面会出现启动、换图和恢复快捷方式；Windows 系统托盘也会出现快捷菜单。

## 恢复

双击桌面的 `WorkBuddy Dream Skin - Restore`，或从托盘选择
`Restore official appearance...`。恢复会关闭仅绑定本机回环地址的调试会话，
重新以普通模式打开官方 WorkBuddy，并保留已经导入的背景。

## 安全说明

- 不修改 `WorkBuddy.exe`、`app.asar` 或官方安装目录。
- CDP 只接受 `127.0.0.1` / `::1`，并再次核对监听进程路径。
- 只停止状态文件中记录且身份匹配的注入进程。
- Windows 包目前未做商业代码签名；请只从本项目 GitHub Release 下载并核对 SHA256。
