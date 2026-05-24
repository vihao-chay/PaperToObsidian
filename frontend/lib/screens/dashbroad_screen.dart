import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  File? selectedPdf;
  String? vaultPath;
  bool vaultValid = false;
  bool isBusy = false;
  double progress = 0;
  String statusText = 'Chọn PDF để bắt đầu.';
  String? errorText;
  Map<String, dynamic>? analysisData;
  bool exportSuccess = false;
  int nodesCreated = 0;
  String? folderPath;
  List<String> filesCreated = [];
  final TextEditingController startPageController = TextEditingController();
  final TextEditingController stopPageController = TextEditingController();
  Timer? progressTimer;

  bool get canSelectVault => selectedPdf != null && !isBusy;
  bool get canAnalyze => selectedPdf != null && vaultValid && !isBusy;
  bool get canExport =>
      analysisData != null && selectedPdf != null && vaultValid && !isBusy;

  @override
  void dispose() {
    progressTimer?.cancel();
    startPageController.dispose();
    stopPageController.dispose();
    super.dispose();
  }

  Future<void> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      allowedExtensions: const ['pdf'],
      dialogTitle: 'Chọn PDF',
      lockParentWindow: true,
      type: FileType.custom,
    );

    final path = result?.files.single.path;
    if (path == null) {
      return;
    }

    setState(() {
      selectedPdf = File(path);
      errorText = null;
      progress = 0;
      statusText = vaultValid
          ? 'PDF đã sẵn sàng. Bấm Analyze để xem Preview.'
          : 'PDF đã sẵn sàng. Hãy chọn Obsidian Vault.';
      clearAnalysisAndResult();
    });
  }

  Future<void> pickVault() async {
    if (!canSelectVault) {
      showSnack('Hãy chọn PDF trước.');
      return;
    }

    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn Obsidian Vault',
      lockParentWindow: true,
    );
    if (path == null) {
      return;
    }

    final isValid = await Directory(_obsidianFolder(path)).exists();
    if (!mounted) {
      return;
    }

    setState(() {
      vaultPath = path;
      vaultValid = isValid;
      errorText = isValid
          ? null
          : 'Vault không hợp lệ: thiếu folder .obsidian.';
      progress = 0;
      statusText = isValid
          ? 'Vault hợp lệ. Bấm Analyze để xem Preview.'
          : 'Hãy chọn đúng Obsidian Vault.';
      clearAnalysisAndResult();
    });
  }

  Future<void> analyzePdf() async {
    if (selectedPdf == null) {
      showSnack('Hãy chọn PDF trước.');
      return;
    }
    if (!vaultValid || vaultPath == null) {
      showSnack('Hãy chọn Obsidian Vault hợp lệ.');
      return;
    }
    final pageRange = resolvePageRange();
    if (pageRange == null) {
      return;
    }

    setState(() {
      isBusy = true;
      errorText = null;
      progress = 0.06;
      statusText = 'Đang tải PDF lên backend...';
      clearAnalysisAndResult();
    });

    try {
      startProgressTicker(target: 0.88, label: 'Backend đang phân tích PDF...');
      final response = await ApiService.analyzeFile(
        file: selectedPdf!,
        vaultPath: vaultPath!,
        start: pageRange[0],
        stop: pageRange[1],
      );

      progressTimer?.cancel();
      final data = response['data'] as Map<String, dynamic>? ?? {};

      setState(() {
        analysisData = data;
        exportSuccess = false;
        nodesCreated = 0;
        folderPath = null;
        filesCreated = [];
        progress = 1;
        statusText = 'Preview đã sẵn sàng. Kiểm tra rồi Export.';
      });
    } catch (error) {
      progressTimer?.cancel();
      final message = friendlyError(error);
      setState(() {
        errorText = message;
        statusText = message;
      });
    } finally {
      progressTimer?.cancel();
      if (mounted) {
        setState(() {
          isBusy = false;
        });
      }
    }
  }

  Future<void> exportNotes() async {
    final data = analysisData;
    if (data == null) {
      showSnack('Hãy Analyze trước khi Export.');
      return;
    }
    if (!vaultValid || vaultPath == null || selectedPdf == null) {
      showSnack('Hãy chọn PDF và Vault hợp lệ.');
      return;
    }

    setState(() {
      isBusy = true;
      errorText = null;
      exportSuccess = false;
      nodesCreated = 0;
      folderPath = null;
      filesCreated = [];
      progress = 0.12;
      statusText = 'Đang ghi notes vào Obsidian...';
    });

    try {
      startProgressTicker(target: 0.78, label: 'Backend đang export nodes...');
      final response = await ApiService.exportAnalysis(
        analysisData: data,
        vaultPath: vaultPath!,
        pdfPath: selectedPdf!.path,
      );

      progressTimer?.cancel();
      final exportData = response['data'] as Map<String, dynamic>? ?? {};
      final files = _stringList(exportData['files_created']);

      setState(() {
        exportSuccess = exportData['export_success'] != false;
        nodesCreated = _intValue(exportData['nodes_created'], files.length);
        folderPath = _previewText(exportData['folder_path']);
        filesCreated = files;
        progress = 1;
        statusText = 'Export thành công. Notes đã ở trong Vault.';
      });
    } catch (error) {
      progressTimer?.cancel();
      final message = friendlyError(error);
      setState(() {
        errorText = message;
        statusText = message;
      });
    } finally {
      progressTimer?.cancel();
      if (mounted) {
        setState(() {
          isBusy = false;
        });
      }
    }
  }

  Future<void> openFolder() async {
    final path = folderPath;
    if (path == null || path.isEmpty) {
      showSnack('Backend chưa trả về folder path.');
      return;
    }

    if (Platform.isWindows) {
      await Process.start('explorer.exe', [path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path]);
    } else {
      await Process.start('xdg-open', [path]);
    }
  }

  void reset() {
    progressTimer?.cancel();
    setState(() {
      selectedPdf = null;
      vaultPath = null;
      vaultValid = false;
      isBusy = false;
      progress = 0;
      statusText = 'Chọn PDF để bắt đầu.';
      errorText = null;
      startPageController.clear();
      stopPageController.clear();
      clearAnalysisAndResult();
    });
  }

  void clearAnalysisAndResult() {
    analysisData = null;
    exportSuccess = false;
    nodesCreated = 0;
    folderPath = null;
    filesCreated = [];
  }

  void pageRangeChanged() {
    if (analysisData == null && !exportSuccess) {
      return;
    }

    setState(() {
      progress = 0;
      errorText = null;
      statusText = 'Khoảng trang đã đổi. Bấm Analyze để tạo Preview mới.';
      clearAnalysisAndResult();
    });
  }

  List<int?>? resolvePageRange() {
    final start = parsePageValue(startPageController.text, 'Trang bắt đầu');
    if (start == -1) {
      return null;
    }
    final stop = parsePageValue(stopPageController.text, 'Trang kết thúc');
    if (stop == -1) {
      return null;
    }

    if (start != null && stop != null && stop < start) {
      final message = 'Trang kết thúc phải lớn hơn hoặc bằng trang bắt đầu.';
      setState(() {
        errorText = message;
        statusText = message;
      });
      return null;
    }

    return [start, stop];
  }

  int? parsePageValue(String rawValue, String label) {
    final text = rawValue.trim();
    if (text.isEmpty) {
      return null;
    }

    final value = int.tryParse(text);
    if (value == null || value < 1) {
      final message = '$label phải là số nguyên dương.';
      setState(() {
        errorText = message;
        statusText = message;
      });
      return -1;
    }

    return value;
  }

  void startProgressTicker({required double target, required String label}) {
    progressTimer?.cancel();
    setState(() {
      statusText = label;
    });

    progressTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted || progress >= target) {
        return;
      }
      setState(() {
        progress = (progress + 0.025).clamp(0.0, target);
      });
    });
  }

  void showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String friendlyError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('failed to establish') ||
        lower.contains('connection refused') ||
        lower.contains('socket')) {
      return 'Không kết nối được backend tại ${ApiService.baseUrl}.';
    }
    if (lower.contains('404')) {
      return 'Backend chưa có endpoint /analyze hoặc /export.';
    }
    if (lower.contains('pdf')) {
      return 'PDF không hợp lệ hoặc backend không xử lý được file này.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  String _obsidianFolder(String path) {
    final separator = path.endsWith(Platform.pathSeparator)
        ? ''
        : Platform.pathSeparator;
    return '$path$separator.obsidian';
  }

  int _intValue(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Column(
          children: [
            _Header(onReset: isBusy ? null : reset),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 22,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final pdfCard = _StepCard(
                              step: '1',
                              title: 'Chọn PDF',
                              subtitle: 'File bài báo cần phân tích',
                              icon: Icons.picture_as_pdf_outlined,
                              buttonIcon: Icons.upload_file_outlined,
                              path: selectedPdf?.path,
                              status: selectedPdf == null
                                  ? 'Chưa chọn'
                                  : 'Đã chọn',
                              active: true,
                              valid: selectedPdf != null,
                              buttonLabel: selectedPdf == null
                                  ? 'Chọn PDF'
                                  : 'Đổi PDF',
                              onPressed: isBusy ? null : pickPdf,
                            );
                            final vaultCard = _StepCard(
                              step: '2',
                              title: 'Chọn Vault',
                              subtitle: 'Thư mục Vault có .obsidian',
                              icon: Icons.folder_copy_outlined,
                              buttonIcon: Icons.folder_open_outlined,
                              path: vaultPath,
                              status: vaultPath == null
                                  ? 'Chưa chọn'
                                  : vaultValid
                                  ? 'Hợp lệ'
                                  : 'Không hợp lệ',
                              active: canSelectVault,
                              valid: vaultValid,
                              buttonLabel: vaultPath == null
                                  ? 'Chọn Vault'
                                  : 'Đổi Vault',
                              onPressed: canSelectVault ? pickVault : null,
                            );

                            if (constraints.maxWidth < 760) {
                              return Column(
                                children: [
                                  pdfCard,
                                  const SizedBox(height: 14),
                                  vaultCard,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: pdfCard),
                                const SizedBox(width: 14),
                                Expanded(child: vaultCard),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        _PageRangePanel(
                          startController: startPageController,
                          stopController: stopPageController,
                          enabled: !isBusy,
                          onChanged: pageRangeChanged,
                        ),
                        const SizedBox(height: 14),
                        _ActionPanel(
                          progress: progress,
                          statusText: statusText,
                          isBusy: isBusy,
                          canAnalyze: canAnalyze,
                          errorText: errorText,
                          onAnalyze: analyzePdf,
                        ),
                        if (analysisData != null) ...[
                          const SizedBox(height: 14),
                          _PreviewPanel(
                            data: analysisData!,
                            isBusy: isBusy,
                            canExport: canExport,
                            onExport: exportNotes,
                          ),
                        ],
                        if (exportSuccess) ...[
                          const SizedBox(height: 14),
                          _ResultPanel(
                            nodesCreated: nodesCreated,
                            folderPath: folderPath ?? '',
                            filesCreated: filesCreated,
                            onOpenFolder: openFolder,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onReset});

  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: const BoxDecoration(
        color: Color(0xFF12151B),
        border: Border(bottom: BorderSide(color: Color(0xFF252B34))),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8).withAlpha(32),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.account_tree_outlined,
              color: Color(0xFF72B7FF),
              size: 21,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PDF to Obsidian Knowledge Nodes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFF4F7FB),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'PDF -> Vault -> Analyze -> Export',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Color(0xFF9AA6B5), fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Làm mới'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC8D2DE),
              side: const BorderSide(color: Color(0xFF384251)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.buttonIcon,
    required this.path,
    required this.status,
    required this.active,
    required this.valid,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String step;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData buttonIcon;
  final String? path;
  final String status;
  final bool active;
  final bool valid;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final borderColor = valid
        ? const Color(0xFF2FBF71)
        : active
        ? const Color(0xFF3D6E9F)
        : const Color(0xFF29313D);
    final textColor = active
        ? const Color(0xFFF4F7FB)
        : const Color(0xFF7D8896);

    return Container(
      constraints: const BoxConstraints(minHeight: 188),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF72B7FF).withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    color: Color(0xFF72B7FF),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF9AA6B5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                icon,
                color: active
                    ? const Color(0xFF72B7FF)
                    : const Color(0xFF596575),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: const Color(0xFF101319),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF252B34)),
            ),
            child: Text(
              path ?? 'Chưa chọn đường dẫn',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: path == null
                    ? const Color(0xFF626E7D)
                    : const Color(0xFFC8D2DE),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatusPill(
                label: status,
                color: valid
                    ? const Color(0xFF2FBF71)
                    : active
                    ? const Color(0xFFFFB454)
                    : const Color(0xFF7D8896),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onPressed,
                icon: Icon(buttonIcon, size: 17),
                label: Text(buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(126, 39),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PageRangePanel extends StatelessWidget {
  const _PageRangePanel({
    required this.startController,
    required this.stopController,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController startController;
  final TextEditingController stopController;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF29313D)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fields = [
            Expanded(
              child: _PageField(
                controller: startController,
                label: 'Trang bắt đầu',
                hint: 'Ví dụ: 1',
                enabled: enabled,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PageField(
                controller: stopController,
                label: 'Trang kết thúc',
                hint: 'Ví dụ: 8',
                enabled: enabled,
                onChanged: onChanged,
              ),
            ),
          ];

          final heading = Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB454).withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.menu_book_outlined,
                  size: 19,
                  color: Color(0xFFFFB454),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chọn số trang',
                      style: TextStyle(
                        color: Color(0xFFF4F7FB),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Để trống nếu muốn phân tích toàn bộ PDF.',
                      style: TextStyle(color: Color(0xFF9AA6B5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 14),
                _PageField(
                  controller: startController,
                  label: 'Trang bắt đầu',
                  hint: 'Ví dụ: 1',
                  enabled: enabled,
                  onChanged: onChanged,
                ),
                const SizedBox(height: 10),
                _PageField(
                  controller: stopController,
                  label: 'Trang kết thúc',
                  hint: 'Ví dụ: 8',
                  enabled: enabled,
                  onChanged: onChanged,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 3, child: heading),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: Row(children: fields)),
            ],
          );
        },
      ),
    );
  }
}

class _PageField extends StatelessWidget {
  const _PageField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => onChanged(),
      style: const TextStyle(color: Color(0xFFF4F7FB), fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF596575)),
        labelStyle: const TextStyle(color: Color(0xFF9AA6B5)),
        filled: true,
        fillColor: const Color(0xFF101319),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF252B34)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF72B7FF), width: 1.3),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF252B34)),
        ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.progress,
    required this.statusText,
    required this.isBusy,
    required this.canAnalyze,
    required this.errorText,
    required this.onAnalyze,
  });

  final double progress;
  final String statusText;
  final bool isBusy;
  final bool canAnalyze;
  final String? errorText;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF29313D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: errorText == null
                        ? const Color(0xFFC8D2DE)
                        : const Color(0xFFFFB4A8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: canAnalyze ? onAnalyze : null,
                icon: isBusy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(isBusy ? 'Đang xử lý' : 'Analyze'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2FBF71),
                  foregroundColor: const Color(0xFF07130D),
                  minimumSize: const Size(132, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFF252B34),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF72B7FF)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.data,
    required this.isBusy,
    required this.canExport,
    required this.onExport,
  });

  final Map<String, dynamic> data;
  final bool isBusy;
  final bool canExport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final metadata = _mapFrom(data['metadata']);
    final title = _previewText(
      data['paper_title'] ?? data['title'] ?? metadata['title'],
      'Chưa có tiêu đề',
    );
    final authors = _stringList(data['authors'] ?? metadata['authors']);
    final keywords = _stringList(data['keywords'] ?? metadata['keywords']);
    final abstract = _previewText(data['abstract'] ?? metadata['abstract']);
    final outputFolder = _previewText(data['output_folder'], 'Papers');
    final markdown = _previewText(
      data['markdown_preview'] ?? data['raw_markdown'],
    );
    final sections = _mapList(data['sections'])
        .map((item) {
          final sectionTitle = _previewText(item['title'], 'Section');
          final content = _compactText(_previewText(item['content']), 110);
          return content.isEmpty ? sectionTitle : '$sectionTitle - $content';
        })
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final references = _stringList(data['references']);
    final nodes = _mapList(data['nodes_to_create'])
        .map((item) {
          final nodeTitle = _previewText(
            item['title'] ?? item['name'] ?? item['file'],
            'Node',
          );
          final path = _previewText(item['path']);
          return path.isEmpty ? nodeTitle : '$nodeTitle - $path';
        })
        .where((item) => item.trim().isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF29313D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.article_outlined, color: Color(0xFF72B7FF)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Preview',
                  style: TextStyle(
                    color: Color(0xFFF4F7FB),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: canExport ? onExport : null,
                icon: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_outlined, size: 18),
                label: Text(isBusy ? 'Đang Export' : 'Export'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(118, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DetailBlock(label: 'Tiêu đề', value: title),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ChipBlock(label: 'Tác giả', values: authors),
              _ChipBlock(label: 'Từ khóa', values: keywords),
              _PathBlock(label: 'Output folder', value: outputFolder),
            ],
          ),
          if (abstract.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextPreviewBlock(label: 'Tóm tắt', value: abstract, maxLines: 5),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final left = Column(
                children: [
                  _PreviewList(title: 'Sections', items: sections),
                  const SizedBox(height: 10),
                  _PreviewList(title: 'References', items: references),
                  const SizedBox(height: 10),
                  _PreviewList(title: 'Nodes sẽ tạo', items: nodes),
                ],
              );
              final right = _MarkdownPreviewBox(markdown: markdown);

              if (constraints.maxWidth < 860) {
                return Column(
                  children: [left, const SizedBox(height: 10), right],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 12),
                  Expanded(child: right),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.nodesCreated,
    required this.folderPath,
    required this.filesCreated,
    required this.onOpenFolder,
  });

  final int nodesCreated;
  final String folderPath;
  final List<String> filesCreated;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF152018),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2FBF71).withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF2FBF71)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Export thành công',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFF4F7FB),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onOpenFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 17),
                label: const Text('Mở Folder'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD6DEE8),
                  side: const BorderSide(color: Color(0xFF5D8C6F)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailBlock(
            label: 'Số nodes đã tạo',
            value: nodesCreated.toString(),
          ),
          if (folderPath.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailBlock(label: 'Folder path', value: folderPath),
          ],
          if (filesCreated.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PreviewList(title: 'Files đã tạo', items: filesCreated),
          ],
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101319),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF252B34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7D8896),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value.isEmpty ? 'Chưa có dữ liệu' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD6DEE8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextPreviewBlock extends StatelessWidget {
  const _TextPreviewBlock({
    required this.label,
    required this.value,
    required this.maxLines,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101319),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF252B34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7D8896),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFC8D2DE), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _ChipBlock extends StatelessWidget {
  const _ChipBlock({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 360),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101319),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF252B34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7D8896),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (values.isEmpty)
            const Text(
              'Chưa có dữ liệu',
              style: TextStyle(color: Color(0xFF626E7D)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final value in values.take(6))
                  _StatusPill(
                    label: _compactText(value, 34),
                    color: const Color(0xFF72B7FF),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PathBlock extends StatelessWidget {
  const _PathBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 500),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101319),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF252B34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7D8896),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? 'Papers' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFC8D2DE),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewList extends StatelessWidget {
  const _PreviewList({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 118, maxHeight: 190),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101319),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF252B34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF7D8896),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Text(
                    'Chưa có dữ liệu',
                    style: TextStyle(color: Color(0xFF626E7D)),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              _compactText(item, 170),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFC8D2DE),
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownPreviewBox extends StatelessWidget {
  const _MarkdownPreviewBox({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 412,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF252B34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Markdown preview',
            style: TextStyle(
              color: Color(0xFF7D8896),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                markdown.isEmpty ? 'Chưa có Markdown preview' : markdown,
                style: const TextStyle(
                  color: Color(0xFFD6DEE8),
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        border: Border.all(color: color.withAlpha(110)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Map<String, dynamic> _mapFrom(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return {};
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is Iterable) {
    return value
        .whereType<Map>()
        .map((item) => item.map((key, val) => MapEntry(key.toString(), val)))
        .toList();
  }
  return [];
}

List<String> _stringList(Object? value) {
  if (value == null) {
    return [];
  }
  if (value is Iterable) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final text = value.toString().trim();
  if (text.isEmpty) {
    return [];
  }
  return text
      .split(RegExp(r'[\n;,]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String _previewText(Object? value, [String fallback = '']) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String _compactText(String value, int maxLength) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 3)}...';
}
