/// Posts DailyLah's alert notifications with the sticker layout: pills and a small picture
/// under the title and text. Android only; everywhere else [DailylahNotify.show] is false
/// and the caller shows the plain notification.
library;

import 'package:flutter/services.dart';

class DailylahNotify {
  const DailylahNotify._();

  static const _channel = MethodChannel('dailylah/notify');

  /// Posts [note] (`RichNote.toMap()` in the app) on the app's alert channel, which is made
  /// with [channelName] and [channelDescription] when it does not exist yet.
  /// False on any error, when notifications are off, or when no plugin answers: never throws.
  static Future<bool> show(
    Map<String, Object?> note, {
    required String channelName,
    required String channelDescription,
  }) async {
    try {
      final ok = await _channel.invokeMethod<Object?>('show', {
        'note': note,
        'channelName': channelName,
        'channelDescription': channelDescription,
      });
      return ok == true;
    } on Object {
      return false;
    }
  }
}
