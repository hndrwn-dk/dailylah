// About > Data sources: one row per source that opens its page, the estimate banner, the licences
// card and the attribution wording the data licences ask for. The layout under 200% text, dark mode
// and a small screen is also in screens_matrix_test.dart, text contrast in contrast_test.dart.
import 'package:dailylah/l10n.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/ui/about.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _s = S();

/// url_launcher's channel in tests (no plugin is registered): every URL the page asks to open.
const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

List<String> _fakeLauncher(WidgetTester tester) {
  final opened = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_launcher, (call) async {
    if (call.method == 'launch') opened.add((call.arguments as Map)['url'] as String);
    return true;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_launcher, null));
  return opened;
}

Future<void> _open(WidgetTester tester, [Condition c = const Condition('about')]) async {
  await applyCondition(tester, c);
  await tester.pumpWidget(pageUnder(c, const Favorites(), tuesdayMorning, const AboutDailyLahPage()));
  await settle(tester);
}

Finder get _list => find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;

Future<void> _show(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _list);
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await settle(tester);
}

const _sources = {
  'source-lta': ltaDataMallUrl,
  'source-datagov': dataGovUrl,
  'source-muslimsg': muslimSgUrl,
  'source-osm': osmCopyrightUrl,
  'source-onemap': oneMapUrl,
  'source-ura': uraUrl,
};

void main() {
  testWidgets('each data source is a row with what it powers, and a tap opens its page', (tester) async {
    final opened = _fakeLauncher(tester);
    await _open(tester);
    expect(dataSources.map((d) => d.url), _sources.values);
    for (final MapEntry(key: key, value: url) in _sources.entries) {
      final row = find.byKey(ValueKey(key));
      await _show(tester, row);
      final source = dataSources.firstWhere((d) => d.url == url);
      expect(find.descendant(of: row, matching: find.text(source.title(_s))), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(source.powers(_s))), findsOneWidget);
      expect(find.descendant(of: row, matching: find.byIcon(Icons.open_in_new)), findsOneWidget);
      await tester.tap(row);
      await tester.pump();
      expect(opened.last, url);
    }
    expect(opened, _sources.values);
  });

  testWidgets('the rows name the sources and say what each one is for', (tester) async {
    await _open(tester);
    await _show(tester, find.byKey(const ValueKey('source-onemap')));
    for (final title in ['LTA DataMall', 'data.gov.sg', 'Muslim.sg', 'OpenStreetMap via Geoapify', 'OneMap']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Bus arrivals, MRT, car parks and taxis'), findsOneWidget);
    // Bicycle parking is not in the app yet.
    expect(find.textContaining(RegExp('bicycle', caseSensitive: false)), findsNothing);
    // Every agency the attribution names is a chip on the data.gov.sg row.
    final chips = find.descendant(of: find.byKey(const ValueKey('source-datagov')), matching: find.byType(InfoChips));
    expect(tester.widget<InfoChips>(chips).labels,
        ['NEA', 'HDB', 'CEA', 'MUIS', 'NParks', 'NLB', 'SportSG', 'PA', 'MOE']);
    for (final agency in _s.dataAgencies) {
      expect(find.descendant(of: chips, matching: find.text(agency)), findsOneWidget);
    }
  });

  testWidgets('every source row tells a screen reader that it opens a website', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);
    for (final d in dataSources) {
      await _show(tester, find.byKey(ValueKey(d.key)));
      expect(
        find.bySemanticsLabel(RegExp('${RegExp.escape(d.title(_s))}[\\s\\S]*${RegExp.escape(_s.opensWebsite)}')),
        findsOneWidget,
        reason: d.key,
      );
    }
    await _show(tester, find.byKey(const ValueKey('licence-sodl')));
    expect(find.bySemanticsLabel(RegExp('Singapore Open Data Licence[\\s\\S]*${RegExp.escape(_s.opensWebsite)}')),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('the attribution the licences ask for stays on screen', (tester) async {
    await _open(tester);
    await _show(tester, find.byKey(const ValueKey('licence-oss')));
    // Singapore Open Data Licence: the source and the licence, in one sentence.
    expect(
      find.text('Contains information from LTA DataMall and from datasets by NEA, HDB, CEA, MUIS, NParks, NLB, '
          'SportSG, PA and MOE accessed through data.gov.sg, made available under the Singapore Open Data Licence.'),
      findsOneWidget,
    );
    expect(find.textContaining('© OpenStreetMap contributors (ODbL)'), findsOneWidget);
    expect(find.textContaining('Geoapify'), findsWidgets);
    expect(find.textContaining('DailyLah is not affiliated with MUIS'), findsOneWidget);
    expect(find.textContaining(_s.oneMapCredit), findsOneWidget);
    // The independence disclaimer is the footer.
    expect(find.text(_s.independent), findsOneWidget);
  });

  testWidgets('estimates are an info banner under the sources', (tester) async {
    await _open(tester);
    final banner = find.byKey(const ValueKey('estimates-note'));
    await _show(tester, banner);
    expect(tester.widget<AlertBanner>(banner).tone, AlertTone.info);
    expect(find.descendant(of: banner, matching: find.byIcon(Icons.info_outline)), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('Bus times, crowd levels, forecasts and prices are estimates.')),
        findsOneWidget);
    final onemap = tester.getRect(find.byKey(const ValueKey('source-onemap')));
    expect(tester.getRect(banner).top, greaterThan(onemap.bottom));
  });

  testWidgets('licences card: the open data licence opens its page, open-source licences the in-app page',
      (tester) async {
    final opened = _fakeLauncher(tester);
    await _open(tester);
    final sodl = find.byKey(const ValueKey('licence-sodl'));
    final oss = find.byKey(const ValueKey('licence-oss'));
    await _show(tester, oss);
    expect(find.descendant(of: sodl, matching: find.text('Singapore Open Data Licence')), findsOneWidget);
    expect(find.descendant(of: sodl, matching: find.byIcon(Icons.open_in_new)), findsOneWidget);
    expect(find.descendant(of: oss, matching: find.text(_s.openSourceLicences)), findsOneWidget);
    expect(find.descendant(of: oss, matching: find.byIcon(Icons.chevron_right)), findsOneWidget);
    // Both rows sit in one card.
    expect(find.ancestor(of: sodl, matching: find.byType(Panel)).evaluate().single,
        find.ancestor(of: oss, matching: find.byType(Panel)).evaluate().single);
    await tester.tap(sodl);
    await tester.pump();
    expect(opened, [sodlUrl]);
    expect(sodlUrl, 'https://data.gov.sg/open-data-licence');
    await tester.tap(oss);
    await settle(tester);
    expect(find.byType(LicensePage), findsOneWidget);
    expect(opened, [sodlUrl]);
  });

  for (final c in const [
    Condition('text 200% on 320dp', textScale: 2.0, size: Size(320, 640)),
    Condition('text 200% on 320dp, dark', textScale: 2.0, size: Size(320, 640), dark: true),
  ]) {
    testWidgets('holds at ${c.name}: nothing overflows and every row is at least 48 dp', (tester) async {
      await _open(tester, c);
      for (final key in [..._sources.keys, 'estimates-note', 'licence-sodl', 'licence-oss']) {
        final row = find.byKey(ValueKey(key));
        await _show(tester, row);
        expect(tester.takeException(), isNull, reason: key);
        final size = tester.getSize(row);
        expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension), reason: key);
        expect(size.width, lessThanOrEqualTo(320), reason: key);
      }
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
