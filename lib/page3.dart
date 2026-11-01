import 'app_snackbar.dart';
import 'miuix_titled_page.dart';
import 'platform_support.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'about/about.dart';
import 'appearance.dart';
import 'features_settings.dart';
import 'about/question.dart';
import 'l10n/l10n.dart';

class Page3 extends StatelessWidget {
  const Page3({
    super.key,
    required this.onLocaleChanged,
    required this.currentLocale,
    required this.currentVersion,
    required this.onThemeModeChanged,
    required this.themeMode,
    required this.onCheckUpdate,
  });

  final ValueChanged<Locale?> onLocaleChanged;
  final Locale? currentLocale;
  final String currentVersion;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeMode themeMode;

  /// 手动检查更新；有新版本时由调用方弹出更新提示
  final Future<UpdateCheckResult> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final appearanceOptions = [
      _SettingOption(
        icon: Icons.palette_outlined,
        svg: 'appearance',
        title: l10n.settingsAppearanceTitle,
        subtitle: l10n.settingsAppearanceSubtitle,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppearancePage(
                onLocaleChanged: onLocaleChanged,
                currentLocale: currentLocale,
                onThemeModeChanged: onThemeModeChanged,
                themeMode: themeMode,
              ),
            ),
          );
        },
      ),
      _SettingOption(
        svg: 'features',
        title: l10n.settingsFeaturesTitle,
        subtitle: l10n.settingsFeaturesSubtitle,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const FeaturesSettingsPage()),
          );
        },
      ),
    ];

    final faqOptions = [
      _SettingOption(
        iconPath:
            'assets/icons/help_24dp_5F6368_FILL0_wght400_GRAD0_opsz24.png',
        svg: 'faq',
        title: l10n.settingsFaqTitle,
        subtitle: l10n.settingsFaqSubtitle,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FAQPage()),
          );
        },
      ),
      //_SettingOption(
      //  iconPath:
      //      'assets/icons/feedback_24dp_5F6368_FILL0_wght400_GRAD0_opsz24.png',
      //  title: l10n.settingsFeedbackTitle,
      //  subtitle: l10n.settingsFeedbackSubtitle,
      //  onTap: () {
      //    _launchEmail(l10n.feedbackEmailSubject, l10n.feedbackEmailBody);
      //  },
      //),
    ];

    final aboutOptions = [
      _SettingOption(
        iconPath:
            'assets/icons/aod_watch_24dp_5F6368_FILL0_wght400_GRAD0_opsz24.png',
        svg: 'about',
        title: l10n.settingsAboutTitle,
        subtitle: 'v$currentVersion',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AboutPage()),
          );
        },
      ),
    ];

    if (isNarrowLayout(context)) {
      return MiuixTitledPage(
        title: l10n.settingsPageTitle,
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(
                12, 0, 12, 20 + MediaQuery.paddingOf(context).bottom),
            children: [
              _buildMiuixSectionTitle(context, l10n.setting_config),
              _buildMiuixGroup([
                for (final option in appearanceOptions)
                  MiuixArrowPreference(
                    title: option.title,
                    startAction: buildSettingsIcon(option.svg),
                    onClick: option.onTap,
                  ),
              ]),
              // 常见问题、检查更新、关于
              const SizedBox(height: 10),
              _buildMiuixSectionTitle(context, l10n.settingsSectionAbout),
              _buildMiuixGroup([
                for (final option in faqOptions)
                  MiuixArrowPreference(
                    title: option.title,
                    startAction: buildSettingsIcon(option.svg),
                    onClick: option.onTap,
                  ),
                _CheckUpdateCard(
                  onCheckUpdate: onCheckUpdate,
                  currentVersion: currentVersion,
                ),
                for (final option in aboutOptions)
                  MiuixArrowPreference(
                    title: option.title,
                    startAction: buildSettingsIcon(option.svg),
                    onClick: option.onTap,
                  ),
              ]),
              const SizedBox(height: 10),
              _buildMiuixSectionTitle(context, l10n.settingsFooter),
            ],
          ),
        ),
      );
    }

    final Widget list = ListView(
      padding: const EdgeInsets.only(left: 20.0, right: 20, bottom: 20),
      children: [
        _buildSectionTitle(context, l10n.setting_config),
        const SizedBox(height: 2),
        ..._buildOptions(context, appearanceOptions),
        // 常见问题、检查更新、关于
        const SizedBox(height: 10),
        _buildSectionTitle(context, l10n.settingsSectionAbout),
        const SizedBox(height: 2),
        ..._buildOptions(context, faqOptions),
        const SizedBox(height: 10),
        _CheckUpdateCard(
          onCheckUpdate: onCheckUpdate,
          currentVersion: currentVersion,
        ),
        const SizedBox(height: 10),
        ..._buildOptions(context, aboutOptions),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.settingsFooter,
              style: TextStyle(
                fontSize: 15,
                color: context.palette.textSecondary,
                fontFamily: 'MiSansLight',
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
      ],
    );
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70.0), // 设置AppBar的高度
        child: Padding(
          padding: const EdgeInsets.only(top: 20), // 设置顶部边距
          child: GestureDetector(
            onPanStart: (details) => startWindowDrag(), // 允许拖动窗口
            child: Container(
              color: Colors.transparent, // 设置为透明背景
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // 左右对齐
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 20), // 调整这个值控制标题往下移动的距离
                    child: Text(
                      l10n.settingsPageTitle,
                      style: TextStyle(
                        color: context.palette.text,
                        fontSize: 26,
                        fontFamily: 'MiSansLight', // 使用自定义字体
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.settingsVersionLabel(currentVersion),
                style: TextStyle(fontSize: 16, fontFamily: 'MiSansLight'),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: list,
          ),
        ],
      ),
    );
  }

  Widget _buildMiuixGroup(List<Widget> children) {
    return MiuixCard(
      child: ClipPath(
        clipper: const ShapeBorderClipper(
          shape: MiuixSquircleBorder(
            cornerRadius: MiuixCardDefaults.cornerRadius,
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _buildMiuixSectionTitle(BuildContext context, String title) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MiuixBasicComponentDefaults.insideMargin.left,
        8,
        MiuixBasicComponentDefaults.insideMargin.right,
        8,
      ),
      child: MiuixText(
        title,
        style: theme.textStyles.footnote1,
        color: theme.colors.onBackgroundVariant,
      ),
    );
  }

  Padding _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            color: context.palette.textSecondary,
            fontFamily: 'MiSansLight',
          ),
        ),
      ),
    );
  }

  List<Widget> _buildOptions(
      BuildContext context, List<_SettingOption> options) {
    final widgets = <Widget>[];
    for (final option in options) {
      widgets.add(_buildOptionCard(context, option));
      widgets.add(const SizedBox(height: 10));
    }
    if (widgets.isNotEmpty) {
      widgets.removeLast();
    }
    return widgets;
  }

  Widget _buildOptionCard(BuildContext context, _SettingOption option) {
    return Material(
      color: context.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        onTap: option.onTap,
        child: Padding(
          padding: const EdgeInsets.all(5.0),
          child: ListTile(
            title: Text(option.title),
            subtitle: Text(option.subtitle),
            leading: option.svg != null
                ? buildWideSettingsIcon(context, option.svg!)
                : option.iconPath != null
                ? Image.asset(
                    option.iconPath!,
                    width: 20,
                    height: 20,
                    color: context.palette.text,
                  )
                : Icon(option.icon, size: 20),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 14,
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _launchEmail(String subject, String body) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'feedback@Gnayoah.com',
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      debugPrint('无法发送邮件至: ${emailUri.toString()}');
    }
  }
}

/// 窄屏设置项行首的 svg 图标
Widget? buildSettingsIcon(String? name) {
  if (name == null) {
    return null;
  }
  return Builder(
    builder: (context) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: SvgPicture.asset(
        'assets/settings/$name.svg',
        width: 22,
        height: 22,
        colorFilter: ColorFilter.mode(
          MiuixTheme.of(context).colors.onBackground,
          BlendMode.srcIn,
        ),
      ),
    ),
  );
}

