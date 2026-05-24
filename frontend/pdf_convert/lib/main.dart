import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const PaperToObsidianApp());
}

class PaperToObsidianApp extends StatelessWidget {
  const PaperToObsidianApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF157A7E),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDF to Obsidian Knowledge Nodes',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD6DAD5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD6DAD5)),
          ),
        ),
      ),
      home: const PaperToObsidianHome(),
    );
  }
}

class MyApp extends PaperToObsidianApp {
  const MyApp({super.key});
}

enum AppPage { pdf, vault, preview, result }

class PaperToObsidianHome extends StatefulWidget {
  const PaperToObsidianHome({super.key});

  @override
  State<PaperToObsidianHome> createState() => _PaperToObsidianHomeState();
}

class _PaperToObsidianHomeState extends State<PaperToObsidianHome> {
  final TextEditingController _apiBaseUrlController = TextEditingController(
    text: 'http://127.0.0.1:8000',
  );

  AppPage _page = AppPage.pdf;
  String? _pdfPath;
  String? _vaultPath;
  String? _vaultMessage;
  bool _vaultValid = false;
  bool _isAnalyzing = false;
  bool _isExporting = false;
  String? _errorMessage;
  AnalysisPreview? _preview;
  ExportResult? _result;

  bool get _canAnalyze =>
      _pdfPath != null && _vaultPath != null && _vaultValid && !_isAnalyzing;

