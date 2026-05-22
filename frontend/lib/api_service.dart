import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static const String _baseUrl = 'http://127.0.0.1:8000';

  static Future<Map<String, dynamic>> convertFile({
    required File file,
    int? start,
    int? stop,
    bool saveToObsidian = true,
  }) async {
    final queryParameters = <String, String>{
      if (start != null) 'start': start.toString(),
      if (stop != null) 'stop': stop.toString(),
      if (!saveToObsidian) 'save_to_obsidian': 'false',
    };

    final uri = Uri.parse('$_baseUrl/convert').replace(queryParameters: queryParameters);

    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: file.uri.pathSegments.last,
        contentType: MediaType('application', 'pdf'),
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Convert API failed: ${response.statusCode} ${response.reasonPhrase}\n${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}