import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';

final apiProvider = Provider((ref) => DailyLahApi());

final trainAlertsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(apiProvider).trainAlerts(),
);

void main() => runApp(const ProviderScope(child: DailyLahApp()));

class DailyLahApp extends StatelessWidget {
  const DailyLahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DailyLah',
      theme: ThemeData(colorSchemeSeed: const Color(0xFFD9480F), useMaterial3: true),
      home: const MorningCardPage(),
    );
  }
}

/// Placeholder for the "kartu pagi" (morning card). See docs/PRD.md, Fase 1.
class MorningCardPage extends ConsumerWidget {
  const MorningCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(trainAlertsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('DailyLah')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('MRT'),
              subtitle: alerts.when(
                data: (d) => Text('Status: ${d['data']?['value']?['Status'] ?? '-'}'),
                loading: () => const Text('Loading…'),
                error: (e, _) => const Text('Belum ada data'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
