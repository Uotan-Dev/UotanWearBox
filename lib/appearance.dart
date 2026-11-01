import 'platform_support.dart';
import 'app_theme.dart';
import 'blur_menu.dart';
import 'miuix_titled_page.dart';
import 'package:watch_assistant/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 界面显示：语言设置、深色模式
class AppearancePage extends StatefulWidget {
  const AppearancePage({
    super.key,
    required this.onLocaleChanged,
    required this.currentLocale,
    required this.onThemeModeChanged,
    required this.themeMode,
  });

  final ValueChanged<Locale?> onLocaleChanged;
  final Locale? currentLocale;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeMode themeMode;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  // 路由不会随设置页重建，当前选择由本页自行保存
  late Locale? _locale = widget.currentLocale;
  late ThemeMode _themeMode = widget.themeMode;

  void _setLocale(Locale? locale) {
    setState(() => _locale = locale);
    widget.onLocaleChanged(locale);
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final String currentLanguage = _locale?.languageCode ?? 'system';
    const List<String> languageValues = ['system', 'zh', 'en', 'ja'];
    final List<String> languageLabels = [
      l10n.languageSystem,
      '简体中文',
      'English',
      '日本語',
    ];
    const List<ThemeMode> themeValues = [
      ThemeMode.system,
      ThemeMode.dark,
      ThemeMode.light,
    ];
    final List<String> themeLabels = [
      l10n.themeModeSystem,
      l10n.themeModeAlwaysOn,
      l10n.themeModeAlwaysOff,
    ];

    if (isNarrowLayout(context)) {
      final int languageIndex = languageValues.indexOf(currentLanguage);
      return MiuixTitledPage(
        title: l10n.settingsAppearanceTitle,
        showBackButton: true,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            MiuixGroupCard(
              children: [
                MiuixOverlayDropdownPreference(
                  title: l10n.settingsLanguageTitle,
                  items: languageLabels,
                  selectedIndex: languageIndex < 0 ? 0 : languageIndex,
                  onSelectedIndexChange: (index) => _setLocale(
                      index == 0 ? null : Locale(languageValues[index])),
                ),
                MiuixOverlayDropdownPreference(
                  title: l10n.settingsDarkModeTitle,
                  items: themeLabels,
                  selectedIndex: themeValues.indexOf(_themeMode),
                  onSelectedIndexChange: (index) =>
                      _setThemeMode(themeValues[index]),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90.0), // 设置 AppBar 的高度
        child: Padding(
          padding: const EdgeInsets.only(top: 40), // 设置顶部边距
          child: GestureDetector(
            onPanStart: (details) => startWindowDrag(), // 允许拖动窗口
            child: Container(
              color: Colors.transparent, // 设置为透明背景
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back,
                        color: context.palette.text, size: 20), // 返回图标
                    onPressed: () {
                      Navigator.pop(context); // 返回到上一个页面
                    },
                  ),
                  const SizedBox(width: 5),
                  Text(
                    l10n.settingsAppearanceTitle, // 页面标题
                    style: TextStyle(
                      color: context.palette.text,
                      fontSize: 26,
                      fontFamily: 'MiSansLight', // 使用自定义字体
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        children: [
          _buildCard(
            context,
            title: l10n.settingsLanguageTitle,
            trailing: BlurDropdown<String>(
              value: currentLanguage,
              onChanged: (value) =>
                  _setLocale(value == 'system' ? null : Locale(value)),
              items: [
                for (final (int i, String value) in languageValues.indexed)
                  BlurMenuItem(value: value, label: languageLabels[i]),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            title: l10n.settingsDarkModeTitle,
            trailing: BlurDropdown<ThemeMode>(
              value: _themeMode,
              onChanged: _setThemeMode,
              items: [
                for (final (int i, ThemeMode value) in themeValues.indexed)
                  BlurMenuItem(value: value, label: themeLabels[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required Widget trailing,
  }) {
    return Material(
      color: context.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: ListTile(
          title: Text(title),
          trailing: trailing,
        ),
      ),
    );
  }
}
