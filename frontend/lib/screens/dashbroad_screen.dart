import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api_service.dart';
import '../theme/app_theme.dart';

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
  bool get canEditPageRange => vaultValid && !isBusy;
  bool get canAnalyze => selectedPdf != null && vaultValid && !isBusy;
  bool get canExport =>
      analysisData != null && selectedPdf != null && vaultValid && !isBusy;

  /// 0=PDF, 1=Vault, 2=Trang, 3=Analyze, 4=Export
  int get activeWorkflowStep {
    if (selectedPdf == null) {
      return 0;
    }
    if (!vaultValid) {
      return 1;
    }
    if (isBusy && analysisData == null) {
      return 3;
    }
    if (analysisData == null) {
      return 2;
    }
    if (!exportSuccess) {
      return 4;
    }
    return 4;
  }

  _WorkflowStepState workflowStepState(int index) {
    if (exportSuccess) {
      return _WorkflowStepState.completed;
    }
    if (index < activeWorkflowStep) {
      return _WorkflowStepState.completed;
    }
    if (index == activeWorkflowStep) {
      return _WorkflowStepState.active;
    }
    return _WorkflowStepState.pending;
  }

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
          ? 'Vault hợp lệ. Chọn số trang (tuỳ chọn) rồi bấm Analyze.'
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
      statusText = 'Đang tải PDF lên Hệ thống...';
      clearAnalysisAndResult();
    });

    try {
      startProgressTicker(target: 0.88, label: 'Hệ thống đang phân tích PDF...');
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
      startProgressTicker(target: 0.78, label: 'Hệ thống đang export nodes...');
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
        statusText = 'Export thành công.';
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
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              _Header(onReset: isBusy ? null : reset),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 26,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _WorkflowStrip(
                            stepStateAt: workflowStepState,
                          ),
                          const SizedBox(height: 20),
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
                          step: '3',
                          startController: startPageController,
                          stopController: stopPageController,
                          enabled: canEditPageRange,
                          locked: !canEditPageRange,
                          isActiveStep: activeWorkflowStep == 2,
                          lockMessage: selectedPdf == null
                              ? 'Hãy chọn PDF trước.'
                              : !vaultValid
                              ? 'Hãy chọn Vault hợp lệ để mở khóa nhập số trang.'
                              : 'Đang xử lý — tạm khóa nhập trang.',
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
      ),
    );
  }
}

class _WorkflowStrip extends StatelessWidget {
  const _WorkflowStrip({required this.stepStateAt});

  final _WorkflowStepState Function(int index) stepStateAt;

  static const _steps = ['PDF', 'Vault', 'Trang', 'Analyze', 'Export'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: AppDecorations.card(elevated: false),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: stepStateAt(i - 1) == _WorkflowStepState.completed
                        ? const LinearGradient(
                            colors: [AppColors.accentDeep, AppColors.accent],
                          )
                        : null,
                    color: stepStateAt(i - 1) == _WorkflowStepState.completed
                        ? null
                        : AppColors.border,
                  ),
                ),
              ),
            _WorkflowChip(
              index: i + 1,
              label: _steps[i],
              state: stepStateAt(i),
            ),
          ],
        ],
      ),
    );
  }
}

enum _WorkflowStepState { pending, active, completed }

class _WorkflowChip extends StatefulWidget {
  const _WorkflowChip({
    required this.index,
    required this.label,
    required this.state,
  });

  final int index;
  final String label;
  final _WorkflowStepState state;

  @override
  State<_WorkflowChip> createState() => _WorkflowChipState();
}

