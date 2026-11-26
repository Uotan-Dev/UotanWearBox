import '../platform_support.dart';
import '../app_theme.dart';
import '../miuix_titled_page.dart';
import 'package:watch_assistant/l10n/l10n.dart';
import 'package:flutter/material.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 窄屏：左右与 miuix 标题对齐（26），顶部间距统一由 MiuixTitledPage 提供
    final l10n = context.l10n;
    // 各段落及其样式，顺序即显示顺序
    final List<(_PolicyStyle, String)> paragraphs = [
      (_PolicyStyle.title, l10n.privacyParagraph2),
      (_PolicyStyle.date, l10n.privacyParagraph3),
      (_PolicyStyle.body, l10n.privacyParagraph4),
      (_PolicyStyle.heading, l10n.privacyParagraph5),
      (_PolicyStyle.body, l10n.privacyParagraph6),
      (_PolicyStyle.heading, l10n.privacyParagraph7),
      (_PolicyStyle.body, l10n.privacyParagraph8),
      (_PolicyStyle.body, l10n.privacyParagraph9),
      (_PolicyStyle.heading, l10n.privacyParagraph10),
      (_PolicyStyle.body, l10n.privacyParagraph11),
      (_PolicyStyle.body, l10n.privacyParagraph12),
      (_PolicyStyle.heading, l10n.privacyParagraph13),
      (_PolicyStyle.body, l10n.privacyParagraph14),
      (_PolicyStyle.heading, l10n.privacyParagraph15),
      (_PolicyStyle.body, l10n.privacyParagraph16),
      (_PolicyStyle.heading, l10n.privacyParagraph17),
      (_PolicyStyle.body, l10n.privacyParagraph18),
      (_PolicyStyle.heading, l10n.privacyParagraph19),
      (_PolicyStyle.body, l10n.privacyParagraph20),
      (_PolicyStyle.heading, l10n.privacyParagraph21),
      (_PolicyStyle.body, l10n.privacyParagraph22),
      (_PolicyStyle.body, l10n.privacyParagraph23),
    ];
    // 窄屏：左右与 miuix 标题对齐（26），顶部间距统一由 MiuixTitledPage 提供
    final body = SingleChildScrollView(
      padding: isNarrowLayout(context)
          ? const EdgeInsets.fromLTRB(26, 0, 26, 30)
          : const EdgeInsets.fromLTRB(30, 20, 30, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (style, text) in paragraphs)
            Padding(
              padding: EdgeInsets.only(
                top: switch (style) {
                  _PolicyStyle.title => 0,
                  _PolicyStyle.date => 2,
                  _PolicyStyle.heading => 16,
                  _PolicyStyle.body => 6,
                },
              ),
              child: Text(
                text,
                style: switch (style) {
                  _PolicyStyle.title =>
                    const TextStyle(fontSize: 24, fontFamily: 'MiSansMed'),
                  _PolicyStyle.heading =>
                    const TextStyle(fontSize: 20, fontFamily: 'MiSansMed'),
                  _PolicyStyle.date || _PolicyStyle.body =>
                    const TextStyle(fontSize: 16),
                },
              ),
            ),
          const SizedBox(height: 30),
        ],
      ),
    );
    if (isNarrowLayout(context)) {
      return MiuixTitledPage(
        title: context.l10n.privacyParagraph1,
        showBackButton: true,
        body: body,
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // 左右对齐
                children: [
                  Row(
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
                        context.l10n.privacyParagraph1, // 页面标题
                        style: TextStyle(
                          color: context.palette.text,
                          fontSize: 26,
                          fontFamily: 'MiSansLight', // 使用自定义字体
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: body,
    );
  }
}

/// 隐私政策段落样式
enum _PolicyStyle { title, date, heading, body }
