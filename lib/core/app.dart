import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../features/auth/phone_auth_screen.dart';
import '../features/posts/home_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

class SarpanchSocialConnectApp extends ConsumerWidget {
  const SarpanchSocialConnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final appearance = ref.watch(appearanceControllerProvider);

    return MaterialApp(
      title: 'Sarpanch Social Connect',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(appearance.themeId, Brightness.light),
      darkTheme: buildAppTheme(appearance.themeId, Brightness.dark),
      themeMode: appearance.themeMode,
      // The product interface is intentionally English-only. The selected
      // content language is stored separately on the Panchayat/user profile.
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: auth.when(
        data: (user) => user == null ? const PhoneAuthScreen() : const HomeScreen(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => const PhoneAuthScreen(),
      ),
    );
  }
}
