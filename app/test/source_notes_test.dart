// Data sources are credited once, in About > Data sources. The tabs carry no source footnotes;
// they keep the short disclaimers a person needs where the decision is made, and the credits a
// provider asks for next to its data (the OneMap credit on the map, Geoapify / OpenStreetMap).
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/about.dart';
import 'package:dailylah/ui/home.dart';
import 'package:dailylah/ui/homes.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _s = S();
const _normal = Condition('normal');
const _large = [
  Condition('text 200% on 320dp', textScale: 2.0, size: Size(320, 640)),
  Condition('text 200% on 320dp, dark', textScale: 2.0, size: Size(320, 640), dark: true),
];

/// The halal disclaimer, word for word (owner decision: never shortened).
const _halal =
    'Not affiliated with MUIS. Always verify halal status directly: look for the MUIS halal certificate at the premises.';

/// What the removed footnotes said: a source or agency credit, or "computed on your phone".
final _sourceNote = RegExp(
  r'data\.gov\.sg|DataMall|OneMap|Singapore Land Authority|Muslim\.sg|Computed on your phone|MUIS via|from LTA|'
  r'SCDF, MOH|PSI and PM2\.5: NEA|Council for Estate Agencies|URA \(|NParks and NEA|OpenStreetMap, ',
);

const _nearbySections = ['bus', 'eat', 'green', 'park', 'taxi', 'toilet', 'prayer', 'help'];

Future<ProviderContainer> _tab(WidgetTester tester, Condition c, int tab,
    {String? nearby, String? home}) async {
  await applyCondition(tester, c);
  await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
  await settle(tester);
  final box = containerOf(tester);
  box.read(shellTabProvider.notifier).state = tab;
  if (nearby != null) box.read(nearbySectionProvider.notifier).state = nearby;
  if (home != null) box.read(homeSectionProvider.notifier).state = home;
  await settle(tester);
  return box;
}

