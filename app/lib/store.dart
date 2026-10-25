import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Favourites live only on the device (SharedPreferences). Readable from the
/// background isolate too.
class FavoritesStore {
  static const _key = 'favorites.v1';

  Future<Favorites> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const Favorites();
    try {
      return Favorites.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const Favorites();
    }
  }

  Future<void> save(Favorites fav) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(fav.toJson()));
  }
}

/// Habits the user logged (parked car, trip times, meals). Only on this phone.
class HabitsStore {
  static const _key = 'habits.v1';

  Future<Habits> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return Habits.empty;
    try {
      return Habits.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return Habits.empty;
    }
  }

  Future<void> save(Habits h) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(h.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Remembers which alerts were already sent so one event gives one notification.
class AlertLog {
  AlertLog(this._prefs);
  final SharedPreferences _prefs;

  static const _sentKey = 'alerts.sent';

  Future<bool> alreadySent(String id) async {
    await _prefs.reload();
    return (_prefs.getStringList(_sentKey) ?? const []).contains(id);
  }

  Future<void> markSent(String id) async {
    final list = [...(_prefs.getStringList(_sentKey) ?? const <String>[]), id];
    // Keep the log small.
    await _prefs.setStringList(_sentKey, list.length > 50 ? list.sublist(list.length - 50) : list);
  }

  /// Non-MRT notifications sent today (daily cap of 3).
  int sentToday(String day) =>
      (_prefs.getStringList(_sentKey) ?? const []).where((id) => id.startsWith('$day:')).length;
}


/// Last good answer of each live endpoint (forecast, train alerts, weather readings), so Today
/// opens with something right away while the server wakes up. Written by the app and by the
/// background check, so a morning open usually finds data from the last 15 minutes.
class LiveCache {
  static const _prefix = 'live.v1.';

  /// The cached body and when it was saved, or null. [reload] picks up writes made by the
  /// background isolate since this isolate last read the preferences.
  Future<(Map<String, dynamic>, DateTime)?> read(String name, {bool reload = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (reload) await prefs.reload();
      final raw = prefs.getString('$_prefix$name');
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (j['b'] as Map<String, dynamic>, DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()));
    } on Object {
      return null;
    }
  }

  Future<void> write(String name, Map<String, dynamic> body, [DateTime? at]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefix$name',
        jsonEncode({'t': (at ?? DateTime.now()).millisecondsSinceEpoch, 'b': body}),
      );
    } on Object {
      // A cache that cannot be written is only a slower start.
    }
  }
}
