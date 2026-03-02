import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_model.dart';

class GithubService {
  // ⚡ 动态获取用户凭证与仓库信息 (加入终极净化器)
  static Future<Map<String, String>?> _getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    // 🛡️ 防御：去除复制粘贴带来的首尾隐形空格
    final token = prefs.getString('github_token')?.trim();
    String? repoUrl = prefs.getString('github_repo_url')?.trim();

    if (token == null || token.isEmpty || repoUrl == null || repoUrl.isEmpty) {
      print("⚠️ 凭证缺失: Token 或 URL 为空");
      return null;
    }

    // 🛡️ 防御：去掉 URL 末尾可能手滑多加的斜杠 (例如 tide/ -> tide)
    if (repoUrl.endsWith('/')) {
      repoUrl = repoUrl.substring(0, repoUrl.length - 1);
    }

    try {
      final uri = Uri.parse(repoUrl.replaceAll('.git', ''));
      final pathSegments = uri.pathSegments;
      // 🛡️ 防御：过滤掉所有空层级，防止解析错位
      final validSegments = pathSegments.where((s) => s.isNotEmpty).toList();

      if (validSegments.length >= 2) {
        return {
          'token': token,
          'owner': validSegments[validSegments.length - 2],
          'repo': validSegments[validSegments.length - 1],
        };
      } else {
        print("❌ URL 解析异常：未能提取到 owner 和 repo");
      }
    } catch (e) {
      print("❌ URL 解析致命错误: $e");
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
    if (creds == null) return null;

    final baseUrl =
        'https://api.github.com/repos/${creds['owner']}/${creds['repo']}/contents/tasks.json';

    print("📡 正在尝试连接云端: $baseUrl");

    try {
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: _getHeaders(creds['token']!),
      );

      if (response.statusCode == 200) {
        print("✅ 云端数据拉取成功 (200)");
        final data = jsonDecode(response.body);
        final String contentStr = utf8.decode(
          base64Decode(data['content'].replaceAll('\n', '')),
        );
        final List<dynamic> jsonList = jsonDecode(contentStr);
        return jsonList.map((e) => TaskModel.fromJson(e)).toList();
      } else if (response.statusCode == 404) {
        print("⚠️ 云端文件不存在 (404) - 视为空仓库");
        return [];
      } else {
        // 🚨 抓捕内鬼：打印真实的服务器拒绝理由！
        print("❌ 云端拉取失败！状态码: ${response.statusCode}");
        print("❌ GitHub 返回信息: ${response.body}");
        return null;
      }
    } catch (e) {
      // 🚨 抓捕网络异常 (如没走代理导致的超时)
      print("❌ 发生底层网络异常 (可能是没走代理或断网): $e");
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
      if (sha != null) body["sha"] = sha;

      final putResp = await http.put(
        Uri.parse(baseUrl),
        headers: headers,
        body: jsonEncode(body),
      );

      if (putResp.statusCode == 200 || putResp.statusCode == 201) {
        print("✅ 数据成功推送至云端！");
        return true;
      } else {
        print("❌ 云端推送失败！状态码: ${putResp.statusCode}");
        print("❌ GitHub 返回信息: ${putResp.body}");
        return false;
      }
    } catch (e) {
      print("❌ 推送发生底层网络异常: $e");
      return false;
    }
  }
}
