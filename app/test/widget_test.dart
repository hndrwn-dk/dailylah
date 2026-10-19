import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dailylah/main.dart';

void main() {
  testWidgets('shows app title', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [trainAlertsProvider.overrideWith((ref) async => {})],
      child: const DailyLahApp(),
    ));
    expect(find.text('DailyLah'), findsOneWidget);
  });
}
