import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AppLanguage {
  english('en'),
  arabic('ar');

  final String code;
  const AppLanguage(this.code);

  bool get isRtl => this == AppLanguage.arabic;
  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) {
    return AppLanguage.english;
  }
}

class AppLanguageController extends ChangeNotifier {
  static const storageKey = 'wellar_app_language';
  static const _storage = FlutterSecureStorage();

  AppLanguage _language;
  bool _loaded;

  AppLanguageController({
    AppLanguage initialLanguage = AppLanguage.english,
    bool loaded = false,
  })  : _language = initialLanguage,
        _loaded = loaded;

  AppLanguage get language => _language;
  bool get isLoaded => _loaded;

  static Future<AppLanguage> loadSavedLanguage() async {
    try {
      final saved = await _storage.read(key: storageKey);
      final normalized = AppLanguage.fromCode(saved);
      if (saved?.trim().toLowerCase() != AppLanguage.english.code) {
        await _storage.write(
          key: storageKey,
          value: AppLanguage.english.code,
        );
      }
      return normalized;
    } catch (_) {
      return AppLanguage.english;
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    _language = await loadSavedLanguage();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage _) async {
    _language = AppLanguage.english;
    try {
      await _storage.write(key: storageKey, value: AppLanguage.english.code);
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }
}