class _WorkflowChipState extends State<_WorkflowChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulse = Tween<double>(begin: 1, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _WorkflowChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.state == _WorkflowStepState.active) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.state == _WorkflowStepState.active;
    final isCompleted = widget.state == _WorkflowStepState.completed;

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isActive
            ? const LinearGradient(
                colors: [AppColors.primaryDeep, AppColors.primary],
              )
            : isCompleted
            ? const LinearGradient(
                colors: [AppColors.accentDeep, AppColors.accent],
              )
            : null,
        color: isActive || isCompleted ? null : AppColors.surfaceInset,
        border: Border.all(
          color: isActive
              ? AppColors.primary
              : isCompleted
              ? AppColors.accent
              : AppColors.border,
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.primary.withAlpha(90),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: isCompleted
          ? const Icon(Icons.check_rounded, size: 16, color: Color(0xFF07130D))
          : Text(
              '${widget.index}',
              style: GoogleFonts.plusJakartaSans(
                color: isActive ? Colors.white : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        isActive
            ? ScaleTransition(scale: _pulse, child: badge)
            : badge,
        const SizedBox(width: 8),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: GoogleFonts.plusJakartaSans(
            color: isActive
                ? AppColors.textPrimary
                : isCompleted
                ? AppColors.accent
                : AppColors.textMuted,
            fontSize: isActive ? 13.5 : 13,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          ),
          child: Text(widget.label),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onReset});

  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      decoration: BoxDecoration(
        color: AppColors.headerBg.withAlpha(235),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryDeep, AppColors.primary],
              ),
              borderRadius: BorderRadius.circular(AppRadii.md),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x404B6FE8),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.hub_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PDF TO OBSIDIAN',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Chuyển PDF thành nodes trong Obsidian Vault',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              'Làm mới',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
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
        ? AppColors.accent
        : active
        ? AppColors.primary.withAlpha(160)
        : AppColors.border;
    final textColor = active ? AppColors.textPrimary : AppColors.textMuted;
    final accent = valid
        ? AppColors.accent
        : active
        ? AppColors.primary
        : AppColors.textMuted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 196),
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(borderColor: borderColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: AppDecorations.iconBadge(accent),
                child: Text(
                  step,
                  style: GoogleFonts.plusJakartaSans(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
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
                      style: GoogleFonts.plusJakartaSans(
                        color: textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, color: accent, size: 22),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: AppDecorations.insetField(),
            child: Text(
              path ?? 'Chưa chọn đường dẫn',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: path == null
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
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
                    ? AppColors.accent
                    : active
                    ? AppColors.warning
                    : AppColors.textMuted,
              ),
              const Spacer(),
              GradientActionButton(
                label: buttonLabel,
                icon: buttonIcon,
                onPressed: onPressed,
                minWidth: 128,
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
    required this.step,
    required this.startController,
    required this.stopController,
    required this.enabled,
    required this.locked,
    required this.isActiveStep,
    required this.lockMessage,
    required this.onChanged,
  });

  final String step;
  final TextEditingController startController;
  final TextEditingController stopController;
  final bool enabled;
  final bool locked;
  final bool isActiveStep;
  final String lockMessage;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final borderColor = locked
        ? AppColors.border
        : isActiveStep
        ? AppColors.warning.withAlpha(200)
        : enabled
        ? AppColors.warning.withAlpha(120)
        : AppColors.border;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 280),
      opacity: locked ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppDecorations.card(borderColor: borderColor),
        child: Stack(
          children: [
            LayoutBuilder(
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
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: AppDecorations.iconBadge(
                  locked ? AppColors.textMuted : AppColors.warning,
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 19,
                  color: locked ? AppColors.textMuted : AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StepBadge(
                          step: step,
                          color: locked
                              ? AppColors.textMuted
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Chọn số trang',
                          style: GoogleFonts.plusJakartaSans(
                            color: locked
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locked
                          ? lockMessage
                          : 'Để trống nếu muốn phân tích toàn bộ PDF.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final fieldsBlock = IgnorePointer(
            ignoring: locked,
            child: Opacity(
              opacity: locked ? 0.7 : 1,
              child: constraints.maxWidth < 760
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                    )
                  : Row(children: fields),
            ),
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, fieldsBlock],
            );
          }

          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: heading),
                  const SizedBox(width: 18),
                  Expanded(flex: 4, child: fieldsBlock),
                ],
              ),
            ],
          );
              },
            ),
            if (locked)
              Positioned(
                right: 8,
                top: 8,
                child: _LockBadge(message: 'Đã khóa'),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.step, required this.color});

  final String step;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: AppDecorations.iconBadge(color),
      child: Text(
        step,
        style: GoogleFonts.plusJakartaSans(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceInset,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
      style: GoogleFonts.plusJakartaSans(
        color: AppColors.textPrimary,
        fontSize: 14,
      ),
      decoration: InputDecoration(labelText: label, hintText: hint),
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
    final pct = (progress.clamp(0.0, 1.0) * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: AppDecorations.iconBadge(AppColors.accent),
                child: const Icon(
                  Icons.auto_awesome_outlined,
                  size: 19,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: errorText == null
                        ? AppColors.textPrimary
                        : AppColors.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              GradientActionButton(
                label: isBusy ? 'Đang xử lý' : 'Analyze',
                icon: Icons.auto_awesome_outlined,
                onPressed: canAnalyze ? onAnalyze : null,
                busy: isBusy,
                variant: GradientButtonVariant.accent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: SizedBox(
                    height: 10,
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: AppColors.surfaceInset,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$pct%',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
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
    final outputFolder = _previewText(data['output_folder'], 'Thư mục Vault');
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
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: AppDecorations.iconBadge(AppColors.primary),
                child: const Icon(
                  Icons.article_outlined,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Preview',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              GradientActionButton(
                label: isBusy ? 'Đang Export' : 'Export',
                icon: Icons.save_alt_outlined,
                onPressed: canExport ? onExport : null,
                busy: isBusy,
                minWidth: 118,
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
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(
        borderColor: AppColors.accent.withAlpha(140),
      ).copyWith(
        color: const Color(0xFF121C18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: AppDecorations.iconBadge(AppColors.accent),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Export thành công',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onOpenFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 17),
                label: Text(
                  'Mở Folder',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.accent.withAlpha(120)),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: AppDecorations.insetField(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? 'Chưa có dữ liệu' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textPrimary,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: AppDecorations.insetField(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
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
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.insetField(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          if (values.isEmpty)
            Text(
              'Chưa có dữ liệu',
              style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final value in values.take(6))
                  _StatusPill(
                    label: _compactText(value, 34),
                    color: AppColors.primary,
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
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.insetField(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? 'Papers' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textPrimary,
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
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.insetField(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Text(
                    'Chưa có dữ liệu',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                    ),
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
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.3,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceInset,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Markdown preview',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                markdown.isEmpty ? 'Chưa có Markdown preview' : markdown,
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withAlpha(36), color.withAlpha(14)],
        ),
        border: Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.plusJakartaSans(
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
