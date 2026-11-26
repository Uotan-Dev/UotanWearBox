import 'miuix_dialog.dart';
import 'app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:watch_assistant/utils.dart';
import 'package:watch_assistant/l10n/l10n.dart';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'adb_device_info.dart';
import 'app_prefs.dart';
import 'privacy_consent.dart';
import 'app_sidebar.dart';
import 'native_tab_bar.dart';
import 'page1.dart';
import 'page2.dart';
import 'page3.dart';
import 'page_transition.dart';
import 'platform_support.dart';
import 'platform_tools.dart';
import 'store_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onLocaleChanged,
    required this.locale,
    required this.onThemeModeChanged,
    required this.themeMode,
  });

  final ValueChanged<Locale?> onLocaleChanged;
  final Locale? locale;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeMode themeMode;

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  int _selectedIndex = 0;

  // 当前显示的导航项；应用中心可在设置 → 功能中关闭
  late List<String> _tabs = _buildTabs();

  static List<String> _buildTabs() => [
        'home',
        'features',
        if (appCenterEnabled.value) 'store',
        'settings',
      ];

  String get _selectedTab => _tabs[_selectedIndex];

  // 开关应用中心后保持停留在原来的导航项上
  void _onAppCenterChanged() {
    final String current = _selectedTab;
    setState(() {
      _tabs = _buildTabs();
      final int index = _tabs.indexOf(current);
      _selectedIndex = index < 0 ? 0 : index;
      // 页数变化，窄屏分页按新位置重建
      _releasePageController();
    });
  }

  List<AdbDeviceInfo> _devices = []; // 用于存储设备信息
  static const String currentVersion = '17.0.1'; // 当前应用版本号（与 pubspec 的 version 一致）
  bool _isCheckingUpdate = true; // 是否显示启动页

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    appCenterEnabled.addListener(_onAppCenterChanged);
    checkAdbDevicesPeriodically(
      setState: setState,
      onDevicesUpdated: (devices) {
        setState(() {
          _devices = devices;
        });
      },
    );
    _finishStartup();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    appCenterEnabled.removeListener(_onAppCenterChanged);
    _pageController?.dispose();
    super.dispose();
  }

  List<Widget> _pages = [];

  // 短暂显示启动页后进入主界面
  Future<void> _finishStartup() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) {
      return;
    }
    setState(() {
      _isCheckingUpdate = false;
    });
    // 首次使用需先同意用户协议和隐私政策（不同意则退出），之后才访问网络
    await ensurePrivacyConsent(context);
    if (!mounted) {
      return;
    }
    // 进入主界面后在后台检查更新，不阻塞使用；仅有新版本时弹出提示，失败时静默
    _checkForUpdates();
    _warnIfAndroidFileTransferRunning();
  }

  bool _androidFileTransferWarningShown = false;

  /// macOS 上 Android File Transfer 会独占 USB 连接的安卓设备，导致无法识别手表。
  /// 启动时提示一次；之后用户手动刷新且仍未检测到设备时再次提示
  Future<void> _warnIfAndroidFileTransferRunning({bool force = false}) async {
    if (_androidFileTransferWarningShown && !force) {
      return;
    }
    if (!await isAndroidFileTransferRunning() || !mounted) {
      return;
    }
    _androidFileTransferWarningShown = true;
    final l10n = context.l10n;
    await showMiuixDialog<void>(
      context: context,
      builder: (context) => MiuixAlertDialog(
        backgroundColor: context.palette.surface,
        title: Text(l10n.androidFileTransferRunningTitle),
        content: Text(l10n.androidFileTransferRunningMessage),
        actions: [
          MiuixDialogButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.dialogOk),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshDevicesNow() async {
    try {
      final List<AdbDeviceInfo> devices = await fetchAdbDevices();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
      });
      if (devices.isEmpty) {
        await _warnIfAndroidFileTransferRunning(force: true);
      }
    } catch (e) {
      print('Failed to refresh devices: $e');
    }
  }

  // 检查远程版本号是否最新，有新版本时弹出更新提示
  Future<UpdateCheckResult> _checkForUpdates() async {
    try {
      final response = await http.get(
        Uri.parse('https://wear.gnayoah.com/version/windows.txt'),
      );

      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        final remoteVersion = lines
            .firstWhere((line) => line.startsWith('[version]'))
            .replaceAll('[version]', '')
            .trim();

        final releaseDate = lines
            .firstWhere((line) => line.startsWith('[date]'))
            .replaceAll('[date]', '')
            .trim();

        if (_compareVersions(remoteVersion, currentVersion) > 0) {
          if (mounted) {
            _showUpdateDialog(remoteVersion, releaseDate);
          }
          return UpdateCheckResult.available;
        }
        return UpdateCheckResult.upToDate;
      } else {
        print('Failed to load version info');
      }
    } catch (e) {
      print('Error checking version: $e');
    }
    return UpdateCheckResult.failed;
  }

  // 显示更新提示框，带有发布日期和去更新按钮
  /// 按「主.次.修订」逐段比较版本号（如 17.0.1 与 16.2），a 较新返回正数
  static int _compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final List<int> pa = parts(a), pb = parts(b);
    for (int i = 0; i < pa.length || i < pb.length; i++) {
      final int x = i < pa.length ? pa[i] : 0;
      final int y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  void _showUpdateDialog(String remoteVersion, String releaseDate) {
    showMiuixDialog(
      context: context,
      barrierDismissible: true, // 非强制更新，允许点击对话框外部区域关闭
      builder: (BuildContext context) {
        final l10n = context.l10n;
        return MiuixAlertDialog(
          backgroundColor: context.palette.surface, // 弹窗背景颜色
          title: Text(l10n.updateDialogTitle),
          content: Text(l10n.updateDialogMessage(remoteVersion, releaseDate)),
          actions: [
            MiuixDialogButton(
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.pressed) ||
                        states.contains(MaterialState.hovered)) {
                      return context.palette.button; // 点击或悬浮时的背景颜色
                    }
                    return null; // 默认状态下不更改颜色
                  },
                ),
                foregroundColor: MaterialStateProperty.all<Color>(
                    context.palette.text), // 文本颜色
              ),
              // 商店版本只能通过商店更新，仅提示有新版本，不提供跳转下载
              child: Text(
                  isStoreBuild ? l10n.dialogOk : l10n.updateDialogLater),
              onPressed: () {
                Navigator.of(context).pop(); // 关闭对话框
              },
            ),
            if (!isStoreBuild)
              MiuixDialogButton(
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.pressed) ||
                        states.contains(MaterialState.hovered)) {
                      return context.palette.button; // 点击或悬浮时的背景颜色
                    }
                    return null; // 默认状态下不更改颜色
                  },
                ),
                foregroundColor: MaterialStateProperty.all<Color>(
                    context.palette.text), // 文本颜色
              ),
              child: Text(l10n.updateDialogUpdate),
              onPressed: () {
                _launchURL(); // 点击跳转到浏览器
              },
            ),
          ],
        );
      },
    );
  }

  // 打开浏览器跳转到指定URL
  void _launchURL() async {
    const url = 'https://wear.gnayoah.com';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  // 窗口宽度小于该值时切换为底部导航栏布局
  static const double _narrowLayoutBreakpoint = 600;

  // 每个导航项拥有独立的嵌套 Navigator，二级页面在内容区域内打开，侧边栏保持显示
  final Map<String, GlobalKey<NavigatorState>> _navigatorKeys = {
    for (final String tab in ['home', 'features', 'store', 'settings'])
      tab: GlobalKey<NavigatorState>(),
  };

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) {
      // 再次点击当前导航项时返回该栏目的首页
      _navigatorKeys[_tabs[index]]!
          .currentState
          ?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    // 窄屏：像原生分页一样连续滚动到目标页，跨页时会经过中间的页面
    final PageController? controller = _pageController;
    if (controller != null && controller.hasClients) {
      final int token = ++_pageAnimationToken;
      controller
          .animateToPage(
        index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() {
        // 只有最后一次点击触发的动画结束时才恢复跟随滑动
        if (token == _pageAnimationToken) {
          _pageAnimationToken = 0;
          // 动画被手指按住打断时页面停在别处，导航栏选中项与实际页面对齐
          if (mounted && controller.hasClients) {
            final int page = controller.page?.round() ?? index;
            if (page != _selectedIndex && page >= 0 && page < _tabs.length) {
              setState(() {
                _selectedIndex = page;
              });
            }
          }
        }
      });
    }
  }

  // 窄屏分页控制器：进入窄屏布局时按当前页创建，切换到宽屏时释放
  PageController? _pageController;

  // 非 0 表示正在执行点击导航触发的翻页动画，此时忽略经过中间页时的 onPageChanged
  int _pageAnimationToken = 0;

  void _releasePageController() {
    final PageController? controller = _pageController;
    if (controller == null) {
      return;
    }
    _pageController = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  // 窄屏页面容器：可左右滑动切换，与底部导航栏联动
  Widget _buildNarrowPager() {
    final PageController controller =
        _pageController ??= PageController(initialPage: _selectedIndex);
    return PageView(
      controller: controller,
      onPageChanged: (index) {
        if (_pageAnimationToken != 0 || index == _selectedIndex) {
          return;
        }
        setState(() {
          _selectedIndex = index;
        });
      },
      children: _pages,
    );
  }

  // 宽屏内容区域：一级页面作为嵌套 Navigator 的根页面
  Widget _buildContent() {
    return Navigator(
      key: _navigatorKeys[_selectedTab],
      pages: [
        MaterialPage(
          key: ValueKey('tab_$_selectedTab'),
          child: _pages[_selectedIndex],
        ),
      ],
      onDidRemovePage: (_) {},
    );
  }

  // 切换导航项时新页面淡入并轻微上移。
  // 只做入场动画、不与旧页面交叉淡化：旧页面的嵌套 Navigator 使用 GlobalKey，
  // 快速来回切换时两份同 key 的页面同时存在会报错
  Widget _buildTabTransition(Widget child) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(_selectedTab),
      tween: Tween<double>(begin: 0, end: 1),
      duration: kPageEnterDuration,
      curve: kPageEnterCurve,
      builder: (context, t, child) => fadeRise(t, child!),
      child: child,
    );
  }

  // 侧边栏与底部导航栏共用的导航项
  List<AppSidebarItem> _navItems(BuildContext context) {
    final Map<String, AppSidebarItem> items = {
      'home': AppSidebarItem(
        icon: 'home',
        selectedIcon: 'home_filled',
        label: context.l10n.navigationHome,
      ),
      'features': AppSidebarItem(
        icon: 'features',
        selectedIcon: 'features_filled',
        label: context.l10n.navigationFeatures,
      ),
      'store': AppSidebarItem(
        icon: 'store',
        selectedIcon: 'store_filled',
        label: context.l10n.navigationStore,
      ),
      'settings': AppSidebarItem(
        icon: 'settings',
        selectedIcon: 'settings_filled',
        label: context.l10n.navigationAbout,
      ),
    };
    return [for (final String tab in _tabs) items[tab]!];
  }

  // 宽屏布局：左侧导航栏
  Widget _buildWideLayout(BuildContext context) {
    _releasePageController();
    return Row(
      children: [
        AppSidebar(
          selectedIndex: _selectedIndex,
          onSelected: _onDestinationSelected,
          items: _navItems(context),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: _buildTabTransition(_buildContent()),
        ),
      ],
    );
  }

  // 窄屏布局：底部导航栏
  Widget _buildNarrowLayout(BuildContext context) {
    if (useNativeTabBar) {
      return _buildNativeNarrowLayout(context);
    }
    // 窄屏下二级页面仍全屏打开，不保留底部导航栏
    return Column(
      children: [
        Expanded(
          // 页面位于导航栏上方，手势导航条的高度由导航栏处理，不再传给页面
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: _buildNarrowPager(),
          ),
        ),
        AppBottomBar(
          items: _navItems(context),
          selectedIndex: _selectedIndex,
          onSelected: _onDestinationSelected,
        ),
      ],
    );
  }

  // iOS 26+ 窄屏布局：原生液态玻璃导航栏悬浮在页面之上，页面铺满全屏，
  // 底部安全区加上导航栏高度后传给页面，滚动内容可从玻璃下方透出
  Widget _buildNativeNarrowLayout(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double barHeight = media.padding.bottom + NativeTabBar.height;
    return Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(bottom: barHeight),
            ),
            child: _buildNarrowPager(),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: barHeight,
          child: NativeTabBar(
            items: _navItems(context),
            selectedIndex: _selectedIndex,
            onSelected: _onDestinationSelected,
            dark: context.palette.isDark,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 每次构建都生成新的列表：PageView 按列表实例判断子页面是否需要重建，
    // 原地修改同一个列表会导致设备连接等状态变化不刷新，直到切换页面
    _pages = [
      for (final String tab in _tabs)
        switch (tab) {
          'home' => Page1(
              devices: _devices,
              onRefreshDevices: _refreshDevicesNow,
            ),
          'features' => const Page2(),
          'store' => const StorePage(),
          _ => Page3(
              onLocaleChanged: widget.onLocaleChanged,
              currentLocale: widget.locale,
              onThemeModeChanged: widget.onThemeModeChanged,
              themeMode: widget.themeMode,
              currentVersion: currentVersion,
              onCheckUpdate: _checkForUpdates,
            ),
        },
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500), // 动画时长
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child); // 使用淡入淡出过渡
        },
        child: _isCheckingUpdate
            ? Center(
                key: const ValueKey('loading'), // 唯一键值
                child: Image.asset(
                  'assets/logo2.png',
                  width: 96,
                  height: 96,
                ),
              )
            : LayoutBuilder(
                key: const ValueKey('content'), // 唯一键值
                builder: (context, constraints) {
                  // 窄屏（窄窗口 / 移动端）时将侧边栏移动到页面底部
                  if (constraints.maxWidth < _narrowLayoutBreakpoint) {
                    return _buildNarrowLayout(context);
                  }
                  return _buildWideLayout(context);
                },
              ),
      ),
    );
  }
}