  bool get _canExport => _preview != null && !_isExporting;

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    const pdfType = XTypeGroup(
      label: 'PDF',
      extensions: <String>['pdf'],
    );

    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[pdfType]);
    if (file == null || !mounted) {
      return;
    }

    setState(() {
      _pdfPath = file.path;
      _preview = null;
      _result = null;
      _errorMessage = null;
      _page = AppPage.vault;
    });
  }

  Future<void> _pickVault() async {
    final path = await getDirectoryPath(confirmButtonText: 'Select Vault');
    if (path == null || !mounted) {
      return;
    }

    final isValid = await _isValidVault(path);
    if (!mounted) {
      return;
    }

    setState(() {
      _vaultPath = path;
      _vaultValid = isValid;
      _vaultMessage = isValid
          ? 'Vault valid'
          : 'Invalid vault: missing .obsidian folder';
      _preview = null;
      _result = null;
      _errorMessage = null;
    });
  }

  Future<bool> _isValidVault(String path) {
    return Directory(_joinPath(path, '.obsidian')).exists();
  }

  Future<void> _analyze() async {
    if (!_canAnalyze) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _preview = null;
      _result = null;
    });

    try {
      final request = http.MultipartRequest('POST', _endpoint('/analyze'))
        ..fields['vault_path'] = _vaultPath!
        ..fields['pdf_path'] = _pdfPath!
        ..files.add(await http.MultipartFile.fromPath('file', _pdfPath!));

      final streamedResponse = await request
          .send()
          .timeout(const Duration(minutes: 30));
      final responseBody = await streamedResponse.stream
          .bytesToString()
          .timeout(const Duration(minutes: 30));
      _throwForBadStatus(streamedResponse.statusCode, responseBody);

      final decoded = _decodeJson(responseBody);
      final preview = AnalysisPreview.fromJson(
        decoded,
        vaultPath: _vaultPath!,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preview = preview;
        _page = AppPage.preview;
      });
    } on TimeoutException {
      _showError('Analyze timed out. Backend may still be processing the PDF.');
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('Analyze failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _export() async {
    final preview = _preview;
    if (preview == null || !_canExport) {
      return;
    }

    setState(() {
      _isExporting = true;
      _errorMessage = null;
      _result = null;
    });

    final payload = <String, dynamic>{
      'analysis_id': preview.analysisId,
      'vault_path': _vaultPath,
      'pdf_path': _pdfPath,
      'output_folder': preview.outputFolder,
    }..removeWhere(_isEmptyPayloadValue);

    if (preview.analysisId == null || preview.analysisId!.isEmpty) {
      payload['analysis'] = preview.raw;
    }

    try {
      final response = await http
          .post(
            _endpoint('/export'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 10));

      _throwForBadStatus(response.statusCode, response.body);
      final decoded = _decodeJson(response.body);
      final result = ExportResult.fromJson(decoded);

      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
        _page = AppPage.result;
      });
    } on TimeoutException {
      _showError('Export timed out. Backend may still be writing files.');
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('Export failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _openFolder(String folderPath) async {
    if (folderPath.isEmpty) {
      return;
    }

    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', <String>[folderPath]);
      } else if (Platform.isMacOS) {
        await Process.start('open', <String>[folderPath]);
      } else {
        await Process.start('xdg-open', <String>[folderPath]);
      }
    } catch (error) {
      _showError('Cannot open folder: $error');
    }
  }

  Uri _endpoint(String path) {
    final rawBaseUrl = _apiBaseUrlController.text.trim();
    final withScheme = rawBaseUrl.startsWith(RegExp(r'https?://'))
        ? rawBaseUrl
        : 'http://$rawBaseUrl';
    final baseUrl = withScheme.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$baseUrl$path');
  }

  dynamic _decodeJson(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      return jsonDecode(body);
    } catch (_) {
      throw ApiException('Backend returned non-JSON response: ${_short(body)}');
    }
  }

  void _throwForBadStatus(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }

    final detail = _extractErrorDetail(body);
    throw ApiException(
      'Backend request failed ($statusCode)'
      '${detail.isEmpty ? '' : ': $detail'}',
    );
  }

  String _extractErrorDetail(String body) {
    if (body.trim().isEmpty) {
      return '';
    }

    try {
      final decoded = jsonDecode(body);
      final root = _asMap(decoded);
      final detail = _pick(root, <String>['detail', 'message', 'error']);
      return _text(detail).isNotEmpty ? _text(detail) : _short(body);
    } catch (_) {
      return _short(body);
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _errorMessage = message;
    });
  }

  void _goTo(AppPage page) {
    if (page == AppPage.preview && _preview == null) {
      return;
    }
    if (page == AppPage.result && _result == null) {
      return;
    }

    setState(() {
      _page = page;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: <Widget>[
            _Sidebar(
              page: _page,
              pdfSelected: _pdfPath != null,
              vaultValid: _vaultValid,
              hasPreview: _preview != null,
              hasResult: _result != null,
              onPageSelected: _goTo,
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  _TopBar(controller: _apiBaseUrlController),
                  if (_errorMessage != null)
                    _ErrorBanner(
                      message: _errorMessage!,
                      onDismissed: () {
                        setState(() {
                          _errorMessage = null;
                        });
                      },
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _buildCurrentPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    if (_isAnalyzing) {
      return const _LoadingView(
        key: ValueKey<String>('analyzing'),
        title: 'Analyzing PDF',
        message: 'Backend is preparing the preview.',
      );
    }

    if (_isExporting) {
      return const _LoadingView(
        key: ValueKey<String>('exporting'),
        title: 'Exporting Nodes',
        message: 'Backend is writing the Obsidian notes.',
      );
    }

    switch (_page) {
      case AppPage.pdf:
        return _PdfPage(
          key: const ValueKey<String>('pdf'),
          pdfPath: _pdfPath,
          onPickPdf: _pickPdf,
          onNext: _pdfPath == null ? null : () => _goTo(AppPage.vault),
        );
      case AppPage.vault:
        return _VaultPage(
          key: const ValueKey<String>('vault'),
          vaultPath: _vaultPath,
          vaultValid: _vaultValid,
          vaultMessage: _vaultMessage,
          canAnalyze: _canAnalyze,
          onPickVault: _pickVault,
          onAnalyze: _analyze,
        );
      case AppPage.preview:
        final preview = _preview;
        if (preview == null) {
          return const _EmptyState(
            key: ValueKey<String>('no-preview'),
            icon: Icons.preview_outlined,
            title: 'No Preview',
          );
        }
        return _PreviewPage(
          key: const ValueKey<String>('preview'),
          preview: preview,
          onBack: () => _goTo(AppPage.vault),
          onExport: _canExport ? _export : null,
        );
      case AppPage.result:
        final result = _result;
        if (result == null) {
          return const _EmptyState(
            key: ValueKey<String>('no-result'),
            icon: Icons.task_alt_outlined,
            title: 'No Result',
          );
        }
        return _ResultPage(
          key: const ValueKey<String>('result'),
          result: result,
          onOpenFolder: result.folderPath.isEmpty
              ? null
              : () => _openFolder(result.folderPath),
        );
    }
  }
}

class AnalysisPreview {
  const AnalysisPreview({
    required this.title,
    required this.authors,
    required this.keywords,
    required this.abstractText,
    required this.sections,
    required this.references,
    required this.nodes,
    required this.markdownPreview,
    required this.outputFolder,
    required this.raw,
    this.analysisId,
  });

  final String title;
  final List<String> authors;
  final List<String> keywords;
  final String abstractText;
  final List<SectionPreview> sections;
  final List<String> references;
  final List<NodePreview> nodes;
  final String markdownPreview;
  final String outputFolder;
  final String? analysisId;
  final Map<String, dynamic> raw;

  factory AnalysisPreview.fromJson(dynamic decoded, {required String vaultPath}) {
    final root = _asMap(decoded);
    final data = _payloadRoot(decoded);
    final metadata = _asMap(_pick(data, <String>['metadata']));
    final files = _asMap(_pick(data, <String>['files']));
    final obsidian = _asMap(_pick(data, <String>['obsidian']));
    final rawNodes = _pick(
      data,
      <String>['nodes_to_create', 'planned_nodes', 'knowledge_nodes', 'nodes'],
    );

    final title = _firstText(<dynamic>[
      _pick(data, <String>['title', 'paper_title', 'paperTitle']),
      _pick(metadata, <String>['title']),
    ], fallback: 'Untitled Paper');

    final referencesRaw =
        _pick(data, <String>['references', 'bibliography']) ??
        _pick(metadata, <String>['references', 'bibliography']) ??
        _namedMapValue(rawNodes, <String>['references', 'bibliography']);

    var sections = SectionPreview.listFrom(
      _pick(data, <String>['sections', 'section_list']),
    );
    if (sections.isEmpty) {
      sections = SectionPreview.listFrom(rawNodes, skipMetadataNodes: true);
    }

    final outputFolder = _firstText(<dynamic>[
      _pick(data, <String>['output_folder', 'output_dir', 'folder_path']),
      _pick(files, <String>['output_folder', 'output_dir', 'folder_path']),
      _pick(obsidian, <String>['folder_path', 'output_folder']),
      _parentFolder(_text(_pick(files, <String>['obsidian_note']))),
      _parentFolder(_text(_pick(obsidian, <String>['path']))),
      vaultPath,
    ]);

    return AnalysisPreview(
      title: title,
      authors: _textList(
        _pick(metadata, <String>['authors']) ??
            _pick(data, <String>['authors']),
        splitPattern: RegExp(r'\s+and\s+|;|\n'),
      ),
      keywords: _textList(
        _pick(metadata, <String>['keywords']) ??
            _pick(data, <String>['keywords']),
        splitPattern: RegExp(r'[,;\n]'),
      ),
      abstractText: _firstText(<dynamic>[
        _pick(metadata, <String>['abstract']),
        _pick(data, <String>['abstract']),
        _namedMapValue(rawNodes, <String>['abstract']),
      ]),
      sections: sections,
      references: _textList(referencesRaw, splitPattern: RegExp(r'\n+')),
      nodes: NodePreview.listFrom(rawNodes),
      markdownPreview: _firstText(<dynamic>[
        _pick(data, <String>[
          'markdown_preview',
          'preview_markdown',
          'markdown',
          'raw_markdown',
        ]),
      ]),
      outputFolder: outputFolder,
      analysisId: _firstText(<dynamic>[
        _pick(data, <String>['analysis_id', 'id']),
        _pick(root, <String>['analysis_id']),
      ]),
      raw: data,
    );
  }
}

class SectionPreview {
  const SectionPreview({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  static List<SectionPreview> listFrom(
    dynamic value, {
    bool skipMetadataNodes = false,
  }) {
    if (value == null) {
      return <SectionPreview>[];
    }

    if (value is List) {
      return value.indexed
          .map((entry) {
            final index = entry.$1;
            final item = entry.$2;
            final map = _asMap(item);
            if (map.isNotEmpty) {
              final title = _firstText(
                <dynamic>[_pick(map, <String>['title', 'name', 'heading'])],
                fallback: 'Section ${index + 1}',
              );
              return SectionPreview(
                title: title,
                content: _firstText(<dynamic>[
                  _pick(map, <String>['content', 'text', 'markdown', 'body']),
                ]),
              );
            }

            return SectionPreview(
              title: 'Section ${index + 1}',
              content: _text(item),
            );
          })
          .where((section) => section.title.isNotEmpty || section.content.isNotEmpty)
          .toList();
    }

    if (value is Map) {
      final sections = <SectionPreview>[];
      for (final entry in value.entries) {
        final title = entry.key.toString();
        if (skipMetadataNodes && _isMetadataNode(title)) {
          continue;
        }
        sections.add(
          SectionPreview(title: title, content: _text(entry.value)),
        );
      }
      return sections;
    }

    final text = _text(value);
    return text.isEmpty
        ? <SectionPreview>[]
        : <SectionPreview>[SectionPreview(title: 'Content', content: text)];
  }
}

class NodePreview {
  const NodePreview({
    required this.title,
    this.type = '',
    this.path = '',
  });

  final String title;
  final String type;
  final String path;

  static List<NodePreview> listFrom(dynamic value) {
    if (value == null) {
      return <NodePreview>[];
    }

    if (value is List) {
      return value.indexed
          .map((entry) {
            final index = entry.$1;
            final item = entry.$2;
            final map = _asMap(item);
            if (map.isEmpty) {
              return NodePreview(title: _text(item));
            }

            return NodePreview(
              title: _firstText(
                <dynamic>[_pick(map, <String>['title', 'name', 'label'])],
                fallback: 'Node ${index + 1}',
              ),
              type: _firstText(<dynamic>[
                _pick(map, <String>['type', 'kind']),
              ]),
              path: _firstText(<dynamic>[
                _pick(map, <String>['path', 'file_path', 'target_path']),
              ]),
            );
          })
          .where((node) => node.title.isNotEmpty)
          .toList();
    }

    if (value is Map) {
      return value.entries.map((entry) {
        final map = _asMap(entry.value);
        return NodePreview(
          title: entry.key.toString(),
          type: _firstText(<dynamic>[
            _pick(map, <String>['type', 'kind']),
          ], fallback: map.isEmpty ? 'section' : ''),
          path: _firstText(<dynamic>[
            _pick(map, <String>['path', 'file_path', 'target_path']),
          ]),
        );
      }).toList();
    }

    final text = _text(value);
    return text.isEmpty ? <NodePreview>[] : <NodePreview>[NodePreview(title: text)];
  }
}

class ExportResult {
  const ExportResult({
    required this.success,
    required this.nodesCreated,
    required this.folderPath,
    required this.filesCreated,
  });

  final bool success;
  final int nodesCreated;
  final String folderPath;
  final List<String> filesCreated;

  factory ExportResult.fromJson(dynamic decoded) {
    final root = _payloadRoot(decoded);
    final files = _pick(root, <String>['files_created', 'created_files']) ??
        _pick(root, <String>['files']);
    final filesCreated = _textList(files, splitPattern: RegExp(r'\n+'));

    return ExportResult(
      success: _bool(_pick(root, <String>['export_success', 'success', 'saved'])) ??
          _text(_pick(root, <String>['status'])).toLowerCase() == 'success',
      nodesCreated: _intValue(
            _pick(root, <String>['nodes_created', 'node_count']),
          ) ??
          _collectionLength(_pick(root, <String>['nodes'])) ??
          filesCreated.length,
      folderPath: _firstText(<dynamic>[
        _pick(root, <String>['folder_path', 'output_folder', 'output_dir']),
        _parentFolder(_firstText(<dynamic>[
          _pick(root, <String>['obsidian_note', 'path']),
        ])),
        filesCreated.isEmpty ? '' : _parentFolder(filesCreated.first),
      ]),
      filesCreated: filesCreated,
    );
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.page,
    required this.pdfSelected,
    required this.vaultValid,
    required this.hasPreview,
    required this.hasResult,
    required this.onPageSelected,
  });

  final AppPage page;
  final bool pdfSelected;
  final bool vaultValid;
  final bool hasPreview;
  final bool hasResult;
  final ValueChanged<AppPage> onPageSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 238,
      color: const Color(0xFF182426),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.hub_outlined, color: Color(0xFF8ED7CC), size: 32),
          const SizedBox(height: 14),
          const Text(
            'PDF to Obsidian',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Knowledge Nodes',
            style: TextStyle(color: Color(0xFFADC4C2), fontSize: 13),
          ),
          const SizedBox(height: 34),
          _StepButton(
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF',
            selected: page == AppPage.pdf,
            complete: pdfSelected,
            onPressed: () => onPageSelected(AppPage.pdf),
          ),
          _StepButton(
            icon: Icons.folder_open_outlined,
            label: 'Vault',
            selected: page == AppPage.vault,
            complete: vaultValid,
            onPressed: () => onPageSelected(AppPage.vault),
          ),
          _StepButton(
            icon: Icons.preview_outlined,
            label: 'Preview',
            selected: page == AppPage.preview,
            complete: hasPreview,
            enabled: hasPreview,
            onPressed: () => onPageSelected(AppPage.preview),
          ),
          _StepButton(
            icon: Icons.task_alt_outlined,
            label: 'Result',
            selected: page == AppPage.result,
            complete: hasResult,
            enabled: hasResult,
            onPressed: () => onPageSelected(AppPage.result),
          ),
          const Spacer(),
          const Text(
            'Backend endpoints',
            style: TextStyle(color: Color(0xFFADC4C2), fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text(
            'POST /analyze\nPOST /export',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.complete,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool complete;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFFC4D5D3);
    final background = selected ? const Color(0xFF264A4D) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: <Widget>[
                Icon(icon, color: enabled ? foreground : const Color(0xFF667B7A)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: enabled ? foreground : const Color(0xFF667B7A),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (complete)
                  const Icon(Icons.check_circle, color: Color(0xFF8ED7CC), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE1E4E0))),
      ),
      child: Row(
        children: <Widget>[
          const Text(
            'PDF to Obsidian Knowledge Nodes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          SizedBox(
            width: 360,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'API Base URL',
                prefixIcon: Icon(Icons.link),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismissed,
  });

  final String message;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0EC),
        border: Border.all(color: const Color(0xFFFFB8A8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, color: Color(0xFFB9361A)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismissed,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _PdfPage extends StatelessWidget {
  const _PdfPage({
    super.key,
    required this.pdfPath,
    required this.onPickPdf,
    required this.onNext,
  });

  final String? pdfPath;
  final VoidCallback onPickPdf;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Select PDF',
      icon: Icons.picture_as_pdf_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _InfoPanel(
            title: 'PDF',
            icon: Icons.description_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _PathDisplay(
                  label: pdfPath == null ? 'No PDF selected' : _fileName(pdfPath!),
                  path: pdfPath ?? '',
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    ElevatedButton.icon(
                      onPressed: onPickPdf,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Select PDF'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: onNext,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultPage extends StatelessWidget {
  const _VaultPage({
    super.key,
    required this.vaultPath,
    required this.vaultValid,
    required this.vaultMessage,
    required this.canAnalyze,
    required this.onPickVault,
    required this.onAnalyze,
  });

  final String? vaultPath;
  final bool vaultValid;
  final String? vaultMessage;
  final bool canAnalyze;
  final VoidCallback onPickVault;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Select Obsidian Vault',
      icon: Icons.folder_open_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _InfoPanel(
            title: 'Vault Folder',
            icon: Icons.folder_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _PathDisplay(
                  label: vaultPath == null ? 'No vault selected' : _fileName(vaultPath!),
                  path: vaultPath ?? '',
                ),
                const SizedBox(height: 14),
                _ValidationPill(
                  valid: vaultValid,
                  text: vaultMessage ?? 'Waiting for vault selection',
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: onPickVault,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Select Vault'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: canAnalyze ? onAnalyze : null,
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Analyze'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPage extends StatelessWidget {
  const _PreviewPage({
    super.key,
    required this.preview,
    required this.onBack,
    required this.onExport,
  });

  final AnalysisPreview preview;
  final VoidCallback onBack;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Preview',
      icon: Icons.preview_outlined,
      actions: <Widget>[
        OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Vault'),
        ),
        FilledButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Export'),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final leftColumn = Column(
            children: <Widget>[
              _InfoPanel(
                title: 'Paper',
                icon: Icons.article_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _LabelValue(label: 'Title', value: preview.title),
                    _LabelValue(
                      label: 'Authors',
                      value: preview.authors.join(', '),
                    ),
                    _ChipList(label: 'Keywords', values: preview.keywords),
                    const SizedBox(height: 12),
                    _BlockText(
                      label: 'Abstract',
                      value: preview.abstractText,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _InfoPanel(
                title: 'Sections',
                icon: Icons.subject_outlined,
                child: _SectionList(sections: preview.sections),
              ),
              const SizedBox(height: 16),
              _InfoPanel(
                title: 'References',
                icon: Icons.format_quote_outlined,
                child: _SimpleList(values: preview.references),
              ),
            ],
          );

          final rightColumn = Column(
            children: <Widget>[
              _InfoPanel(
                title: 'Nodes To Create',
                icon: Icons.account_tree_outlined,
                child: _NodeList(nodes: preview.nodes),
              ),
              const SizedBox(height: 16),
              _InfoPanel(
                title: 'Markdown Preview',
                icon: Icons.notes_outlined,
                child: _MarkdownBox(markdown: preview.markdownPreview),
              ),
              const SizedBox(height: 16),
              _InfoPanel(
                title: 'Output Folder',
                icon: Icons.drive_folder_upload_outlined,
                child: _PathDisplay(
                  label: _fileName(preview.outputFolder),
                  path: preview.outputFolder,
                ),
              ),
            ],
          );

          if (constraints.maxWidth < 980) {
            return Column(
              children: <Widget>[
                leftColumn,
                const SizedBox(height: 16),
                rightColumn,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 6, child: leftColumn),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: rightColumn),
            ],
          );
        },
      ),
    );
  }
}

class _ResultPage extends StatelessWidget {
  const _ResultPage({
    super.key,
    required this.result,
    required this.onOpenFolder,
  });

  final ExportResult result;
  final VoidCallback? onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Result',
      icon: Icons.task_alt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _InfoPanel(
            title: 'Export',
            icon: result.success ? Icons.check_circle_outline : Icons.error_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ValidationPill(
                  valid: result.success,
                  text: result.success ? 'Export success' : 'Export failed',
                ),
                const SizedBox(height: 18),
                _LabelValue(
                  label: 'Nodes created',
                  value: result.nodesCreated.toString(),
                ),
                _LabelValue(label: 'Folder path', value: result.folderPath),
                const SizedBox(height: 16),
                _SimpleList(
                  title: 'Files created',
                  values: result.filesCreated,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onOpenFolder,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open Folder'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageShell extends StatelessWidget {
  const _PageShell({
    required this.title,
    required this.icon,
    required this.child,
    this.actions = const <Widget>[],
  });

  final String title;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final action in actions) ...<Widget>[
                const SizedBox(width: 10),
                action,
              ],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE0DB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 20, color: const Color(0xFF157A7E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PathDisplay extends StatelessWidget {
  const _PathDisplay({
    required this.label,
    required this.path,
  });

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        border: Border.all(color: const Color(0xFFE0E5E3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF55706E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (path.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  SelectableText(
                    path,
                    style: const TextStyle(
                      color: Color(0xFF5F6F6E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationPill extends StatelessWidget {
  const _ValidationPill({
    required this.valid,
    required this.text,
  });

  final bool valid;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: valid ? const Color(0xFFE8F7EF) : const Color(0xFFFFF7E6),
        border: Border.all(
          color: valid ? const Color(0xFF87C9A4) : const Color(0xFFE3B75C),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              valid ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
              color: valid ? const Color(0xFF257746) : const Color(0xFF9B6A00),
            ),
            const SizedBox(width: 8),
            Text(text),
          ],
        ),
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF5D6A67),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value.isEmpty ? '-' : value),
          ),
        ],
      ),
    );
  }
}

class _BlockText extends StatelessWidget {
  const _BlockText({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5D6A67),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(value.isEmpty ? '-' : value),
      ],
    );
  }
}

class _ChipList extends StatelessWidget {
  const _ChipList({
    required this.label,
    required this.values,
  });

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF5D6A67),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: values.isEmpty
                ? const Text('-')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: values
                        .map(
                          (value) => Chip(
                            label: Text(value),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({required this.sections});

  final List<SectionPreview> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return const Text('-');
    }

    return Column(
      children: sections
          .map(
            (section) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E5E3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  section.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      section.content.isEmpty ? '-' : section.content,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SimpleList extends StatelessWidget {
  const _SimpleList({
    required this.values,
    this.title,
  });

  final List<String> values;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final content = values.isEmpty
        ? const Text('-')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: values
                .map(
                  (value) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 7),
                          child: Icon(Icons.circle, size: 6),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: SelectableText(value)),
                      ],
                    ),
                  ),
                )
                .toList(),
          );

    if (title == null) {
      return content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title!,
          style: const TextStyle(
            color: Color(0xFF5D6A67),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        content,
      ],
    );
  }
}

class _NodeList extends StatelessWidget {
  const _NodeList({required this.nodes});

  final List<NodePreview> nodes;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const Text('-');
    }

    return Column(
      children: nodes
          .map(
            (node) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9F8),
                border: Border.all(color: const Color(0xFFE0E5E3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.note_add_outlined, color: Color(0xFF157A7E)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          node.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (node.type.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            node.type,
                            style: const TextStyle(color: Color(0xFF657472)),
                          ),
                        ],
                        if (node.path.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          SelectableText(
                            node.path,
                            style: const TextStyle(
                              color: Color(0xFF657472),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MarkdownBox extends StatelessWidget {
  const _MarkdownBox({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 420),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111817),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          markdown.isEmpty ? '-' : markdown,
          style: const TextStyle(
            color: Color(0xFFE2E9E7),
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 5),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: Color(0xFF657472))),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 46, color: const Color(0xFF7E918F)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _payloadRoot(dynamic decoded) {
  final map = _asMap(decoded);
  final data = _pick(map, <String>['data', 'result', 'analysis']);
  final dataMap = _asMap(data);
  return dataMap.isEmpty ? map : dataMap;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}

dynamic _pick(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    if (source.containsKey(key)) {
      return source[key];
    }
  }

  final normalizedKeys = keys.map(_normalizeKey).toSet();
  for (final entry in source.entries) {
    if (normalizedKeys.contains(_normalizeKey(entry.key))) {
      return entry.value;
    }
  }

  return null;
}

dynamic _namedMapValue(dynamic value, List<String> keys) {
  final map = _asMap(value);
  if (map.isEmpty) {
    return null;
  }

  final normalizedKeys = keys.map(_normalizeKey).toSet();
  for (final entry in map.entries) {
    if (normalizedKeys.contains(_normalizeKey(entry.key))) {
      return entry.value;
    }
  }
  return null;
}

String _normalizeKey(String value) {
  return value.replaceAll(RegExp(r'[_\-\s]'), '').toLowerCase();
}

String _firstText(List<dynamic> values, {String fallback = ''}) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) {
      return text;
    }
  }
  return fallback;
}

String _text(dynamic value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value.trim();
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  if (value is List) {
    return value.map(_text).where((item) => item.isNotEmpty).join('\n');
  }
  if (value is Map) {
    final map = _asMap(value);
    return _firstText(<dynamic>[
      _pick(map, <String>['title', 'name', 'content', 'text', 'path']),
      jsonEncode(map),
    ]);
  }
  return value.toString().trim();
}

List<String> _textList(dynamic value, {Pattern? splitPattern}) {
  if (value == null) {
    return <String>[];
  }
  if (value is List) {
    return value.map(_text).where((item) => item.isNotEmpty).toList();
  }
  if (value is Map) {
    return value.entries
        .map((entry) => _text(entry.value).isEmpty ? entry.key.toString() : _text(entry.value))
        .where((item) => item.isNotEmpty)
        .toList();
  }

  final text = _text(value);
  if (text.isEmpty) {
    return <String>[];
  }
  if (splitPattern == null) {
    return <String>[text];
  }
  return text
      .split(splitPattern)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

bool? _bool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final lower = value.toLowerCase();
    if (<String>{'true', 'yes', '1', 'success'}.contains(lower)) {
      return true;
    }
    if (<String>{'false', 'no', '0', 'failed', 'error'}.contains(lower)) {
      return false;
    }
  }
  return null;
}

int? _intValue(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  if (value is List || value is Map) {
    return _collectionLength(value);
  }
  return null;
}

int? _collectionLength(dynamic value) {
  if (value is List) {
    return value.length;
  }
  if (value is Map) {
    return value.length;
  }
  return null;
}

bool _isMetadataNode(String title) {
  final normalized = _normalizeKey(title);
  return <String>{
    'abstract',
    'keywords',
    'references',
    'bibliography',
    'metadatafrontmatter',
  }.contains(normalized);
}

bool _isEmptyPayloadValue(String _, dynamic value) {
  return value == null || (value is String && value.trim().isEmpty);
}

String _joinPath(String parent, String child) {
  if (parent.endsWith('/') || parent.endsWith('\\')) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

String _fileName(String path) {
  if (path.isEmpty) {
    return '';
  }
  final slashIndex = path.lastIndexOf('/');
  final backslashIndex = path.lastIndexOf('\\');
  final index = slashIndex > backslashIndex ? slashIndex : backslashIndex;
  return index == -1 ? path : path.substring(index + 1);
}

String _parentFolder(String path) {
  if (path.isEmpty) {
    return '';
  }
  final slashIndex = path.lastIndexOf('/');
  final backslashIndex = path.lastIndexOf('\\');
  final index = slashIndex > backslashIndex ? slashIndex : backslashIndex;
  return index == -1 ? '' : path.substring(0, index);
}

String _short(String value) {
  const maxLength = 320;
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength)}...';
}
