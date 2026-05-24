import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  static Future<Map<String, dynamic>> convertFile({
    required File file,
    int? start,
    int? stop,
    bool saveToObsidian = true,
    String? vaultPath,
    String? outputFolder,
  }) async {
    if (saveToObsidian) {
      if (vaultPath == null) {
        throw Exception('Vault path is required.');
      }

      final analysis = await analyzeFile(
        file: file,
        vaultPath: vaultPath,
        outputFolder: outputFolder,
        start: start,
        stop: stop,
      );
      final analysisData = analysis['data'] as Map<String, dynamic>;
      final exportResult = await exportAnalysis(
        analysisData: analysisData,
        vaultPath: vaultPath,
        outputFolder: outputFolder,
        pdfPath: file.path,
      );

      return {
        'status': 'success',
        'data': {
          ...analysisData,
          'paper_title': analysisData['paper_title'] ?? analysisData['title'],
          'raw_markdown':
              analysisData['raw_markdown'] ?? analysisData['markdown_preview'],
          'export': exportResult['data'],
        },
      };
    }

    final queryParameters = <String, String>{
      if (start != null) 'start': start.toString(),
      if (stop != null) 'stop': stop.toString(),
      'save_to_obsidian': 'false',
    };

    final uri = Uri.parse(
      '$baseUrl/convert',
    ).replace(queryParameters: queryParameters);

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
      throw Exception(
        'Convert API failed: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> analyzeFile({
    required File file,
    required String vaultPath,
    String? outputFolder,
    int? start,
    int? stop,
  }) async {
    final queryParameters = <String, String>{
      if (start != null) 'start': start.toString(),
      if (stop != null) 'stop': stop.toString(),
    };
    final uri = Uri.parse(
      '$baseUrl/analyze',
    ).replace(queryParameters: queryParameters);

    final request = http.MultipartRequest('POST', uri)
      ..fields['vault_path'] = vaultPath;
    if (outputFolder != null && outputFolder.isNotEmpty) {
      request.fields['output_folder'] = outputFolder;
    }
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
      throw Exception(
        'Analyze API failed: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> exportAnalysis({
    required Map<String, dynamic> analysisData,
    required String vaultPath,
    String? outputFolder,
    required String pdfPath,
  }) async {
    final payload = <String, dynamic>{
      'analysis_id': analysisData['analysis_id'],
      'analysis': analysisData,
      'vault_path': vaultPath,
      'pdf_path': pdfPath,
    };
    if (outputFolder != null && outputFolder.isNotEmpty) {
      payload['output_folder'] = outputFolder;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/export'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Export API failed: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
