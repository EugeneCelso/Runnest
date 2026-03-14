import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/run_sessions.dart';

class StorageService {
  static const _key = 'run_sessions';

  Future<List<RunSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => RunSession.fromJson(jsonDecode(s)))
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  Future<void> saveSession(RunSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(session.toJson()));
    await prefs.setStringList(_key, raw);
  }

  /// Update an existing session in place (e.g. after adding a photo)
  Future<void> updateSession(RunSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final updated = raw.map((s) {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      if (decoded['id'] == session.id) {
        return jsonEncode(session.toJson());
      }
      return s;
    }).toList();
    await prefs.setStringList(_key, updated);
  }

  Future<void> deleteSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.removeWhere((s) {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      return decoded['id'] == id;
    });
    await prefs.setStringList(_key, raw);
  }
}