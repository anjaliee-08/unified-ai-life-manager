import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class ApiService {
  final String baseUrl = Constants.baseUrl;

  // ── Auth ──────────────────────────────────────────

  Future<Map<String, dynamic>> registerUser(
      String email, String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'name': name}),
    );
    return jsonDecode(response.body);
  }

  // ── Tasks ─────────────────────────────────────────

  Future<List<dynamic>> getUserTasks(int userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/tasks/user/$userId'),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> createTask(
      int userId, String description, String priority) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/tasks/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'description': description,
        'priority': priority,
        'source': 'manual',
      }),
    );
    return jsonDecode(response.body);
  }

  Future<void> updateTaskStatus(int taskId, String status) async {
    await http.patch(
      Uri.parse('$baseUrl/api/tasks/$taskId/status?status=$status'),
    );
  }

  Future<void> deleteTask(int taskId) async {
    await http.delete(
      Uri.parse('$baseUrl/api/tasks/$taskId'),
    );
  }

  // ── AI ────────────────────────────────────────────

  Future<Map<String, dynamic>> getAiStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/ai/status'),
      ).timeout(const Duration(seconds: 5));
      return jsonDecode(response.body);
    } catch (e) {
      return {'status': 'offline', 'model': 'unknown'};
    }
  }

  Future<Map<String, dynamic>> extractTasks(String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/ai/extract'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    return jsonDecode(response.body);
  }

  Future<String> chat(String message) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/ai/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message}),
    );
    final data = jsonDecode(response.body);
    return data['response'] ?? 'No response';
  }
  Future<String> chatWithContext(String message, int userId) async {
  // Fetch user's actual tasks first
  List<dynamic> tasks = [];
  try {
    tasks = await getUserTasks(userId);
  } catch (_) {}

  // Build context string from real tasks
  String taskContext = '';
  if (tasks.isNotEmpty) {
    final pending = tasks.where((t) => t['status'] == 'pending').toList();
    if (pending.isNotEmpty) {
      taskContext = '\n\nUser\'s current pending tasks:\n';
      for (final t in pending) {
        taskContext += '- ${t['description']} (${t['priority']} priority)\n';
      }
    }
  }

  final response = await http.post(
    Uri.parse('$baseUrl/api/ai/chat'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'message': message + taskContext}),
  );
  final data = jsonDecode(response.body);
  return data['response'] ?? 'No response';
}
// ── Agent (intelligent AI assistant) ─────────────────────────────

Future<Map<String, dynamic>> agentChat({
  required int userId,
  required String message,
  String? confirmAction,
  int? confirmTaskId,
}) async {
  final body = <String, dynamic>{
    'user_id': userId,
    'message': message,
  };
  if (confirmAction != null) body['confirm_action'] = confirmAction;
  if (confirmTaskId != null) body['confirm_task_id'] = confirmTaskId;

  final response = await http.post(
    Uri.parse('$baseUrl/api/agent/chat'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  ).timeout(const Duration(seconds: 90));

  return jsonDecode(response.body);
}

Future<List<dynamic>> getTodayTasks(int userId) async {
  final r = await http.get(
      Uri.parse('$baseUrl/api/agent/tasks/today/$userId'));
  return jsonDecode(r.body);
}

Future<List<dynamic>> getOverdueTasks(int userId) async {
  final r = await http.get(
      Uri.parse('$baseUrl/api/agent/tasks/overdue/$userId'));
  return jsonDecode(r.body);
}

Future<List<dynamic>> getHighPriorityTasks(int userId) async {
  final r = await http.get(
      Uri.parse('$baseUrl/api/agent/tasks/high-priority/$userId'));
  return jsonDecode(r.body);
}
}