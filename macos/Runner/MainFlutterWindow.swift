import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // 调用 adb/fastboot 时子进程提前退出会触发 SIGPIPE，默认行为是直接杀死整个应用；
    // 忽略后写入会返回 EPIPE，由 Dart 侧的 try/catch 正常处理。
    signal(SIGPIPE, SIG_IGN)

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPlatformToolsChannel(messenger: flutterViewController.engine.binaryMessenger)

    // MainMenu.xib 中的 APP_NAME 占位符替换为本地化后的应用名（如“退出 柚坛手表助手”）
    let appName = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? ProcessInfo.processInfo.processName
    self.title = appName
    if let mainMenu = NSApp.mainMenu {
      replaceAppNamePlaceholder(in: mainMenu, with: appName)
    }

    super.awakeFromNib()
  }

  /// Android File Transfer 及其菜单栏常驻的 Agent。它们会独占 USB 连接的安卓设备，导致 adb 无法识别
  private static let androidFileTransferBundleIds: Set<String> = [
    "com.google.android.mtpagent",
    "com.google.android.mtpviewer",
  ]

  /// 与 lib/platform_tools.dart 的 `wearbox/platform_tools` 通道对应
  private func registerPlatformToolsChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "wearbox/platform_tools", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAndroidFileTransferRunning":
        // NSWorkspace 在 App 沙盒中同样可用
        let running = NSWorkspace.shared.runningApplications.contains {
          $0.bundleIdentifier.map(Self.androidFileTransferBundleIds.contains) ?? false
        }
        result(running)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func replaceAppNamePlaceholder(in menu: NSMenu, with appName: String) {
    menu.title = menu.title.replacingOccurrences(of: "APP_NAME", with: appName)
    for item in menu.items {
      item.title = item.title.replacingOccurrences(of: "APP_NAME", with: appName)
      if let submenu = item.submenu {
        replaceAppNamePlaceholder(in: submenu, with: appName)
      }
    }
  }
}
