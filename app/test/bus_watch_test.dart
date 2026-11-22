// Bus arriving: the rule that follows one bus of a running trip (busWatchStep) and what its
// notifications say.
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 22, 12, 10);

BusEta _eta(String service, int minutes) => BusEta(service: service, minutes: minutes, load: 'SEA');

BusTrack _track(int dueIn, {bool nearSent = false, bool arrivingSent = false, bool wasAtStop = false}) => BusTrack(
      service: '197',
      due: _now.add(Duration(minutes: dueIn)),
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

    test('gone', () {
      expect(_step(_track(1, nearSent: true), [_eta('197', 14)]).event, BusWatchEvent.gone);
      expect(_step(_track(1, nearSent: true), [_eta('48', 3)]).event, BusWatchEvent.gone);
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
}
