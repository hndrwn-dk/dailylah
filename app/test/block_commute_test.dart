// Commute and all-in cost on "Prices, rent and score" (BlockPage) and the extra commute lines in
// the block comparison. Rules are tested in where_to_live_test.dart; the layout under 200% text,
// dark mode and a small screen in screens_matrix_test.dart. Expected figures come from the
// committed bundles, so the weekly data rebuild does not break these tests.
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/homes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _c = Condition('block commute');
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

final _wtl = WhereToLive.fromBundle(
    jsonDecode(File('../web/data/where-to-live.json').readAsStringSync()) as Map<String, dynamic>);
final _sixMonth =
    RentData.fromBundle(jsonDecode(File('../web/data/hdb_rent.json').readAsStringSync()) as Map<String, dynamic>);

Future<void> _open(WidgetTester tester, Favorites fav, Widget page) async {
  await applyCondition(tester, _c);
  await tester.pumpWidget(pageUnder(_c, fav, tuesdayMorning, page));
  await settle(tester);
}

/// The page's list (text fields have a Scrollable of their own).
Finder get _list => find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;

Future<void> _show(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 300, scrollable: _list);
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.4);
  await settle(tester);
}

void main() {
  const cbd = WtlChoice(area: 'cbd');
  final town = wtlTownFor(_wtl, 'TAMPINES')!;

  testWidgets('the block takes its town trip from the MRT station, with the estimated month', (tester) async {
    await _open(tester, householdFavorites, const BlockPage(block: _tampines));
    await _show(tester, find.byKey(const ValueKey('wtl-from')));
    expect(find.text('Tampines · from ${town.station} MRT'), findsOneWidget);
    expect(find.textContaining('Commute to CBD (Raffles Place)'), findsOneWidget);
    final cm = town.commute['cbd']!;
    expect(find.text('${cm.min} min'), findsWidgets);
    expect(find.text('Time to CBD (Raffles Place)'), findsOneWidget);
    final row = WtlRow(town: town, commute: cm, price: town.rent['4-ROOM'], group: WtlGroup.match);
    final m = wtlMonthly(cbd, row)!;
    expect(find.text('≈ ${sgd(m.total!)}'), findsOneWidget);
    expect(find.text('all-in a month, rent + fares'), findsOneWidget);
    expect(find.text('${m.hours} h'), findsOneWidget);
    expect(find.text(_s.wtlEstimateNote), findsWidgets);
  });

  testWidgets('one rent per town: the quarterly median with its quarter, not the six-month one', (tester) async {
    await _open(tester, householdFavorites, const BlockPage(block: _tampines));
    await _show(tester, find.text(_s.rentTitle));
    final q = town.rent['4-ROOM']!;
    expect(find.text(_s.wtlRentCaption('4-ROOM', q.quarter)), findsOneWidget);
    expect(find.text(_s.wtlTownRentNote('Tampines')), findsOneWidget);
    final six = _sixMonth.towns['TAMPINES']!['4-ROOM'];
    if (six != null && six != q.median) {
      // Anywhere on the page, the six-month 4-room figure never shows.
      await tester.scrollUntilVisible(find.byKey(const ValueKey('wtl-outside')), 600, scrollable: _list);
      expect(find.textContaining(sgd(six)), findsNothing);
    }
  });

  testWidgets('towns ranked by trip: fastest and best value, sort by price, budget and time limit', (tester) async {
    await _open(tester, householdFavorites, const BlockPage(block: _tampines));
    final fits = wtlRank(_wtl, cbd)[WtlGroup.match]!;
    await _show(tester, find.textContaining('Fits your choices'));
    expect(find.text(_s.wtlFits(fits.length)), findsOneWidget);
    expect(find.textContaining('Fastest: '), findsOneWidget);
    expect(find.textContaining('Best value: '), findsOneWidget);
    expect(find.text("This block's town"), findsOneWidget);

    // Sort by price: the cheapest town comes first.
    await _show(tester, find.byKey(const ValueKey('wtl-sort')));
    await tester.tap(find.text('Price'));
    await settle(tester);
    final byPrice = wtlSorted(fits, WtlSort.price);
    final first = find.byKey(ValueKey('wtl-row-${byPrice.first.town.id}'));
    final second = find.byKey(ValueKey('wtl-row-${byPrice[1].town.id}'));
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));

    // A budget narrows the towns that fit.
    await _show(tester, find.byKey(const ValueKey('wtl-budget')));
    await tester.enterText(find.byKey(const ValueKey('wtl-budget')), '3500');
    await settle(tester);
    final n = wtlRank(_wtl, cbd.copyWith(budget: () => 3500))[WtlGroup.match]!.length;
    expect(find.text(_s.wtlFits(n)), findsOneWidget);

    // So does a time limit.
    await tester.tap(find.byKey(const ValueKey('wtl-max')));
    await settle(tester);
    await tester.tap(find.text('Up to 45 min').last);
    await settle(tester);
    final n45 = wtlRank(_wtl, cbd.copyWith(budget: () => 3500, maxMinutes: () => 45))[WtlGroup.match]!.length;
    expect(find.text(_s.wtlFits(n45)), findsOneWidget);
  });

  testWidgets('switching to buy drops the rent budget and saves the choice', (tester) async {
    await _open(tester, householdFavorites, const BlockPage(block: _tampines));
    await _show(tester, find.byKey(const ValueKey('wtl-budget')));
    await tester.enterText(find.byKey(const ValueKey('wtl-budget')), '3500');
    await settle(tester);
    await _show(tester, find.byKey(const ValueKey('wtl-mode')));
    await tester.tap(find.text('Buy resale'));
    await settle(tester);
    expect(containerOf(tester).read(favoritesProvider).wtlMode, 'buy');
    await _show(tester, find.byKey(const ValueKey('wtl-budget')));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('wtl-budget'))).controller!.text, isEmpty);
    expect(
        find.text(_s.wtlFits(wtlRank(_wtl, cbd.copyWith(mode: WtlMode.buy))[WtlGroup.match]!.length)), findsOneWidget);
  });

  testWidgets('compare: commute lines per block, the office area town in this area, no best in all-in', (tester) async {
    final fav = householdFavorites.copyWith(
      wtlArea: 'woodlands',
      compareBlocks: ['1|MARSILING DR', '156|TAMPINES ST 12', '101|ANG MO KIO AVE 3'],
    );
    await _open(tester, fav, const ComparePage());
    final woodlands = wtlTownFor(_wtl, 'WOODLANDS')!;
    await _show(tester, find.text('On the road a month'));
    expect(find.text('Time to Woodlands'), findsOneWidget);
    expect(find.text('In this area'), findsWidgets);
    expect(find.text('≈ ${sgd(woodlands.rent['4-ROOM']!.median)} rent, no fare estimate'), findsOneWidget);
    // The same cells the table shows: their best flags.
    final lines = wtlBlockLines(_wtl, const WtlChoice(area: 'woodlands'), ['WOODLANDS', 'TAMPINES', 'ANG MO KIO']);
    final time = lines.firstWhere((l) => l.key == WtlLineKey.time);
    expect(time.cells.first.best, isFalse);
    expect(lines.firstWhere((l) => l.key == WtlLineKey.allIn).cells.any((c) => c.best), isFalse);
    expect(lines.firstWhere((l) => l.key == WtlLineKey.hours).cells.any((c) => c.best), isFalse);
    expect(find.text('Best'), findsWidgets);
  });

  testWidgets('Home: the block card quotes the same quarterly rent', (tester) async {
    await applyCondition(tester, _c);
    await tester.pumpWidget(appUnder(_c, householdFavorites, tuesdayMorning));
    await settle(tester);
    containerOf(tester).read(shellTabProvider.notifier).state = 2;
    await settle(tester);
    expect(find.textContaining(RegExp(r'Rent around S\$[\d,]+ a month for an? .* in this town \(Q[1-4] \d{4} median\)')),
        findsOneWidget);
  });
}
