// Bus arriving: the rule that follows one bus of a running trip (busWatchStep) and what its
// notifications say.
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 22, 12, 10);

BusEta _eta(String service, int minutes) => BusEta(service: service, minutes: minutes, load: 'SEA');

BusTrack _track(int dueIn, {bool nearSent = false, bool arrivingSent = false, bool wasAtStop = false, int? ahead}) =>
    BusTrack(
      service: '197',
      due: _now.add(Duration(minutes: dueIn)),
      ahead: ahead == null ? null : _now.add(Duration(minutes: ahead)),
      nearSent: nearSent,
      arrivingSent: arrivingSent,
      wasAtStop: wasAtStop,
    );

BusWatchResult _step(BusTrack t, List<BusEta> etas, {DateTime? fetchedAt, bool fetched = true, double? metres}) =>
    busWatchStep(t, etas, _now, fetchedAt: fetched ? (fetchedAt ?? _now) : null, metresToStop: metres);

void main() {
  group('busWatchStep', () {
    test('near once', () {
      final r = _step(_track(5), [_eta('197', 2)]);
      expect(r.event, BusWatchEvent.near);
      expect(r.track.nearSent, isTrue);
      expect(r.eta?.minutes, 2);
      expect(_step(r.track, [_eta('197', 2)]).event, BusWatchEvent.none);
    });

    test('arriving once', () {
      final r = _step(_track(1), [_eta('197', 0)]);
      expect(r.event, BusWatchEvent.arriving);
      expect(r.track.nearSent, isTrue);
      expect(r.track.arrivingSent, isTrue);
      expect(_step(r.track, [_eta('197', 0)]).event, BusWatchEvent.none);
    });

    test('too soon ignored', () {
      final r = _step(_track(12), [_eta('197', 1), _eta('197', 12)]);
      expect(r.event, BusWatchEvent.none);
      expect(r.eta?.minutes, 12);
      expect(r.track.nearSent, isFalse);
      expect(r.track.arrivingSent, isFalse);
    });

    test('bunched', () {
      final r = _step(_track(3), [_eta('197', 1), _eta('197', 3)]);
      expect(r.event, BusWatchEvent.none);
      expect(r.eta?.minutes, 3);
    });

    test('follows drift', () {
      final r = _step(_track(6), [_eta('197', 8)]);
      expect(r.event, BusWatchEvent.none);
      expect(r.track.due, _now.add(const Duration(minutes: 8)));
    });

    test('gone: after two looks without it, not after one', () {
      // LTA drops a service for one reading now and then: that must not end the watch.
      final first = _step(_track(1, nearSent: true), const []);
      expect(first.event, BusWatchEvent.none);
      expect(first.eta, isNull);
      expect(_step(first.track, [_eta('197', 14)]).event, BusWatchEvent.gone);
      // It comes back at the next look: still watched, and the count starts again.
      final back = _step(first.track, [_eta('197', 1)]);
      expect(back.event, BusWatchEvent.none);
      expect(back.eta?.minutes, 1);
      expect(_step(back.track, [_eta('48', 3)]).event, BusWatchEvent.none);
    });

    test('gone at once when it is well past its time', () {
      expect(_step(_track(-2, nearSent: true), [_eta('197', 14)]).event, BusWatchEvent.gone);
    });

    test('slipping: the bus ahead stays the bus ahead when both times move', () {
      // Buses at 4 and 6 min, the 6 is watched; the next reading says 3 and 8.
      final learned = _step(_track(6), [_eta('197', 4), _eta('197', 6)]);
      expect(learned.eta?.minutes, 6);
      expect(learned.track.ahead, _now.add(const Duration(minutes: 4)));
      final r = _step(learned.track, [_eta('197', 3), _eta('197', 8)]);
      expect(r.eta?.minutes, 8, reason: 'not the earlier bus');
      expect(r.event, BusWatchEvent.none);
    });

    test('the bus ahead has left: the watched one is now the first', () {
      final r = _step(_track(5, ahead: 0), [_eta('197', 5), _eta('197', 14)]);
      expect(r.eta?.minutes, 5);
      expect(r.track.ahead, isNull);
    });

    test('after arriving, the next bus is not taken for it', () {
      final r = _step(_track(0, nearSent: true, arrivingSent: true), [_eta('197', 3)]);
      expect(r.eta, isNull);
      expect(r.event, BusWatchEvent.none);
      expect(_step(r.track, [_eta('197', 3)]).event, BusWatchEvent.gone);
    });

    test('re-anchors before near', () {
      final r = _step(_track(6), [_eta('197', 15)]);
      expect(r.event, BusWatchEvent.none);
      expect(r.track.due, _now.add(const Duration(minutes: 15)));
      final none = _step(_track(6), const []);
      expect(none.event, BusWatchEvent.none);
      expect(none.track.due, _now.add(const Duration(minutes: 6)));
    });

    test('stale', () {
      final old = _step(_track(1), [_eta('197', 0)], fetchedAt: _now.subtract(const Duration(seconds: 91)));
      expect(old.event, BusWatchEvent.stale);
      expect(old.track.arrivingSent, isFalse);
      expect(_step(_track(1), [_eta('197', 0)], fetched: false).event, BusWatchEvent.stale);
    });

    test('left the stop', () {
      expect(_step(_track(5), [_eta('197', 5)], metres: 40).track.wasAtStop, isTrue);
      expect(_step(_track(1, wasAtStop: true, nearSent: true), [_eta('197', 1)], metres: 320).event,
          BusWatchEvent.left);
      expect(_step(_track(5, wasAtStop: true), [_eta('197', 5)], metres: 320).event, BusWatchEvent.none);
      expect(_step(_track(1, nearSent: true), [_eta('197', 1)], metres: 320).event, BusWatchEvent.none);
    });
  });

  group('notes', () {
    const s = S();
    const stop = 'Marine Pde Stn Exit 6';
    List<String> texts(RichNote n) => [for (final p in n.pills) p.text];
    List<PillTone> tones(RichNote n) => [for (final p in n.pills) p.tone];

    test('near: the bus, the minutes and the load', () {
      final n = busNearNote(s, service: '197', stop: stop, to: 'Bugis Junction', minutes: 2, load: 'SEA');
      expect(n.id, 24);
      expect(n.title, '197 in 2 min');
      expect(n.body, 'At Marine Pde Stn Exit 6 · to Bugis Junction');
      expect(texts(n), ['197', '2 min', s.loadLabel('SEA')]);
      expect(tones(n), [PillTone.board, PillTone.amber, PillTone.mint]);
      expect(n.art, NoteArt.phone);
      expect(n.link, 'dailylah://today');
    });

    test('near: a load that is not known has no pill', () {
      final n = busNearNote(s, service: '197', stop: stop, to: 'Bugis Junction', minutes: 2);
      expect(texts(n), ['197', '2 min']);
    });

    test('near: a timetable estimate says so in the body', () {
      final n = busNearNote(s, service: '197', stop: stop, to: 'Bugis Junction', minutes: 2, monitored: false);
      expect(n.body, endsWith('Timetable estimate'));
    });

    test('arriving: where to get off when known', () {
      final n = busArrivingNote(s, service: '197', stop: stop, to: 'Bugis Junction', alight: 'Bugis Stn');
      expect(n.id, 24);
      expect(n.title, '197 is arriving');
      expect(texts(n), ['197', 'Arriving', 'Get off at Bugis Stn']);
      expect(tones(n), [PillTone.board, PillTone.amber, PillTone.sky]);
      expect(texts(busArrivingNote(s, service: '197', stop: stop, to: 'Bugis Junction')), ['197', 'Arriving']);
    });

    test('ongoing: the countdown on the location service notification', () {
      final n = busWatchNote(s, service: '197', stop: stop, minutes: 5, stopsAway: 4);
      expect(n.id, locationServiceNoteId);
      expect(n.title, 'Bus arriving');
      expect(n.body, 'At Marine Pde Stn Exit 6');
      expect(texts(n), ['197', '5 min', '4 stops away']);
      expect(tones(n), [PillTone.board, PillTone.teal, PillTone.sky]);
      expect(texts(busWatchNote(s, service: '197', stop: stop, minutes: 0))[1], 'Arriving');
      expect(texts(busWatchNote(s, service: '197', stop: stop, minutes: 5, stopsAway: 1))[2], '1 stop away');
      expect(texts(busWatchNote(s, service: '197', stop: stop, minutes: 5, stopsAway: 0))[2], 'Next stop');
    });

    test('ongoing: an old reading says when it is from', () {
      final n = busWatchNote(s, service: '197', stop: stop, minutes: 5, staleSince: DateTime(2026, 11, 22, 12, 7));
      expect(texts(n)[1], 'Updated 12:07');
      expect(tones(n)[1], PillTone.amber);
    });

    test('ongoing: how far the rider is from the stop when the bus has no position', () {
      expect(texts(busWatchNote(s, service: '197', stop: stop, minutes: 5, metresToStop: 40))[2], 'At the stop');
      expect(texts(busWatchNote(s, service: '197', stop: stop, minutes: 5, metresToStop: 340))[2], '350 m to the stop');
      expect(texts(busWatchNote(s, service: '197', stop: stop, minutes: 5)), ['197', '5 min']);
      expect(texts(busWatchNote(s, service: '197', stop: stop)), ['197', 'No arrival time']);
    });
  });

  group('what the phone remembers', () {
    const to = Place(kind: PlaceKind.other, name: 'Bugis Junction', addrLat: 1.2996, addrLng: 103.8554);
    final running = Habits(
      tripRoute: 'Home>Bugis Junction',
      tripStart: DateTime(2026, 11, 22, 12, 1),
      tripTo: to,
      tripStop: '92049',
      tripBus: '197',
    );

    test('the running trip keeps its destination, stop and bus', () {
      final back = Habits.fromJson(running.toJson());
      expect(back.tripTo?.name, 'Bugis Junction');
      expect(back.tripTo?.lat, 1.2996);
      expect(back.tripTo?.lng, 103.8554);
      expect(back.tripStop, '92049');
      expect(back.tripBus, '197');
    });

    test('they go when the trip ends', () {
      final ended = running.copyWith(clearTrip: true);
      expect(ended.tripTo, isNull);
      expect(ended.tripStop, isNull);
      expect(ended.tripBus, isNull);
      expect(ended.toJson().keys, isNot(contains('tt')));
    });

    test('the bus alone can be dropped', () {
      final none = running.copyWith(clearTripBus: true);
      expect(none.tripBus, isNull);
      expect(none.tripStop, '92049');
      expect(none.tripTo?.name, 'Bugis Junction');
    });

    test('a history saved before this loads', () {
      final old = Habits.fromJson(const {'trips': [], 'meals': [], 'tr': 'home>work', 'ts': '2026-11-20T08:00:00.000'});
      expect(old.tripRoute, 'home>work');
      expect(old.tripTo, isNull);
      expect(old.tripStop, isNull);
      expect(old.tripBus, isNull);
    });

    test('Bus arriving is an alert that is on until switched off', () {
      expect(const Favorites().busAlerts, isTrue);
      expect(Favorites.fromJson(const Favorites().copyWith(busAlerts: false).toJson()).busAlerts, isFalse);
      expect(Favorites.fromJson(const {'onboarded': true}).busAlerts, isTrue);
      expect(alertKinds, 10);
      final off = const Favorites().copyWith(busAlerts: false);
      expect(alertsOn(const Favorites()) - alertsOn(off), 1);
    });
  });

  group('tripLeave: what I\'m leaving remembers and watches', () {
    // Service 10 along Marine Parade Road (web/data): Siglap Sth CC to St. Patrick's Green is six
    // stops, to Goodwill Ct one stop (no quicker than walking).
    const siglap = Place(kind: PlaceKind.other, name: 'Siglap Sth CC', addrLat: 1.313904, addrLng: 103.931711);
    const goodwill = Place(kind: PlaceKind.other, name: 'Goodwill Ct', addrLat: 1.312958, addrLng: 103.927906);
    const stPatricks =
        Place(kind: PlaceKind.other, name: "St. Patrick's Green", addrLat: 1.309281, addrLng: 103.914345);
    Object? bundle(String name) => jsonDecode(File('../web/data/$name.json').readAsStringSync());
    final routes = BusRoutes.fromBundle(bundle('bus_routes') as Map<String, dynamic>);
    final all = [for (final r in bundle('bus_stops') as List) BusStop.fromBundle(r as Map<String, dynamic>)];
    List<BusStop> stopsFor(Place from, Place to) => tripStops(const [], all, routes, from, to).stops;
    final etas = [_eta('10', 6), _eta('10', 15), _eta('858A', 3)];

    test('the first stop and the bus to leave for', () {
      final stops = stopsFor(siglap, stPatricks);
      final l = tripLeave(from: siglap, to: stPatricks, stops: stops, routes: routes, all: all, etas: etas);
      expect(l?.stop.code, stops.first.code);
      expect(l?.service, '10');
      expect(l?.minutes, 6);
      expect(l?.alight, isNotNull);
    });

    test('no arrivals yet: the stop is remembered, no bus', () {
      final stops = stopsFor(siglap, stPatricks);
      final l = tripLeave(from: siglap, to: stPatricks, stops: stops, routes: routes, all: all, etas: null);
      expect(l?.stop.code, stops.first.code);
      expect(l?.service, isNull);
      expect(l?.minutes, isNull);
    });

    test('1.5 km or more from the stop: no bus to leave for', () {
      const far = Place(kind: PlaceKind.other, name: 'Far', addrLat: 1.333904, addrLng: 103.931711);
      final l = tripLeave(
          from: far, to: stPatricks, stops: stopsFor(siglap, stPatricks), routes: routes, all: all, etas: etas);
      expect(l?.stop, isNotNull);
      expect(l?.service, isNull);
    });

    test('a bus no quicker than walking is not watched', () {
      final stops = stopsFor(siglap, goodwill);
      final l = tripLeave(from: siglap, to: goodwill, stops: stops, routes: routes, all: all, etas: etas);
      expect(l?.stop.code, stops.first.code);
      expect(l?.service, isNull);
    });

    test('no bus stop card: nothing', () {
      expect(tripLeave(from: siglap, to: stPatricks, stops: const [], routes: routes, all: all, etas: etas), isNull);
    });
  });

  group('todayTripSlot: what sits under the weather on Today', () {
    const to = Place(kind: PlaceKind.other, name: 'Bugis Junction', addrLat: 1.2996, addrLng: 103.8554);
    final running = Habits(
        tripRoute: 'Home>Bugis Junction', tripStart: DateTime(2026, 11, 22, 12, 1), tripTo: to, tripStop: '92049');

    test('a running bus trip shows its board', () {
      expect(todayTripSlot(h: running, commuteShown: false, commuteRoute: null, plannedKey: 'adhoc'),
          TodayTripSlot.running);
    });

    test('not twice: the commute card already shows that trip', () {
      final commute = running.copyWith(tripRoute: 'home>work');
      expect(todayTripSlot(h: commute, commuteShown: true, commuteRoute: 'home>work', plannedKey: null),
          TodayTripSlot.none);
      expect(todayTripSlot(h: running, commuteShown: true, commuteRoute: 'home>work', plannedKey: null),
          TodayTripSlot.running, reason: 'another trip than the commute');
    });

    test('a trip with no stop or destination remembered has no board', () {
      final bare = Habits(tripRoute: 'Home>Here', tripStart: DateTime(2026, 11, 22, 12, 1));
      expect(todayTripSlot(h: bare, commuteShown: false, commuteRoute: null, plannedKey: null), TodayTripSlot.none);
    });

    test('a destination picked but not left for moves the planner card up', () {
      expect(todayTripSlot(h: Habits.empty, commuteShown: false, commuteRoute: null, plannedKey: 'adhoc'),
          TodayTripSlot.planned);
      expect(todayTripSlot(h: Habits.empty, commuteShown: false, commuteRoute: null, plannedKey: null),
          TodayTripSlot.none);
    });
  });
}
