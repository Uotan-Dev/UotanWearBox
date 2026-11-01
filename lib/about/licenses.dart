import '../platform_support.dart';
import '../app_theme.dart';
import '../miuix_titled_page.dart';
import 'package:watch_assistant/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 按软件包分组的开源许可，读取一次后缓存
final Future<List<(String, List<LicenseEntry>)>> _licenses = () async {
  final Map<String, List<LicenseEntry>> byPackage = {};
  await for (final LicenseEntry entry in LicenseRegistry.licenses) {
    for (final String package in entry.packages) {
      byPackage.putIfAbsent(package, () => []).add(entry);
    }
  }
  final List<String> names = byPackage.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final String name in names) (name, byPackage[name]!)];
}();

/// 开源许可声明：软件包列表
class LicensesPage extends StatelessWidget {
  const LicensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    final bool narrow = isNarrowLayout(context);
    final Widget body = FutureBuilder<List<(String, List<LicenseEntry>)>>(
      future: _licenses,
      builder: (context, snapshot) {
        final List<(String, List<LicenseEntry>)>? packages = snapshot.data;
        if (packages == null) {
          return Center(
            child: narrow
                ? const MiuixInfiniteProgressIndicator()
                : CircularProgressIndicator(
                    strokeWidth: 2, color: context.palette.text),
          );
        }
        void open((String, List<LicenseEntry>) package) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  _LicenseDetailPage(package: package.$1, entries: package.$2),
            ),
          );
        }

        if (narrow) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            children: [
              MiuixGroupCard(
                children: [
                  for (final package in packages)
                    MiuixArrowPreference(
                      title: package.$1,
                      summary:
                          material.licensesPackageDetailText(package.$2.length),
                      onClick: () => open(package),
                    ),
                ],
              ),
            ],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          itemCount: packages.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final package = packages[index];
            return Material(
              color: context.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8.0),
                onTap: () => open(package),
                child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: ListTile(
                    title: Text(package.$1),
                    subtitle: Text(
                        material.licensesPackageDetailText(package.$2.length)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (narrow) {
      return MiuixTitledPage(
        title: l10n.aboutLicensesTitle,
        showBackButton: true,
        body: body,
      );
    }
    return _WideScaffold(title: l10n.aboutLicensesTitle, body: body);
  }
}

/// 单个软件包的许可全文
class _LicenseDetailPage extends StatelessWidget {
  const _LicenseDetailPage({required this.package, required this.entries});

  final String package;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (isNarrowLayout(context)) {
      final MiuixThemeData theme = MiuixTheme.of(context);
      return MiuixTitledPage(
        title: package,
        showBackButton: true,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            for (final (int i, LicenseEntry entry) in entries.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              MiuixCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _LicenseText(
                    entry: entry,
                    style: theme.textStyles.body2
                        .copyWith(color: theme.colors.onSurface),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return _WideScaffold(
      title: package,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        children: [
          for (final (int i, LicenseEntry entry) in entries.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            Material(
              color: context.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _LicenseText(
                  entry: entry,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: context.palette.text,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一条许可的各段落，按缩进排版，居中段落居中显示
class _LicenseText extends StatelessWidget {
  const _LicenseText({required this.entry, required this.style});

  final LicenseEntry entry;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final List<LicenseParagraph> paragraphs = entry.paragraphs.toList();
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (int i, LicenseParagraph paragraph) in paragraphs.indexed)
            Padding(
              padding: EdgeInsetsDirectional.only(
                top: i == 0 ? 0 : 8,
                start: paragraph.indent == LicenseParagraph.centeredIndent
                    ? 0
                    : 16.0 * paragraph.indent,
              ),
              child: Text(
                paragraph.text,
                style: style,
                textAlign: paragraph.indent == LicenseParagraph.centeredIndent
                    ? TextAlign.center
                    : TextAlign.start,
              ),
            ),
        ],
      ),
    );
  }
}

/// 宽屏页面：返回按钮 + 标题，与其他二级页面一致
class _WideScaffold extends StatelessWidget {
  const _WideScaffold({required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
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
                  Expanded(
                    child: Text(
                      title, // 页面标题
                      overflow: TextOverflow.ellipsis,
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
      body: body,
    );
  }
}
