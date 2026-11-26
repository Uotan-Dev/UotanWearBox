import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Mac App Store 版 adb 服务使用的端口，与 lib/platform_tools.dart 的 macAppStoreAdbPort 一致
  private static let macAppStoreAdbPort = "15037"

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    stopSandboxedAdbServer()
    super.applicationWillTerminate(notification)
  }

  /// App 沙盒中（Mac App Store 版）退出时关闭随 App 启动的 adb 后台服务，
  /// 避免 App 退出后仍有进程在运行（App Store 审核指南 2.4.5）
  private func stopSandboxedAdbServer() {
    let environment = ProcessInfo.processInfo.environment
    guard environment["APP_SANDBOX_CONTAINER_ID"] != nil,
          let adb = Bundle.main.url(
            forResource: "adb", withExtension: nil, subdirectory: "platform-tools")
    else { return }
    let process = Process()
    process.executableURL = adb
    process.arguments = ["kill-server"]
    var adbEnvironment = environment
    adbEnvironment["ANDROID_ADB_SERVER_PORT"] = Self.macAppStoreAdbPort
    process.environment = adbEnvironment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      NSLog("WearBox: failed to stop adb server: \(error)")
    }
  }
}
