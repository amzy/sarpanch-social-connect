import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RetryQueueService {
  static const _key = 'pending_local_retries_v1';

  Future<void> enqueue(Map<String, Object?> task) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_key) ?? <String>[];
    items.add(jsonEncode({...task, 'queuedAt': DateTime.now().toIso8601String()}));
    await prefs.setStringList(_key, items);
  }

  Future<List<Map<String, dynamic>>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? <String>[])
        .map((item) => jsonDecode(item) as Map<String, dynamic>).toList();
  }

  Future<void> replace(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, items.map(jsonEncode).toList());
  }
}
