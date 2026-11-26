import Flutter
import UIKit

/// 原生 UITabBar 平台视图：iOS 26 起系统自动绘制为液态玻璃样式。
/// Flutter 端通过 `wearbox/native_tab_bar_<id>` 通道下发导航项、选中项与深浅色，
/// 用户点击时回传 `select`。
final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "wearbox/native_tab_bar"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeTabBarView(frame: frame, viewId: viewId, args: args, messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class NativeTabBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: UIView
  private let tabBar = UITabBar()
  private let channel: FlutterMethodChannel
  /// 当前导航项（label + SF Symbol），未变化时不重建，以保留系统的选中动画
  private var itemKeys: [String] = []

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(NativeTabBarFactory.viewType)_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    container.backgroundColor = .clear
    tabBar.delegate = self
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: container.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    apply(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.apply(call.arguments)
      result(nil)
    }
  }

  func view() -> UIView { container }

  private func apply(_ args: Any?) {
    guard let dict = args as? [String: Any] else { return }

    if let dark = dict["dark"] as? Bool {
      container.overrideUserInterfaceStyle = dark ? .dark : .light
    }

    // 与 miuix 导航栏一致：选中为图标色，未选中为其一定透明度（图标与文字同色）
    let iconColor = Self.color(dict["iconColor"]) ?? .label
    let unselectedAlpha = CGFloat(dict["unselectedAlpha"] as? Double ?? 0.4)
    let unselectedColor = iconColor.withAlphaComponent(unselectedAlpha)
    tabBar.tintColor = iconColor
    tabBar.unselectedItemTintColor = unselectedColor

    if let rawItems = dict["items"] as? [[String: Any]] {
      // 颜色随深浅色变化，一并作为是否重建的依据
      let colorKey = "\(dict["iconColor"] ?? "")|\(unselectedAlpha)"
      let keys = rawItems.map {
        "\($0["label"] ?? "")|\($0["icon"] ?? "")|\($0["selectedIcon"] ?? "")|\(colorKey)"
      }
      if keys != itemKeys {
        itemKeys = keys
        let items = rawItems.enumerated().map { index, raw -> UITabBarItem in
          let label = raw["label"] as? String ?? ""
          // iOS 26 液态玻璃会把未选中的系统文字强制为系统文字色（设置颜色 / 外观均无效），
          // 因此不用系统标题，而是把图标（Assets.xcassets 中的 tab_* SVG）和文字一起按原色绘制成一张图
          func image(_ key: String, _ color: UIColor) -> UIImage? {
            guard let name = raw[key] as? String,
                  let source = UIImage(named: "tab_\(name)") else { return nil }
            let text = NSAttributedString(string: label, attributes: [
              .font: Self.labelFont,
              .foregroundColor: color,
            ])
            let textSize = text.size()
            // SVG 画布为 24pt，图形只占约 2/3，放大绘制以接近系统图标的视觉大小（矢量资源，放大不糊）
            let width = max(Self.iconSize, ceil(textSize.width))
            let size = CGSize(width: width, height: Self.iconSize + Self.labelSpacing + ceil(textSize.height))
            return UIGraphicsImageRenderer(size: size).image { _ in
              source.withTintColor(color).draw(in: CGRect(
                x: (width - Self.iconSize) / 2, y: 0, width: Self.iconSize, height: Self.iconSize
              ))
              text.draw(at: CGPoint(
                x: (width - textSize.width) / 2, y: Self.iconSize + Self.labelSpacing
              ))
            }.withRenderingMode(.alwaysOriginal)
          }
          let item = UITabBarItem(title: nil, image: image("icon", unselectedColor), tag: index)
          item.selectedImage = image("selectedIcon", iconColor)
          item.accessibilityLabel = label
          return item
        }
        tabBar.setItems(items, animated: false)
      }
    }

    if let selected = dict["selected"] as? Int,
       let items = tabBar.items, selected >= 0, selected < items.count,
       tabBar.selectedItem !== items[selected] {
      tabBar.selectedItem = items[selected]
    }
  }

  /// 导航栏图标绘制尺寸（pt）
  private static let iconSize: CGFloat = 27
  /// 导航项文字字体与图文间距，接近系统导航栏标题样式
  private static let labelFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
  private static let labelSpacing: CGFloat = 1

  /// Flutter 传来的 ARGB 整数 → UIColor
  private static func color(_ value: Any?) -> UIColor? {
    guard let argb = (value as? NSNumber)?.uint32Value else { return nil }
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("select", arguments: item.tag)
  }
}
