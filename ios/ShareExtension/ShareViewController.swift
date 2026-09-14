//
//  ShareViewController.swift
//  Fluxio Share Extension
//
//  功能：接收系统分享的 URL，保存到 App Group，然后唤起主 App 处理收藏。
//

import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    // App Group ID（需要和主 App 一致）
    let appGroupID = "group.com.plbear.fluxio"

    // 主 App 的 URL Scheme
    let urlScheme = "fluxio://share"

    // 提取到的 URL
    var sharedURL: URL?
    var sharedTitle: String?

    override func isContentValid() -> Bool {
        // 验证分享内容是否有效
        return sharedURL != nil
    }

    override func didSelectPost() {
        // 用户点击"发布"按钮（我们改成"收藏"）
        guard let url = sharedURL else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        // 1. 保存到 App Group UserDefaults
        saveToAppGroup(url: url, title: sharedTitle)

        // 2. 延迟一小段时间，确保保存完成，然后唤起主 App
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.openMainApp()
        }
    }

    override func configurationItems() -> [Any]! {
        // 配置分享界面的选项（我们不需要额外选项）
        return []
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 修改按钮文字
        self.postButtonTitle = "收藏"

        // 提取分享内容
        extractSharedContent()
    }

    // MARK: - 提取分享内容

    private func extractSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            return
        }

        // 遍历附件，寻找 URL 或文本
        for attachment in extensionItem.attachments ?? [] {
            // 1. 尝试加载 URL
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                    DispatchQueue.main.async {
                        if let url = item as? URL {
                            self?.sharedURL = url
                            self?.sharedTitle = extensionItem.attributedContentText?.string
                            self?.validateContent()
                        }
                    }
                }
                return
            }

            // 2. 尝试加载文本（可能包含 URL）
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, error) in
                    DispatchQueue.main.async {
                        if let text = item as? String {
                            // 从文本中提取 URL
                            if let url = self?.extractURL(from: text) {
                                self?.sharedURL = url
                                self?.sharedTitle = text.replacingOccurrences(of: url.absoluteString, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                                self?.validateContent()
                            }
                        }
                    }
                }
                return
            }
        }
    }

    // 从文本中提取 URL
    private func extractURL(from text: String) -> URL? {
        let types: NSTextCheckingResult.CheckingType = [.link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return nil
        }

        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            if let url = match.url {
                return url
            }
        }
        return nil
    }

    // 验证内容并更新 UI
    private func validateContent() {
        if let url = sharedURL {
            self.textView.text = "📥 即将收藏到 Fluxio：\n\(url.absoluteString)"
        } else {
            self.textView.text = "❌ 未检测到可收藏的链接"
        }
        self.validateContent()
    }

    // MARK: - App Group 存储

    private func saveToAppGroup(url: URL, title: String?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            print("⚠️ 无法访问 App Group: \(appGroupID)")
            return
        }

        // 保存分享数据
        let shareData: [String: Any] = [
            "url": url.absoluteString,
            "title": title ?? "",
            "timestamp": Date().timeIntervalSince1970,
            "source": "share_extension"
        ]

        // 读取现有的分享队列（支持多个分享）
        var queue = defaults.array(forKey: "pendingShares") as? [[String: Any]] ?? []
        queue.append(shareData)

        // 只保留最近 10 条
        if queue.count > 10 {
            queue = Array(queue.suffix(10))
        }

        defaults.set(queue, forKey: "pendingShares")
        defaults.synchronize()

        print("✅ 已保存到 App Group: \(url.absoluteString)")
    }

    // MARK: - 唤起主 App

    private func openMainApp() {
        // 构建 URL Scheme
        var components = URLComponents(string: urlScheme)
        if let url = sharedURL {
            components?.queryItems = [
                URLQueryItem(name: "url", value: url.absoluteString),
                URLQueryItem(name: "title", value: sharedTitle ?? "")
            ]
        }

        guard let url = components?.url else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        // 通过 selector 唤起主 App（在 Share Extension 中不能直接用 UIApplication.shared.open）
        let selector = sel_registerName("openURL:")
        var responder = self as UIResponder?
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                break
            }
            responder = current.next
        }

        // 完成分享请求
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
