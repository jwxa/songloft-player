import 'package:flutter/material.dart';

String resolveEffectiveTheme(ThemeMode mode, Brightness platformBrightness) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return platformBrightness == Brightness.dark ? 'dark' : 'light';
  }
}
