import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_model.dart';

class GithubService {
  // ⚡ 动态获取用户凭证与仓库信息
  static Future<Map<String, String>?> _getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('github_token');
    final repoUrl = prefs.getString('github_repo_url');

    if (token == null || token.isEmpty || repoUrl == null || repoUrl.isEmpty) {
      return null;
    }

    // ⚡ 强悍的正则：无论是 https://github.com/A/B 还是 git@github.com:A/B.git，都能精准提取
    try {
      final uri = Uri.parse(repoUrl.replaceAll('.git', ''));
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 2) {
        return {
          'token': token,
          'owner': pathSegments[pathSegments.length - 2],
          'repo': pathSegments[pathSegments.length - 1],
        };
      }
    } catch (e) {
      print("URL 解析失败: $e");
    }
    return null;
  }

  static Map<String, String> _getHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github.v3+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  // ==========================================
  // 📥 从云端拉取数据
  // ==========================================
  static Future<List<TaskModel>?> fetchTasksFromCloud() async {
    final creds = await _getCredentials();
    if (creds == null) return null; // 凭证缺失

    final baseUrl =
        'https://api.github.com/repos/${creds['owner']}/${creds['repo']}/contents/tasks.json';

    try {
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: _getHeaders(creds['token']!),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String contentStr = utf8.decode(
          base64Decode(data['content'].replaceAll('\n', '')),
        );
        final List<dynamic> jsonList = jsonDecode(contentStr);
        return jsonList.map((e) => TaskModel.fromJson(e)).toList();
      } else if (response.statusCode == 404) {
        // ⚡ 完美符合你的要求：如果根目录没有 task.json，返回空列表，表示云端是空的
        return [];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ==========================================
  // 📤 将数据推送到云端 (自动创建或覆盖)
  // ==========================================
  static Future<bool> syncToCloud(List<TaskModel> tasks) async {
    final creds = await _getCredentials();
    if (creds == null) return false;

    final baseUrl =
        'https://api.github.com/repos/${creds['owner']}/${creds['repo']}/contents/tasks.json';
    final headers = _getHeaders(creds['token']!);

    try {
      String? sha;
      // 侦察：看看云端有没有旧文件
      final getResp = await http.get(Uri.parse(baseUrl), headers: headers);
      if (getResp.statusCode == 200) {
        sha = jsonDecode(getResp.body)['sha'];
      }

      final String jsonString = jsonEncode(
        tasks.map((e) => e.toJson()).toList(),
      );
      final String base64Content = base64Encode(utf8.encode(jsonString));

      final Map<String, dynamic> body = {
        "message": "Auto Sync: ${DateTime.now().toIso8601String()}",
        "content": base64Content,
      };
      if (sha != null) body["sha"] = sha; // ⚡ 有 sha 则覆盖，无 sha 则在根目录自动新建！

      final putResp = await http.put(
        Uri.parse(baseUrl),
        headers: headers,
        body: jsonEncode(body),
      );

      return putResp.statusCode == 200 || putResp.statusCode == 201;
    } catch (e) {
      return false;
    }
  }
}
