import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background.dart';
import 'providers.dart';
import 'store.dart';
import 'ui/home.dart';
import 'ui/setup.dart';

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
      theme: ThemeData(colorSchemeSeed: const Color(0xFFD9480F), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFFD9480F),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: onboarded ? const HomePage() : const SetupPage(firstRun: true),
    );
  }
}
