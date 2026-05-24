import 'dart:io';
import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';
import '../widgets/bottonbar.dart';
import '../widgets/uploadzone.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  File? selectedFile;
  double progress = 0;
  bool isLoading = false;
  bool saveToObsidian = true;
  String? rawMarkdown;
  String? paperTitle;
  List<String> authors = [];
  final TextEditingController startController = TextEditingController();
  final TextEditingController stopController = TextEditingController();

  @override
  void dispose() {
    startController.dispose();
    stopController.dispose();
    super.dispose();
  }

  Future<void> startConvert() async {
    if (selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF first.')),
      );
      return;
    }

    setState(() {
      isLoading = true;
      progress = 0;
      rawMarkdown = null;
      paperTitle = null;
      authors = [];
    });

    int? start;
    int? stop;

    if (startController.text.isNotEmpty) {
      start = int.tryParse(startController.text);
      if (start == null || start < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Start page must be a positive integer.'),
          ),
        );
        setState(() {
          isLoading = false;
        });
        return;
      }
    }

    if (stopController.text.isNotEmpty) {
      stop = int.tryParse(stopController.text);
      if (stop == null || stop < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stop page must be a positive integer.'),
          ),
        );
        setState(() {
          isLoading = false;
        });
        return;
      }
    }

    if (start != null && stop != null && stop < start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Stop page must be greater than or equal to start page.',
          ),
        ),
      );
      setState(() {
        isLoading = false;
      });
      return;
    }

    if (start != null && stop != null && (stop - start + 1) > 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Page range cannot exceed 8 pages. (1-8 pages allowed)',
          ),
        ),
      );
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      final response = await ApiService.convertFile(
        file: selectedFile!,
        start: start,
        stop: stop,
        saveToObsidian: saveToObsidian,
      );
      final data = response['data'] as Map<String, dynamic>?;
      final metadata = data?['metadata'] as Map<String, dynamic>?;

      setState(() {
        progress = 1;
        rawMarkdown = data?['raw_markdown'] as String?;
        paperTitle = data?['paper_title'] as String?;
        authors = ((metadata?['authors'] as List<dynamic>?) ?? [])
            .map((e) => e.toString())
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Converted "${paperTitle ?? 'Document'}" successfully.',
          ),
        ),
      );
    } catch (error) {
      String errorMsg = 'Conversion failed';
      final errorStr = error.toString().toLowerCase();

      if (errorStr.contains('failed to establish')) {
        errorMsg =
            'Cannot connect to API server. Make sure backend is running.';
      } else if (errorStr.contains('pdf')) {
        errorMsg = 'Invalid PDF file or corrupted.';
      } else if (errorStr.contains('timeout')) {
        errorMsg = 'Request timeout. File might be too large.';
      } else if (errorStr.contains('404')) {
        errorMsg = 'Backend API endpoint not found.';
      } else if (errorStr.contains('413')) {
        errorMsg = 'File size too large. Max 80MB allowed.';
      } else if (errorStr.contains('unsupported|socket')) {
        errorMsg = 'Network error. Check your connection.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), duration: const Duration(seconds: 4)),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const Sidebar(),

          Expanded(
            child: Column(
              children: [
                const TopBar(),

                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: startController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Start page',
                                      border: OutlineInputBorder(),
                                      hintText: '1',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: stopController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Stop page',
                                      border: OutlineInputBorder(),
                                      hintText: '5',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Switch(
                                  value: saveToObsidian,
                                  onChanged: (value) {
                                    setState(() {
                                      saveToObsidian = value;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Save to Obsidian',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: UploadZone(
                          onFileSelected: (file) {
                            setState(() {
                              selectedFile = file;
                              progress = 0;
                              rawMarkdown = null;
                              paperTitle = null;
                              authors = [];
                            });
                          },
                        ),
                      ),

                      if (rawMarkdown != null)
                        Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1B1B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF404752),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Conversion Result',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        selectedFile = null;
                                        rawMarkdown = null;
                                        paperTitle = null;
                                        authors = [];
                                        progress = 0;
                                        startController.clear();
                                        stopController.clear();
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.refresh,
                                      color: Color(0xFF0078D4),
                                      size: 20,
                                    ),
                                    label: const Text(
                                      'Choose Other',
                                      style: TextStyle(
                                        color: Color(0xFF0078D4),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (paperTitle != null)
                                Text(
                                  'Title: $paperTitle',
                                  style: const TextStyle(
                                    color: Color(0xFFC0C7D4),
                                  ),
                                ),
                              if (authors.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Authors: ${authors.join(', ')}',
                                  style: const TextStyle(
                                    color: Color(0xFFC0C7D4),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 260,
                                child: SingleChildScrollView(
                                  child: Text(
                                    rawMarkdown!,
                                    style: const TextStyle(
                                      color: Color(0xFFE3E8EF),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                BottomBar(
                  progress: progress,
                  isLoading: isLoading,
                  onConvert: startConvert,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