/// 宽屏设置项卡片的 svg 图标，与窄屏共用 assets/settings/ 下的图标
Widget buildWideSettingsIcon(BuildContext context, String name) {
  return SvgPicture.asset(
    'assets/settings/$name.svg',
    width: 22,
    height: 22,
    colorFilter: ColorFilter.mode(context.palette.text, BlendMode.srcIn),
  );
}

/// 检查更新的结果
enum UpdateCheckResult { available, upToDate, failed }

class _CheckUpdateCard extends StatefulWidget {
  const _CheckUpdateCard({
    required this.onCheckUpdate,
    required this.currentVersion,
  });

  final Future<UpdateCheckResult> Function() onCheckUpdate;
  final String currentVersion;

  @override
  State<_CheckUpdateCard> createState() => _CheckUpdateCardState();
}

class _CheckUpdateCardState extends State<_CheckUpdateCard> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    final UpdateCheckResult result = await widget.onCheckUpdate();
    if (!mounted) {
      return;
    }
    setState(() => _checking = false);
    // 有新版本时已弹出更新提示，这里只提示无更新或失败
    final String? message = switch (result) {
      UpdateCheckResult.available => null,
      UpdateCheckResult.upToDate => context.l10n.updateUpToDate,
      UpdateCheckResult.failed => context.l10n.updateCheckFailed,
    };
    if (message != null) {
      showAppSnackbar(message, replace: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (isNarrowLayout(context)) {
      final MiuixThemeData theme = MiuixTheme.of(context);
      return MiuixArrowPreference(
        title: l10n.settingsCheckUpdateTitle,
        startAction: buildSettingsIcon('update'),
        enabled: !_checking,
        onClick: _checking ? null : _check,
        endActions: [
          _checking
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                  ),
                )
              : Text(
                  l10n.settingsCurrentVersion(widget.currentVersion),
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceVariantActions,
                  ),
                ),
        ],
      );
    }
    return Material(
      color: context.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        onTap: _checking ? null : _check,
        child: Padding(
          padding: const EdgeInsets.all(5.0),
          child: ListTile(
            leading: buildWideSettingsIcon(context, 'update'),
            title: Text(l10n.settingsCheckUpdateTitle),
            subtitle: Text(l10n.settingsCheckUpdateSubtitle),
            trailing: _checking
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: context.palette.text,
                    ),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 14),
          ),
        ),
      ),
    );
  }
}

class _SettingOption {
  const _SettingOption({
    this.iconPath,
    this.icon,
    this.svg,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String? iconPath;
  final IconData? icon;

  /// 行首图标，assets/settings/ 下的 svg 文件名；为空时使用 [iconPath] 或 [icon]
  final String? svg;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}
