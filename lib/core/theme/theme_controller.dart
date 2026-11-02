import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class AppAppearance {
  const AppAppearance({
    this.themeId = AppThemeId.governmentBlue,
    this.themeMode = ThemeMode.system,
  });

  final AppThemeId themeId;
  final ThemeMode themeMode;

  AppAppearance copyWith({AppThemeId? themeId, ThemeMode? themeMode}) {
    return AppAppearance(
      themeId: themeId ?? this.themeId,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class AppearanceController extends StateNotifier<AppAppearance> {
  AppearanceController() : super(const AppAppearance()) {
    _restore();
  }

  static const _themeKey = 'appearance.theme';
  static const _modeKey = 'appearance.mode';

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final themeName = preferences.getString(_themeKey);
    final modeName = preferences.getString(_modeKey);

    final theme = AppThemeId.values.firstWhere(
      (value) => value.name == themeName,
      orElse: () => AppThemeId.governmentBlue,
    );
    final mode = ThemeMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => ThemeMode.system,
    );

    if (mounted) {
      state = AppAppearance(themeId: theme, themeMode: mode);
    }
  }

  Future<void> selectTheme(AppThemeId themeId) async {
    state = state.copyWith(themeId: themeId);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeKey, themeId.name);
  }

  Future<void> selectMode(ThemeMode themeMode) async {
    state = state.copyWith(themeMode: themeMode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_modeKey, themeMode.name);
  }
}

final appearanceControllerProvider =
    StateNotifierProvider<AppearanceController, AppAppearance>(
      (ref) => AppearanceController(),
    );
