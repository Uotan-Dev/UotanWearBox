import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'app_sidebar.dart';

int _iosMajorVersion() {
  // iOS 上形如 "Version 26.1 (Build 23B85)"
  final Match? match =
      RegExp(r'(\d+)\.').firstMatch(Platform.operatingSystemVersion);
  return match == null ? 0 : int.parse(match.group(1)!);
}

/// iOS 26 起底部导航栏使用原生 UITabBar（系统液态玻璃样式），更低版本仍用 miuix 导航栏
final bool useNativeTabBar =
    !kIsWeb && Platform.isIOS && _iosMajorVersion() >= 26;

/// 原生液态玻璃底部导航栏（ios/Runner/NativeTabBar.swift）。
///
/// 悬浮在页面之上，页面内容从玻璃下方透出；高度为 [height] 加上手势导航条高度。
class NativeTabBar extends StatefulWidget {
  const NativeTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.dark,
  });

  final List<AppSidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool dark;

  /// 导航栏高度（不含手势导航条），页面底部需留出这部分空间
  static const double height = 49;

  @override
  State<NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<NativeTabBar> {
  static const String _viewType = 'wearbox/native_tab_bar';

  MethodChannel? _channel;

  Map<String, Object> _params() => {
        // 图标为 Assets.xcassets 中的 tab_<侧边栏图标名>，与 miuix 导航栏同一套 SVG
        'items': [
          for (final AppSidebarItem item in widget.items)
            {
              'label': item.label,
              'icon': item.icon,
              'selectedIcon': item.selectedIcon,
            },
        ],
        'selected': widget.selectedIndex,
        'dark': widget.dark,
        // 颜色与 AppBottomBar（miuix 导航栏）一致；图标与文字同色
        'iconColor': (widget.dark ? MiuixThemeData.dark() : MiuixThemeData.light())
            .colors
            .onSurfaceContainer
            .toARGB32(),
        'unselectedAlpha': MiuixNavigationBarDefaults.unselectedAlpha,
      };

  void _onCreated(int id) {
    final MethodChannel channel = MethodChannel('${_viewType}_$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'select' && call.arguments is int) {
        widget.onSelected(call.arguments as int);
      }
    });
    _channel = channel;
    // 创建期间参数可能已变化（如滑动切换了页面），同步一次
    channel.invokeMethod<void>('update', _params());
  }

  @override
  void didUpdateWidget(NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _channel?.invokeMethod<void>('update', _params());
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: _viewType,
      creationParams: _params(),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onCreated,
      // 触摸全部交给原生导航栏（含 iOS 26 在导航项间拖动切换的手势）
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}
