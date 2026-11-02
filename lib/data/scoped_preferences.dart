import 'package:shared_preferences/shared_preferences.dart';

/// Separate device identity, selected vehicles and retries between backends.
class ScopedPreferences {
  ScopedPreferences(this.store, this.namespace);
  final SharedPreferences store;
  final String namespace;
  String? getString(String key) => store.getString('$namespace$key');
  List<String>? getStringList(String key) =>
      store.getStringList('$namespace$key');
  Future<bool> setString(String key, String value) =>
      store.setString('$namespace$key', value);
  Future<bool> setStringList(String key, List<String> value) =>
      store.setStringList('$namespace$key', value);
  Future<bool> remove(String key) => store.remove('$namespace$key');
}
