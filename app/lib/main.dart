import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background.dart';
import 'providers.dart';
import 'store.dart';
import 'ui/setup.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final favorites = await FavoritesStore().load();
  await initNotifications();
  if (favorites.onboarded) await registerBackgroundWork();
  runApp(ProviderScope(
    overrides: [initialFavoritesProvider.overrideWithValue(favorites)],
    child: const DailyLahApp(),
  ));
}

class DailyLahApp extends ConsumerWidget {
  const DailyLahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(favoritesProvider.select((f) => f.onboarded));
    return MaterialApp(
      title: 'DailyLah',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: onboarded ? const AppShell() : const SetupPage(firstRun: true),
    );
  }
}
