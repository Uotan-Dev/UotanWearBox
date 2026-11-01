import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'about/privacy.dart';
import 'about/user.dart';
import 'app_prefs.dart';
import 'l10n/l10n.dart';
import 'miuix_dialog.dart';
import 'platform_support.dart';

/// 首次启动时请求同意用户协议和隐私政策；已同意则直接返回。
/// 不同意时退出应用。
Future<void> ensurePrivacyConsent(BuildContext context) async {
  if (await hasPrivacyConsent() || !context.mounted) {
    return;
  }
  final bool? agreed = await showMiuixDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final l10n = context.l10n;
      return PopScope(
        canPop: false,
        child: MiuixAlertDialog(
          title: Text(l10n.consentDialogTitle),
          content: const _ConsentContent(),
          actions: [
            MiuixDialogButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.consentDisagree),
            ),
            MiuixDialogButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.consentAgree),
            ),
          ],
        ),
      );
    },
  );
  if (agreed == true) {
    await setPrivacyConsent(true);
  } else {
    await closeApp();
  }
}

/// 撤回同意：二次确认后清除同意记录并退出，下次启动重新询问
Future<void> withdrawPrivacyConsent(BuildContext context) async {
  final bool? confirmed = await showMiuixDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return MiuixAlertDialog(
        title: Text(l10n.aboutWithdrawConsentTitle),
        content: Text(l10n.withdrawConsentMessage),
        actions: [
          MiuixDialogButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.dialogCancel),
          ),
          MiuixDialogButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.withdrawConsentConfirm),
          ),
        ],
      );
    },
  );
  if (confirmed == true) {
    await setPrivacyConsent(false);
    await closeApp();
  }
}

/// 同意弹窗正文：说明文字，以及可点击查看的《用户协议》《隐私政策》
class _ConsentContent extends StatefulWidget {
  const _ConsentContent();

  @override
  State<_ConsentContent> createState() => _ConsentContentState();
}

class _ConsentContentState extends State<_ConsentContent> {
  late final TapGestureRecognizer _userTap = TapGestureRecognizer()
    ..onTap = () => _open(const UserPage());
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => _open(const PrivacyPage());

  void _open(Widget page) {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (context) => page));
  }

  @override
  void dispose() {
    _userTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final TextStyle link =
        TextStyle(color: MiuixTheme.of(context).colors.primary);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: l10n.consentDialogMessage),
          const TextSpan(text: '\n'),
          TextSpan(
            text: '《${l10n.settingsUserAgreementTitle}》',
            style: link,
            recognizer: _userTap,
          ),
          TextSpan(
            text: '《${l10n.settingsPrivacyTitle}》',
            style: link,
            recognizer: _privacyTap,
          ),
        ],
      ),
    );
  }
}
