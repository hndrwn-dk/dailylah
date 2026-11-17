import 'package:dailylah_notify/dailylah_notify.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dailylah/notify');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const note = <String, Object?>{'id': 2, 'title': 'Rain before you leave.', 'body': 'Bring an umbrella.'};

  Future<bool> show() =>
      DailylahNotify.show(note, channelName: 'DailyLah alerts', channelDescription: 'Rain, MRT and more');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('true when Android posted it, with the note and the channel names', () async {
    MethodCall? got;
    messenger.setMockMethodCallHandler(channel, (call) async {
      got = call;
      return true;
    });
    expect(await show(), isTrue);
    expect(got!.method, 'show');
    final args = (got!.arguments as Map).cast<String, Object?>();
    expect(args['note'], note);
    expect(args['channelName'], 'DailyLah alerts');
    expect(args['channelDescription'], 'Rain, MRT and more');
  });

  test('false when Android says it did not post', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await show(), isFalse);
  });

  test('false when the plugin throws', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'boom'));
    expect(await show(), isFalse);
  });

  test('false when no plugin answers (tests, another platform)', () async {
    expect(await show(), isFalse);
  });

  test('showOngoing sends the note with the service notification it replaces', () async {
    MethodCall? got;
    messenger.setMockMethodCallHandler(channel, (call) async {
      got = call;
      return true;
    });
    expect(await DailylahNotify.showOngoing(note, serviceNotificationId: 75415, serviceChannelId: 'geo'), isTrue);
    expect(got!.method, 'showOngoing');
    final args = (got!.arguments as Map).cast<String, Object?>();
    expect(args['note'], note);
    expect(args['serviceNotificationId'], 75415);
    expect(args['serviceChannelId'], 'geo');
  });

  test('showOngoing is false when no plugin answers or it throws', () async {
    expect(await DailylahNotify.showOngoing(note, serviceNotificationId: 1, serviceChannelId: 'geo'), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'boom'));
    expect(await DailylahNotify.showOngoing(note, serviceNotificationId: 1, serviceChannelId: 'geo'), isFalse);
  });

  test('false when the answer is not a bool', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => 'yes');
    expect(await show(), isFalse);
  });
}
