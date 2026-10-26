import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background.dart';
import 'models.dart';
import 'providers.dart';
import 'store.dart';
import 'ui/keyboard.dart';
import 'ui/setup.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var favorites = const Favorites();
  try {
    favorites = await FavoritesStore().load();
  } on Object catch (e) {
    debugPrint('favourites not loaded: $e');
  }
  // Show the app first; notifications and background work must never block start-up.
  runApp(ProviderScope(
    overrides: [initialFavoritesProvider.overrideWithValue(favorites)],
    child: const DailyLahApp(),
  ));
  try {
    await initNotifications();
  } on Object catch (e) {
    debugPrint('notifications not ready: $e');
  }
  if (favorites.onboarded) {
    try {
      await registerBackgroundWork();
    } on Object catch (e) {
      debugPrint('background work not registered: $e');
    }
  }
}

class DailyLahApp extends ConsumerWidget {
  const DailyLahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(favoritesProvider.select((f) => f.onboarded));
    return MaterialApp(
      title: 'DailyLah',
      navigatorObservers: [KeyboardNavigatorObserver()],
      builder: (context, child) => KeyboardRepaint(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: onboarded ? const AppShell() : const SetupPage(firstRun: true),
    );
  }
}
