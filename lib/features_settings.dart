import 'platform_support.dart';
import 'app_prefs.dart';
import 'app_theme.dart';
import 'miuix_titled_page.dart';
import 'package:watch_assistant/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 功能：可选功能的开关
class FeaturesSettingsPage extends StatelessWidget {
  const FeaturesSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (isNarrowLayout(context)) {
      return MiuixTitledPage(
        title: l10n.settingsFeaturesTitle,
        showBackButton: true,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            MiuixGroupCard(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: appCenterEnabled,
                  builder: (context, enabled, _) => MiuixSwitchPreference(
                    title: l10n.featuresAppCenterTitle,
                    summary: l10n.featuresAppCenterSubtitle,
                    value: enabled,
                    onChanged: setAppCenterEnabled,
                  ),
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
                    l10n.settingsFeaturesTitle, // 页面标题
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
          ValueListenableBuilder<bool>(
            valueListenable: appCenterEnabled,
            builder: (context, enabled, _) => Material(
              color: context.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5.0),
                child: ListTile(
                  title: Text(l10n.featuresAppCenterTitle),
                  subtitle: Text(l10n.featuresAppCenterSubtitle),
                  // 配色与应用列表页"显示系统应用"开关一致
                  trailing: Switch(
                    value: enabled,
                    activeColor: Colors.white,
                    activeTrackColor: const Color.fromARGB(255, 30, 93, 229),
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.grey[300],
                    onChanged: setAppCenterEnabled,
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
