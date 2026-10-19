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
