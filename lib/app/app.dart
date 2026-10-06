import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import 'constants.dart';
import 'router.dart';

class FishLogApp extends ConsumerWidget {
  const FishLogApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [for (final code in kMaterialSupportedLanguages) Locale(code)],
      // Keep intl (dates, numbers) on the same locale the UI resolved to, so "Jun 15" and
      // "4,5 kg" follow the device rather than defaulting to en_US.
      localeListResolutionCallback: (locales, supported) {
        final resolved = basicLocaleListResolution(locales, supported);
        Intl.defaultLocale = resolved.toString();
        return resolved;
      },
    );
  }
}
