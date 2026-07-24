import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem!
  private var operationCount = 0
  private let fileManager = FileManager.default

  private var engineRoot: URL {
    fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy-dream-skin/studio", isDirectory: true)
  }

  private var stateRoot: URL {
    fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WorkBuddyDreamSkin", isDirectory: true)
  }

  private var activeThemeDirectory: URL { stateRoot.appendingPathComponent("current-theme", isDirectory: true) }
  private var themesDirectory: URL { stateRoot.appendingPathComponent("themes", isDirectory: true) }
  private var bundledThemeDirectory: URL { engineRoot.appendingPathComponent("presets/gothic-void-crusade", isDirectory: true) }

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "WorkBuddy Dream Skin")
      button.image?.isTemplate = true
      button.toolTip = "WorkBuddy Dream Skin"
    }
    let menu = NSMenu(title: "WorkBuddy Dream Skin")
    menu.delegate = self
    statusItem.menu = menu
    rebuildMenu(menu)
  }

  func menuWillOpen(_ menu: NSMenu) {
    rebuildMenu(menu)
  }

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let active = activeThemeMetadata()
    let status = NSMenuItem(title: active.map { "当前背景：\($0.name)" } ?? "当前背景：内置背景", action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
    menu.addItem(.separator())

    menu.addItem(item("选择新背景图片…", action: #selector(chooseBackground), key: "n"))

    let switchItem = NSMenuItem(title: "快速切换背景", action: nil, keyEquivalent: "")
    let switchMenu = NSMenu(title: "快速切换背景")
    let bundled = item("内置背景 · Gothic Void Crusade", action: #selector(useBundledBackground))
    bundled.state = active?.id == "gothic-void-crusade" ? .on : .off
    switchMenu.addItem(bundled)

    let savedThemes = loadSavedThemes()
    if !savedThemes.isEmpty {
      switchMenu.addItem(.separator())
      for theme in savedThemes {
        let savedItem = item(theme.name, action: #selector(useSavedBackground(_:)))
        savedItem.representedObject = theme.id
        savedItem.state = active?.id == theme.id ? .on : .off
        switchMenu.addItem(savedItem)
      }
    }
    switchItem.submenu = switchMenu
    menu.addItem(switchItem)

    menu.addItem(item("重新应用当前背景", action: #selector(reapplyBackground), key: "r"))
    menu.addItem(.separator())
    menu.addItem(item("验证运行状态", action: #selector(verifySkin)))
    menu.addItem(item("打开背景目录", action: #selector(openThemesFolder)))
    menu.addItem(item("恢复 WorkBuddy 官方外观…", action: #selector(restoreOfficialAppearance)))
    menu.addItem(.separator())
    menu.addItem(item("退出菜单栏工具", action: #selector(quit), key: "q"))
  }

  private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
    let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
    result.target = self
    return result
  }

  @objc private func chooseBackground() {
    run("customize-theme-macos.sh", description: "选择新背景")
  }

  @objc private func useBundledBackground() {
    run("switch-theme-macos.sh", arguments: ["--bundled"], description: "恢复内置背景")
  }

  @objc private func useSavedBackground(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    run("switch-theme-macos.sh", arguments: ["--id", id], description: "切换背景")
  }

  @objc private func reapplyBackground() {
    let theme = fileManager.fileExists(atPath: activeThemeDirectory.appendingPathComponent("theme.json").path)
      ? activeThemeDirectory : bundledThemeDirectory
    run("apply-theme-macos.sh", arguments: ["--theme", theme.path], description: "重新应用背景")
  }

  @objc private func verifySkin() {
    run("verify-workbuddy-dream-skin-macos.sh", description: "验证运行状态", showSuccess: true)
  }

  @objc private func restoreOfficialAppearance() {
    let alert = NSAlert()
    alert.messageText = "恢复 WorkBuddy 官方外观？"
    alert.informativeText = "这会停止当前皮肤会话，但不会删除你保存的背景。"
    alert.addButton(withTitle: "恢复")
    alert.addButton(withTitle: "取消")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    run("restore-workbuddy-macos.sh", description: "恢复官方外观", showSuccess: true)
  }

  @objc private func openThemesFolder() {
    try? fileManager.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
    NSWorkspace.shared.open(themesDirectory)
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func run(_ name: String, arguments: [String] = [], description: String, showSuccess: Bool = false) {
    let script = engineRoot.appendingPathComponent("scripts/\(name)")
    guard fileManager.isExecutableFile(atPath: script.path) else {
      showError("找不到脚本", details: "请重新运行 WorkBuddy Dream Skin 安装程序。\n\(script.path)")
      return
    }

    operationCount += 1
    updateBusyState()
    ScriptRunner.run(script: script, arguments: arguments) { [weak self] result in
      guard let self else { return }
      self.operationCount = max(0, self.operationCount - 1)
      self.updateBusyState()
      if result.succeeded {
        self.flashSuccess()
        if showSuccess { self.showSuccess(description, details: result.output) }
      } else {
        self.showError("\(description)失败", details: result.output)
      }
    }
  }

  private func updateBusyState() {
    statusItem.button?.toolTip = operationCount > 0 ? "WorkBuddy Dream Skin 正在处理…" : "WorkBuddy Dream Skin"
  }

  private func flashSuccess() {
    guard let button = statusItem.button else { return }
    let normal = button.image
    button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "完成")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { button.image = normal }
  }

  private func showSuccess(_ title: String, details: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = details.trimmingCharacters(in: .whitespacesAndNewlines).suffix(1400).description
    alert.alertStyle = .informational
    alert.runModal()
  }

  private func showError(_ title: String, details: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = details.trimmingCharacters(in: .whitespacesAndNewlines).suffix(1800).description
    alert.alertStyle = .warning
    alert.runModal()
  }

  private struct ThemeMetadata {
    let id: String
    let name: String
  }

  private func activeThemeMetadata() -> ThemeMetadata? {
    readTheme(at: activeThemeDirectory)
  }

  private func loadSavedThemes() -> [ThemeMetadata] {
    guard let directories = try? fileManager.contentsOfDirectory(
      at: themesDirectory,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }

    return directories.compactMap { directory in
      guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true, values.isSymbolicLink != true else { return nil }
      return readTheme(at: directory)
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func readTheme(at directory: URL) -> ThemeMetadata? {
    let file = directory.appendingPathComponent("theme.json")
    guard let data = try? Data(contentsOf: file),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = object["id"] as? String, !id.isEmpty else { return nil }
    let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return ThemeMetadata(id: id, name: name?.isEmpty == false ? name! : id)
  }
}