/// Scrolls the tab to its end and checks at every step that no text on it matches [what].
Future<void> _noneWhileScrolling(WidgetTester tester, Pattern what, {required String reason}) async {
  final lists = _vertical;
  for (var i = 0; i < 12; i++) {
    final hits = find.textContaining(what).evaluate().map((e) => (e.widget as Text).data);
    expect(hits, isEmpty, reason: reason);
    if (lists.evaluate().isEmpty) return;
    await tester.drag(lists.first, const Offset(0, -500), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// The tab's or page's own list (not the row of section chips, which scrolls sideways).
Finder get _vertical => find
    .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
    .hitTestable();

/// Scrolls until [f] is built and on screen. Some sections are a list inside the tab's list, so
/// every vertical list on screen is tried, innermost first.
Future<void> _showText(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    for (var i = _vertical.evaluate().length - 1; i >= 0 && f.evaluate().isEmpty; i--) {
      try {
        await tester.scrollUntilVisible(f, 300, scrollable: _vertical.at(i), maxScrolls: 40);
      } on StateError {
        // Not in this list: try the one around it.
      }
    }
  }
  expect(f, findsWidgets);
  await tester.ensureVisible(f.first);
  await tester.pump();
}

void main() {
  test('the halal disclaimer is unchanged, and the notes left on screens name no source', () {
    expect(_s.halalDisclaimer, _halal);
    expect(_s.halalSheetSubtitle('1 Tampines Walk'), '1 Tampines Walk\n$_halal');
    expect(_s.homesDisclaimer, 'Past sales, not listings. Not financial advice.');
    for (final note in [
      _s.homesDisclaimer,
      _s.privateHomesNote,
      _s.toiletNote,
      _s.emergencyNote,
      _s.evLiveNote,
      _s.taxiLive,
      _s.directionsNote,
      _s.pullToRefresh,
      _s.dataFooter('12 Nov 2026'),
    ]) {
      expect(_sourceNote.hasMatch(note), isFalse, reason: note);
    }
    // The warnings themselves are still said.
    expect(_s.emergencyNote, contains('call 995 first'));
    expect(_s.emergencyNote, contains('may be out of date'));
    expect(_s.toiletNote, contains('may be closed or inside paid areas'));
    expect(_s.evLiveNote, contains('Not affiliated with the operators'));
  });

  group('no source footnotes on the tabs', () {
    testWidgets('Today', (tester) async {
      await _tab(tester, _normal, 0);
      await _noneWhileScrolling(tester, _sourceNote, reason: 'Today');
      expect(find.text(_s.pullToRefresh), findsOneWidget);
    });

    for (final section in _nearbySections) {
      testWidgets('Nearby: $section', (tester) async {
        await _tab(tester, _normal, 1, nearby: section);
        await _noneWhileScrolling(tester, _sourceNote, reason: 'Nearby $section');
      });
    }

    for (final section in HomePage.sections) {
      testWidgets('Home: $section', (tester) async {
        await _tab(tester, _normal, 2, home: section);
        await _noneWhileScrolling(tester, _sourceNote, reason: 'Home $section');
      });
    }

    testWidgets('the agent check page', (tester) async {
      await applyCondition(tester, _normal);
      await tester.pumpWidget(pageUnder(_normal, householdFavorites, tuesdayMorning, const AgentCheckPage()));
      await settle(tester);
      expect(find.textContaining(_sourceNote), findsNothing);
    });
  });

  group('halal disclaimer, word for word, wherever halal places are listed', () {
    for (final c in [_normal, ..._large]) {
      testWidgets('Nearby card and the sheet of a place on it (${c.name})', (tester) async {
        await _tab(tester, c, 1, nearby: 'eat');
        await _showText(tester, find.text(_halal));
        expect(find.text(_halal), findsOneWidget);
        final tile = find.widgetWithIcon(ListTile, Icons.restaurant_outlined).first;
        await tester.ensureVisible(tile);
        await tester.pump();
        await tester.tap(tile);
        await settle(tester);
        expect(find.textContaining('\n$_halal'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('See all list and the sheet of a place on it (${c.name})', (tester) async {
        await _tab(tester, c, 1, nearby: 'eat');
        final seeAll =
            find.descendant(of: find.widgetWithText(SectionTitle, 'Halal food nearby'), matching: find.text('See all'));
        await _showText(tester, seeAll);
        await tester.ensureVisible(seeAll);
        await tester.pump();
        await tester.tap(seeAll);
        await settle(tester);
        expect(find.widgetWithText(AlertBanner, _halal), findsOneWidget);
        expect(find.textContaining(_sourceNote), findsNothing);
        await _showText(tester, find.widgetWithIcon(ListTile, Icons.restaurant_outlined));
        final tile = find.widgetWithIcon(ListTile, Icons.restaurant_outlined).first;
        await tester.ensureVisible(tile);
        await tester.pump();
        await tester.tap(tile);
        await settle(tester);
        expect(find.textContaining('\n$_halal'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Home > Food and the sheet of a place on it (${c.name})', (tester) async {
        final box = await _tab(tester, c, 2, home: 'food');
        final home = householdFavorites.places[PlaceKind.home]!;
        final all = (await tester.runAsync(() => box.read(halalProvider.future)))!;
        final first = halalNear(all, home.lat, home.lng, limit: 15).first.$1;
        await _showText(tester, find.text(_halal));
        expect(find.text(_halal), findsOneWidget);
        final row = find.widgetWithText(ListTile, first.name).first;
        await tester.ensureVisible(row);
        await tester.pump();
        await tester.tap(row);
        await settle(tester);
        expect(find.text('${first.address}\n$_halal'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('short disclaimers stay where the decision is made', () {
    for (final c in [_normal, ..._large]) {
      testWidgets('Home: past sales, not listings (${c.name})', (tester) async {
        await _tab(tester, c, 2, home: 'home');
        await _showText(tester, find.text('Past sales, not listings. Not financial advice.'));
        expect(find.text('Past sales, not listings. Not financial advice.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('emergency on Home: call 995 first (${c.name})', (tester) async {
        await _tab(tester, c, 2, home: 'emergency');
        await _showText(tester, find.text(_s.emergencyNote));
        expect(find.text(_s.emergencyNote), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('emergency on Nearby > See all: call 995 first (${c.name})', (tester) async {
        await _tab(tester, c, 1, nearby: 'help');
        final seeAll = find.descendant(of: find.widgetWithText(SectionTitle, _s.helpNearby), matching: find.text('See all'));
        await _showText(tester, seeAll);
        await tester.tap(seeAll);
        await settle(tester);
        await _showText(tester, find.text(_s.emergencyNote));
        expect(find.text(_s.emergencyNote), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('toilets: the estimate note and the Geoapify / OpenStreetMap credit (${c.name})', (tester) async {
        await _tab(tester, c, 1, nearby: 'toilet');
        await _showText(tester, find.text(_s.placesAttribution));
        expect(find.text('Times are estimates. Some toilets may be closed or inside paid areas.'), findsOneWidget);
        expect(find.text('Powered by Geoapify · © OpenStreetMap contributors'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('block search keeps the short line', (tester) async {
      await applyCondition(tester, _normal);
      await tester.pumpWidget(pageUnder(_normal, householdFavorites, tuesdayMorning, const BlockSearchPage()));
      await settle(tester);
      expect(find.text(_s.homesDisclaimer), findsOneWidget);
    });
  });

  group('About covers everything that left the screens', () {
    Future<void> open(WidgetTester tester, Condition c) async {
      await applyCondition(tester, c);
      await tester.pumpWidget(pageUnder(c, const Favorites(), tuesdayMorning, const AboutDailyLahPage()));
      await settle(tester);
    }

    /// Every text of the page, read while scrolling to its end.
    Future<String> allText(WidgetTester tester) async {
      final seen = <String>{};
      final list = _vertical.first;
      for (var i = 0; i < 14; i++) {
        seen.addAll(find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? ''));
        await tester.drag(list, const Offset(0, -400), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
      }
      return seen.join('\n');
    }

    testWidgets('every source and agency of the inventory is named', (tester) async {
      await open(tester, _normal);
      final text = await allText(tester);
      for (final name in [
        'LTA DataMall', 'data.gov.sg', 'OneMap (SLA)', 'Singapore Land Authority', 'URA', 'Muslim.sg', 'Geoapify',
        'OpenStreetMap', 'Eventfinda', 'NEA', 'HDB', 'CEA', 'MUIS', 'NParks', 'NLB', 'SportSG', 'PA', 'MOE', 'SCDF',
        'MOH', 'MOM', 'ECDA', 'LTA', //
      ]) {
        expect(text, contains(name), reason: name);
      }
      // What each removed line credited is said by a row.
      for (final powers in [
        'Bus arrivals', 'taxis', 'EV chargers', 'Weather and haze', 'HDB blocks, prices and rents', 'prayer times',
        'estate agents', 'AEDs', 'Halal places, refreshed daily', 'public toilets (with NParks and NEA hawker centres)',
        'works and services near home', 'Private home sale prices', 'Weekend events', //
      ]) {
        expect(text, contains(powers), reason: powers);
      }
    });

    testWidgets('the licence statement, the OpenStreetMap credit and every disclaimer are there', (tester) async {
      await open(tester, _normal);
      final text = await allText(tester);
      expect(
        text,
        contains('Contains information from LTA DataMall and from datasets by NEA, HDB, CEA, MUIS, NParks, NLB, '
            'SportSG, PA, MOE, SCDF, MOH, MOM and ECDA accessed through data.gov.sg, made available under the '
            'Singapore Open Data Licence.'),
      );
      expect(text, contains('© OpenStreetMap contributors'));
      expect(text, contains(_s.oneMapCredit));
      expect(text, contains(_s.estimatesNote));
      expect(text, contains('Halal food: $_halal'));
      expect(text, contains('past transactions from public data, not current listings. Not financial advice. '
          'Check eligibility on hdb.gov.sg.'));
      expect(text, contains('caveats lodged with URA and exclude bulk sales'));
      expect(text, contains('rough estimates'));
      expect(text, contains('Toilets may be closed, moved or inside paid areas.'));
      expect(text, contains('call 995 first'));
      expect(text, contains('health advice follows NEA guidelines; see haze.gov.sg'));
      expect(text, contains('not affiliated with the charging operators'));
      expect(text, contains('MOE uses its own home-to-school measurement'));
      expect(text, contains('check details and tickets'));
      expect(text, contains('Distances, scores and what is near you are computed on your phone.'));
      for (final note in _s.aboutNotes) {
        expect(text, contains(note), reason: note);
      }
    });

    for (final c in _large) {
      testWidgets('the Good to know card holds at ${c.name}', (tester) async {
        await open(tester, c);
        final card = find.byKey(const ValueKey('good-to-know'));
        await _showText(tester, card);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(card).width, lessThanOrEqualTo(320));
      });
    }
  });

  group('About this data (block page)', () {
    for (final c in [_normal, ..._large]) {
      testWidgets('has no source list of its own; See data sources opens About (${c.name})', (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(pageUnder(c, householdFavorites, tuesdayMorning, const ComparePage()));
        await settle(tester);
        final about = find.byKey(const ValueKey('about-data'));
        await _showText(tester, about);
        await tester.ensureVisible(about);
        await tester.pump();
        await tester.tap(about);
        await settle(tester);
        expect(find.text('Sources'), findsNothing);
        expect(find.text(_s.aboutDataMethod), findsOneWidget);
        final link = find.byKey(const ValueKey('see-data-sources'));
        await tester.scrollUntilVisible(link, 200, scrollable: find.byType(Scrollable).last);
        expect(find.byKey(const ValueKey('check-eligibility')), findsOneWidget);
        await tester.ensureVisible(link);
        await tester.pump();
        await tester.tap(link);
        await settle(tester);
        expect(find.byType(AboutDailyLahPage), findsOneWidget);
        expect(find.text(_s.aboutDataMethod), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
