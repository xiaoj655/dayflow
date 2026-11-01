import 'package:shared_preferences/shared_preferences.dart';

abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PreferenceStore implements LocalStore {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read(String key) => _preferences.getString(key);
  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

class MemoryStore implements LocalStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
