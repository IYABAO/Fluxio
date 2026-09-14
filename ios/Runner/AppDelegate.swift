import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // 分享接收 MethodChannel
  private var shareChannel: FlutterMethodChannel?

  // App Group ID（必须和 Share Extension 一致）
  let appGroupID = "group.com.plbear.fluxio"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 注册分享接收 Channel
    if let controller = window?.rootViewController as? FlutterViewController {
      shareChannel = FlutterMethodChannel(name: "com.plbear.fluxio/share", binaryMessenger: controller.binaryMessenger)
      shareChannel?.setMethodCallHandler { [weak self] (call, result) in
        self?.handleMethodCall(call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - URL Scheme 唤起处理

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // 处理 fluxio://share?url=xxx&title=xxx
    if url.scheme == "fluxio", url.host == "share" {
      handleShareURL(url)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  // 处理分享 URL
  private func handleShareURL(_ url: URL) {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let urlParam = components?.queryItems?.first(where: { $0.name == "url" })?.value
    let titleParam = components?.queryItems?.first(where: { $0.name == "title" })?.value

    guard let sharedURL = urlParam, !sharedURL.isEmpty else {
      return
    }

    // 通知 Flutter 层
    shareChannel?.invokeMethod("onShareReceived", arguments: [
      "url": sharedURL,
      "title": titleParam ?? ""
    ])
  }

  // MARK: - MethodChannel 处理

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPendingShares":
      // 从 App Group 读取待处理的分享队列
      let shares = getPendingSharesFromAppGroup()
      result(shares)

    case "clearPendingShares":
      // 清空 App Group 中的分享队列
      clearPendingSharesInAppGroup()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - App Group 读写

  // 从 App Group UserDefaults 读取待处理的分享队列
  private func getPendingSharesFromAppGroup() -> [[String: Any]] {
    guard let defaults = UserDefaults(suiteName: appGroupID) else {
      print("⚠️ 无法访问 App Group: \(appGroupID)")
      return []
    }

    let shares = defaults.array(forKey: "pendingShares") as? [[String: Any]] ?? []
    print("✅ 从 App Group 读取到 \(shares.count) 条待处理分享")
    return shares
  }

  // 清空 App Group 中的分享队列
  private func clearPendingSharesInAppGroup() {
    guard let defaults = UserDefaults(suiteName: appGroupID) else {
      return
    }
    defaults.removeObject(forKey: "pendingShares")
    defaults.synchronize()
    print("✅ 已清空 App Group 分享队列")
  }
}
