// Runs after the emulator workflow installed the previous APK, used it, and then installed
// the new build over it with `adb install -r` (docs/QA.md section 5). It must find the data
// the old version left behind and open on Today, not on Setup.
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/store.dart';
import 'package:dailylah/ui/setup.dart';
import 'package:dailylah/ui/today.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('data saved by the previous version is still there', (tester) async {
    final fav = await FavoritesStore().load();
    expect(fav.onboarded, isTrue, reason: 'the upgrade lost favorites.v1 or could not read it');
    expect(fav.places[PlaceKind.home], isNotNull);
    expect(fav.lines, contains('EWL'));
    expect(fav.mrtAlerts, isFalse, reason: 'a toggle changed in the old version must stay changed');

    await tester.pumpWidget(ProviderScope(
      overrides: [initialFavoritesProvider.overrideWithValue(fav)],
      child: const DailyLahApp(),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(SetupPage), findsNothing);
    expect(find.byType(TodayPage), findsOneWidget);
  });
}
