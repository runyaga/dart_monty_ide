import 'dart:convert';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:http/http.dart' as http;

/// A [MontyVfs] implementation that communicates with a remote REST API.
class RestMontyVfs implements MontyVfs {
  /// Creates a [RestMontyVfs] with the given [baseUrl].
  RestMontyVfs({
    required this.baseUrl,
    this.authToken,
  });

  /// The base URL of the file management API.
  final String baseUrl;

  /// Optional authentication token.
  final String? authToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (authToken != null) 'Authorization': 'Bearer $authToken',
  };

  @override
  Future<List<String>> listFiles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/files'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data.cast<String>();
    }
    throw Exception('Failed to list files: ${response.statusCode}');
  }

  @override
  Future<String> readFile(String path) async {
    final response = await http.get(
      Uri.parse('$baseUrl/files/$path'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return response.body;
    }
    throw Exception('Failed to read file: ${response.statusCode}');
  }

  @override
  Future<void> writeFile(String path, String content) async {
    final response = await http.post(
      Uri.parse('$baseUrl/files/$path'),
      headers: _headers,
      body: content,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to write file: ${response.statusCode}');
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/files/$path'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to delete file: ${response.statusCode}');
    }
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rename'),
      headers: _headers,
      body: jsonEncode({
        'oldPath': oldPath,
        'newPath': newPath,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to rename file: ${response.statusCode}');
    }
  }
}
