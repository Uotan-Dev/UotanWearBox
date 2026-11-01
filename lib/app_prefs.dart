import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _appCenterPrefsKey = 'app_center_enabled';
const String _privacyConsentPrefsKey = 'privacy_consent';

/// 是否启用应用中心（导航栏中的"应用"页面），在设置 → 功能中切换
final ValueNotifier<bool> appCenterEnabled = ValueNotifier<bool>(true);

/// 启动时读取已保存的设置
Future<void> loadAppPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  appCenterEnabled.value = prefs.getBool(_appCenterPrefsKey) ?? true;
}

void setAppCenterEnabled(bool enabled) {
  appCenterEnabled.value = enabled;
  SharedPreferences.getInstance()
      .then((prefs) => prefs.setBool(_appCenterPrefsKey, enabled));
}

/// 用户是否已同意用户协议和隐私政策
Future<bool> hasPrivacyConsent() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_privacyConsentPrefsKey) ?? false;
}

Future<void> setPrivacyConsent(bool agreed) async {
  final prefs = await SharedPreferences.getInstance();
  if (agreed) {
    await prefs.setBool(_privacyConsentPrefsKey, true);
  } else {
    await prefs.remove(_privacyConsentPrefsKey);
  }
}
