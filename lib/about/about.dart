import '../platform_support.dart';
import '../app_theme.dart';
import '../miuix_titled_page.dart';
import '../privacy_consent.dart';
import 'licenses.dart';
import 'privacy.dart';
import 'user.dart';
import 'package:watch_assistant/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于柚坛手表助手
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// ICP 备案号
  static const String icpNumber = '沪ICP备2024043668号-6A';

  /// 工信部 ICP 备案查询
  static const String icpQueryUrl = 'https://beian.miit.gov.cn/';

  static Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('无法打开URL: $url');
    }
  }

  static Future<void> _openIcpQuery() => _launchURL(icpQueryUrl);

  static void _showLicenses(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LicensesPage()),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // 访问官网（标题，链接）
    final List<(String, String)> visits = [
      (l10n.settingsWebsiteSubtitle, 'https://wearbox.uotan.cn/'),
      (l10n.settingsCommunityTitle, 'https://www.uotan.cn'),
      (
        l10n.viewOnGithub,
        'https://github.com/Uotan-Dev/UOTAN-WearBox',
      ),
    ];
    // 用户协议、隐私政策（标题，页面）
    final List<(String, Widget)> agreements = [
      (l10n.settingsUserAgreementTitle, const UserPage()),
      (l10n.settingsPrivacyTitle, const PrivacyPage()),
    ];
    if (isNarrowLayout(context)) {
      return MiuixTitledPage(
        title: l10n.settingsAboutTitle,
        showBackButton: true,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            MiuixSectionTitle(l10n.settingsSectionVisit, top: 0),
            MiuixGroupCard(
              children: [
                for (final (String title, String url) in visits)
                  MiuixArrowPreference(
                    title: title,
                    onClick: () => _launchURL(url),
                  ),
              ],
            ),
            MiuixSectionTitle(l10n.settingsSectionAgreements),
            MiuixGroupCard(
              children: [
                for (final (String title, Widget page) in agreements)
                  MiuixArrowPreference(
                    title: title,
                    onClick: () => _open(context, page),
                  ),
                MiuixArrowPreference(
                  title: l10n.aboutLicensesTitle,
                  onClick: () => _showLicenses(context),
                ),
                MiuixArrowPreference(
                  title: l10n.aboutWithdrawConsentTitle,
                  onClick: () => withdrawPrivacyConsent(context),
                ),
              ],
            ),
            MiuixSectionTitle(l10n.aboutSectionFiling),
            MiuixGroupCard(
              children: [
                // 点击打开工信部备案查询；备案号较长，放在副标题避免溢出
                MiuixArrowPreference(
                  title: l10n.aboutIcpLabel,
                  summary: icpNumber,
                  onClick: _openIcpQuery,
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
                    l10n.settingsAboutTitle, // 页面标题
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
          _buildSectionTitle(context, l10n.settingsSectionVisit),
          const SizedBox(height: 2),
          for (final (String title, String url) in visits) ...[
            Material(
              color: context.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8.0),
                onTap: () => _launchURL(url),
                child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: ListTile(
                    title: Text(title),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _buildSectionTitle(context, l10n.settingsSectionAgreements),
          const SizedBox(height: 2),
          for (final (String title, Widget page) in agreements) ...[
            Material(
              color: context.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8.0),
                onTap: () => _open(context, page),
                child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: ListTile(
                    title: Text(title),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          for (final (String title, VoidCallback onTap) in [
            (l10n.aboutLicensesTitle, () => _showLicenses(context)),
            (
              l10n.aboutWithdrawConsentTitle,
              () => withdrawPrivacyConsent(context),
            ),
          ]) ...[
            Material(
              color: context.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8.0),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: ListTile(
                    title: Text(title),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _buildSectionTitle(context, l10n.aboutSectionFiling),
          const SizedBox(height: 2),
          Material(
            color: context.palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            // 点击打开工信部备案查询
            child: InkWell(
              borderRadius: BorderRadius.circular(8.0),
              onTap: _openIcpQuery,
              child: Padding(
                padding: const EdgeInsets.all(5.0),
                child: ListTile(
                  title: Text(l10n.aboutIcpLabel),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        icpNumber,
                        style: TextStyle(color: context.palette.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_ios, size: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
