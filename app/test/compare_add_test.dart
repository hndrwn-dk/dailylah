// Compare any blocks (add from search, watched and recently viewed blocks, 1 → 2 → 3), the block
// page about prices, rent and commute only (no Daily life; Compare keeps those lines), and one
// spelling for flat types ("3-room").
import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/homes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _c = Condition('compare add');
const _s = S();

const _tampines = HdbBlock(
  block: '156',
  street: 'TAMPINES ST 12',
  town: 'TAMPINES',
  yearCompleted: 1983,
  floors: 11,
  lat: 1.35159,
  lng: 103.94503,
  postal: '521156',
);

/// The page under the app's navigator, so pushes and the snackbar work as in the app.
Future<void> _open(WidgetTester tester, Favorites fav, Widget page) async {
  await applyCondition(tester, _c);
  await tester.pumpWidget(pageUnder(_c, fav, tuesdayMorning, page));
  await settle(tester);
}

Finder _list(WidgetTester tester) =>
    find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;

void main() {
  test('flat types read the same whatever the source writes', () {
    for (final raw in ['3 ROOM', '3-ROOM', '3 room']) {
      expect(_s.wtlFlatName(raw), '3-room');
    }
    expect(_s.wtlFlatName('EXECUTIVE'), 'Executive');
    expect(_s.wtlFlatName('MULTI-GENERATION'), 'Multi-generation');
    expect(_s.medianFor('3 ROOM'), '3-room median');
    expect(_s.rentMedian('3-ROOM', r'S$2,500'), r'Rent around S$2,500 a month for a 3-room in this town');
    expect(_s.rentMedian('EXECUTIVE', r'S$3,500'), r'Rent around S$3,500 a month for an Executive in this town');
  });

  test('recently viewed blocks: newest first, no repeats, at most 6; candidates skip compared ones', () {
    var recent = <String>[];
    for (final k in ['a', 'b', 'c', 'a', 'd', 'e', 'f', 'g']) {
      recent = withRecentBlock(recent, k);
    }
    expect(recent, ['g', 'f', 'e', 'd', 'a', 'c']);
    expect(
      compareCandidates(watched: ['w', 'a'], recent: ['a', 'x', 'c'], compared: ['c']),
      ['w', 'a', 'x'],
    );
  });

  testWidgets('Compare 1 → 2 → 3: Add block from watched blocks and from search, then no more room',
      (tester) async {
    // One block compared; 156 Tampines St 12 is watched.
    await _open(tester, householdFavorites.copyWith(compareBlocks: ['508|TAMPINES CTRL 1']), const ComparePage());
    final box = containerOf(tester);
    expect(find.text(_s.addAnotherBlock), findsOneWidget);
    final add = find.byKey(const ValueKey('compare-add'));
    expect(add, findsOneWidget);

    // 2: the watched block is offered before anything is typed.
    await tester.tap(add);
    await settle(tester);
    expect(find.text(_s.addBlockTitle), findsOneWidget);
    expect(find.text(_s.watched), findsOneWidget);
    expect(find.text('TAMPINES CTRL 1'), findsNothing); // already compared
    await tester.tap(find.text('TAMPINES ST 12'));
    await settle(tester);
    expect(find.text(_s.addBlockTitle), findsNothing); // back on Compare
    expect(box.read(favoritesProvider).compareBlocks, ['508|TAMPINES CTRL 1', '156|TAMPINES ST 12']);
    expect(find.text(_s.addAnotherBlock), findsNothing);
    expect(find.byKey(const ValueKey('compare-add')), findsOneWidget);

    // 3: found by search.
    await tester.tap(find.byKey(const ValueKey('compare-add')));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '101 Ang Mo Kio Ave 3');
    await settle(tester);
    await tester.tap(find.text('ANG MO KIO AVE 3').first);
    await settle(tester);
    expect(box.read(favoritesProvider).compareBlocks.length, 3);
    expect(box.read(favoritesProvider).compareBlocks.last, '101|ANG MO KIO AVE 3');
    // Full: the add column is gone.
    expect(find.byKey(const ValueKey('compare-add')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compare with no block offers Add block', (tester) async {
    await _open(tester, householdFavorites.copyWith(compareBlocks: const []), const ComparePage());
    expect(find.text(_s.noCompareYet), findsOneWidget);
    expect(find.byKey(const ValueKey('compare-add')), findsOneWidget);
  });

  testWidgets('Compare on the block page: snackbar with Add, which picks the next block and shows the comparison',
      (tester) async {
    await _open(tester, householdFavorites.copyWith(compareBlocks: const []), const BlockPage(block: _tampines));
    final box = containerOf(tester);
    // The page counts as recently viewed.
    expect(box.read(favoritesProvider).recentBlocks.first, _tampines.key);
    await tester.tap(find.byKey(const ValueKey('block-compare')));
    await settle(tester);
    expect(find.text(_s.compareAdded(1)), findsOneWidget);
    expect(_s.compareAdded(1), 'Added. Add another block to compare');
    await tester.tap(find.widgetWithText(SnackBarAction, _s.add));
    await settle(tester);
    expect(find.text(_s.addBlockTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), '101 Ang Mo Kio Ave 3');
    await settle(tester);
    await tester.tap(find.text('ANG MO KIO AVE 3').first);
    await settle(tester);
    expect(box.read(favoritesProvider).compareBlocks, [_tampines.key, '101|ANG MO KIO AVE 3']);
    expect(find.byType(ComparePage), findsOneWidget);
  });

  testWidgets('the block page is about prices, rent and commute; Compare keeps the daily life lines', (tester) async {
    await _open(tester, householdFavorites, const BlockPage(block: _tampines));
    // Scroll to the end: no Daily life section anywhere on the page.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('about-data')), 400, scrollable: _list(tester));
    await settle(tester);
    expect(find.text('Daily life around this block'), findsNothing);
    expect(find.text('Hawker centres within 1 km'), findsNothing);
    expect(find.text('Nearest MRT'), findsNothing);
    expect(find.text(_s.wtlCommuteTitle), findsOneWidget);

    await _open(tester, householdFavorites, const ComparePage());
    await tester.scrollUntilVisible(find.text('Hawkers ≤ 1 km'), 300, scrollable: _list(tester));
    expect(find.text('Nearest MRT'), findsOneWidget);
    expect(find.text('Hawkers ≤ 1 km'), findsOneWidget);
    expect(find.text('Bus stops ≤ 400 m'), findsOneWidget);
  });

  testWidgets('Home: the block button reads Prices, rent and commute; flat types read 3-room', (tester) async {
    await applyCondition(tester, _c);
    await tester.pumpWidget(ProviderScope(
      retry: noRetry,
      overrides: overridesFor(_c, householdFavorites, tuesdayMorning),
      child: const DailyLahApp(),
    ));
    await settle(tester);
    containerOf(tester).read(shellTabProvider.notifier).state = 2;
    await settle(tester);
    expect(_s.blockDetails, 'Prices, rent and commute');
    expect(find.text('Prices, rent and commute'), findsOneWidget);
    expect(find.text('Prices, rent and score'), findsNothing);
    // "3-room median", never "median 3 room".
    expect(find.textContaining(RegExp(r'\d room|median \d')), findsNothing);
    expect(find.textContaining(RegExp(r'^\d-room median$|^Executive median$')), findsWidgets);

    await tester.ensureVisible(find.text('Prices, rent and commute'));
    await tester.pump();
    await tester.tap(find.text('Prices, rent and commute'));
    await settle(tester);
    expect(find.byType(BlockPage), findsOneWidget);
    // The resale chips too.
    expect(find.textContaining(RegExp(r'^\d room$')), findsNothing);
    expect(find.textContaining(RegExp(r'^\d-room$')), findsWidgets);
  });
}
