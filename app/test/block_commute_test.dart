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
import 'package:dailylah/ui/block_commute.dart';
import 'package:dailylah/ui/homes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(find.text('The office area where your work is.'), findsOneWidget);
    final cm = town.commute['cbd']!;
    expect(find.text('${cm.min} min'), findsWidgets);
    expect(find.text('Time to CBD (Raffles Place)'), findsOneWidget);
    final row = WtlRow(town: town, commute: cm, price: town.rent['4-ROOM'], group: WtlGroup.match);
    final m = wtlMonthly(cbd, row)!;
    expect(find.text('≈ ${sgd(m.total!)}'), findsOneWidget);
    expect(find.text(_s.wtlAllInLabel), findsOneWidget);
    expect(_s.wtlAllInLabel, contains('estimate'));
    // All-in is rent plus fares, both shown under it.
    expect(find.text(_s.wtlAllInParts(sgd(row.price!.median), sgd(m.fares!))), findsOneWidget);
    expect(find.text(_s.wtlTransfersValue(cm.transfers!)), findsOneWidget);
    // The rent is in the list above, not repeated on the card.
    expect(find.textContaining('median rent S\$'), findsNothing);
    expect(find.text('${m.hours} h'), findsOneWidget);
    expect(find.text(_s.wtlHoursLabel), findsOneWidget);
  });

  testWidgets('one rent per town: the quarterly median with its quarter, not the six-month one', (tester) async {
    await _open(tester, householdFavorites, const BlockPage(block: _tampines));
    await _show(tester, find.text(_s.rentTitle));
    final q = town.rent['4-ROOM']!;
    expect(find.text('${sgd(q.median)} /mo', findRichText: true), findsOneWidget);
    expect(find.text(_s.wtlQuarter(q.quarter)), findsWidgets);
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

  testWidgets('the commute card has its own accessibility nodes, not one node for the whole page', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, householdFavorites, const BlockPage(block: _tampines));
    await _show(tester, find.byKey(const ValueKey('wtl-from')));
    // Screen readers and Maestro find the line on its own, a node no taller than the line.
    final node = tester.getSemantics(find.byKey(const ValueKey('wtl-from')));
    expect(node.label, 'Tampines · from ${town.station} MRT');
    expect(node.rect.height, lessThan(120));
    await _show(tester, find.textContaining('Fits your choices'));
    expect(tester.getSemantics(find.textContaining('Fits your choices')).label, startsWith('Fits your choices'));
    semantics.dispose();
  });

  testWidgets('an office area picked by hand is not asked to be saved again', (tester) async {
    await _open(tester, householdFavorites.copyWith(wtlArea: 'one-north'), const BlockPage(block: _tampines));
    await _show(tester, find.byKey(const ValueKey('wtl-from')));
    expect(find.text(_s.wtlPickedArea), findsOneWidget);
    expect(find.textContaining('Save your work place'), findsNothing);
    // The towns' heading shows once, above the filters.
    await _show(tester, find.textContaining('Fits your choices'));
    expect(find.text(_s.wtlTownsTitle('one-north')), findsOneWidget);
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
    // The context as chips above the table.
    final chips = find.byKey(const ValueKey('compare-context'));
    expect(find.descendant(of: chips, matching: find.text('To Woodlands')), findsOneWidget);
    expect(find.descendant(of: chips, matching: find.text('4-room')), findsOneWidget);
    expect(find.descendant(of: chips, matching: find.text('Rent')), findsOneWidget);
    await _show(tester, find.text('On the road a month'));
    expect(find.text('Time to Woodlands'), findsOneWidget);
    expect(find.text('In this area'), findsWidgets);
    expect(find.text('≈ ${sgd(woodlands.rent['4-ROOM']!.median)}'), findsOneWidget);
    expect(find.text('rent only'), findsOneWidget);
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

  testWidgets('one disclaimer line; About this data opens the sheet with the hdb.gov.sg link', (tester) async {
    await _open(tester, householdFavorites, const BlockPage(block: _tampines));
    final about = find.byKey(const ValueKey('about-data'));
    await _show(tester, about);
    expect(find.text(_s.dataFooter(dataDay(_wtl.generatedAt))), findsOneWidget);
    expect(find.text(_s.homesDisclaimer), findsNothing);
    await tester.tap(about);
    await settle(tester);
    expect(find.text(_s.aboutDataMethod), findsOneWidget);
    expect(find.textContaining('22 working days'), findsOneWidget);
    expect(find.byKey(const ValueKey('check-eligibility')), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Notify and Compare buttons: same size, labels on one line (text ${scale * 100}%)', (tester) async {
      final c = Condition('buttons', textScale: scale, size: scale > 1 ? const Size(360, 780) : const Size(412, 915));
      await applyCondition(tester, c);
      await tester.pumpWidget(pageUnder(c, householdFavorites, tuesdayMorning, const BlockPage(block: _tampines)));
      await settle(tester);
      final watch = find.widgetWithText(FilledButton, 'Notifying you');
      final compare = find.byKey(const ValueKey('block-compare'));
      expect(tester.getSize(watch), tester.getSize(compare));
      for (final label in [_s.watching, _s.openCompare(2)]) {
        final text = find.text(label);
        // One line: the label is no taller than one line of its style.
        final style = tester.widget<Text>(text).style ?? DefaultTextStyle.of(tester.element(text)).style;
        expect(tester.getSize(text).height, lessThanOrEqualTo((style.fontSize ?? 14) * scale * (style.height ?? 1.5) + 2));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compare: section titles over the resale and rent lines, short labels', (tester) async {
    await _open(tester, householdFavorites.copyWith(compareBlocks: ['1|MARSILING DR', '156|TAMPINES ST 12']), const ComparePage());
    expect(find.text('Resale median'), findsOneWidget);
    await _show(tester, find.text('Rent in town'));
    expect(find.text('Hawkers ≤ 1 km'), findsOneWidget);
    expect(find.text('Bus stops ≤ 400 m'), findsOneWidget);
  });

  testWidgets('the block street wraps between words at 200% text, never inside one', (tester) async {
    const c = Condition('header', textScale: 2, size: Size(320, 700));
    await applyCondition(tester, c);
    const long = HdbBlock(
      block: '101',
      street: 'ANG MO KIO AVE 3',
      town: 'ANG MO KIO',
      yearCompleted: 1977,
      floors: 12,
      lat: 1.37024,
      lng: 103.83948,
      postal: '560101',
    );
    for (final b in [_tampines, long]) {
      await tester.pumpWidget(pageUnder(c, householdFavorites, tuesdayMorning, BlockPage(block: b)));
      await settle(tester);
      final title = find.text(b.street);
      final para = tester.renderObject<RenderParagraph>(title);
      // Lay the same text out again at the paragraph's width to read where its lines break.
      final tp = TextPainter(text: para.text, textDirection: TextDirection.ltr, textScaler: para.textScaler)
        ..layout(maxWidth: para.size.width);
      addTearDown(tp.dispose);
      final text = b.street;
      // Every line break falls on a space.
      final lines = tp.getLineBoundary(const TextPosition(offset: 0));
      expect(lines.start, 0);
      var offset = 0;
      while (offset < text.length) {
        final line = tp.getLineBoundary(TextPosition(offset: offset));
        if (line.end < text.length) {
          expect(text[line.end - 1] == ' ' || text[line.end] == ' ', isTrue, reason: '${b.street} breaks at ${line.end}');
        }
        offset = line.end > offset ? line.end : offset + 1;
      }
      expect(tester.takeException(), isNull);
    }
  });
}
