import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class UploadZone extends StatefulWidget {
  const UploadZone({super.key, this.onFileSelected});

  final ValueChanged<File>? onFileSelected;

  @override
  State<UploadZone> createState() => _UploadZoneState();
}

class _UploadZoneState extends State<UploadZone> {
  File? selectedFile;
  bool isLoading = false;

  Future<File?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowedExtensions: ['pdf'],
      allowMultiple: false,
      dialogTitle: 'Select PDF',
      lockParentWindow: true,
      type: FileType.custom,
    );

    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  Future<void> handleUpload() async {
    if (isLoading) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    final file = await pickFile();
    if (!mounted) {
      return;
    }

    if (file == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    if (!file.path.toLowerCase().endsWith('.pdf')) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF file.')),
      );
      return;
    }

    setState(() {
      selectedFile = file;
      isLoading = false;
    });

    widget.onFileSelected?.call(file);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = constraints.maxHeight.clamp(220.0, 300.0).toDouble();

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: isLoading ? null : handleUpload,
              child: Container(
                height: cardHeight,
                margin: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1B1B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF404752), width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: Color(0x1A0078D4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.upload_file,
                        size: 34,
                        color: Color(0xFF0078D4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Upload Your PDF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select a PDF file to analyze and export.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFC0C7D4), fontSize: 14),
                    ),
                    if (selectedFile != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Selected: ${selectedFile!.path.split(Platform.pathSeparator).last}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.greenAccent),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0078D4),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: isLoading ? null : handleUpload,
                        child: isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                selectedFile == null
                                    ? 'Select PDF'
                                    : 'Choose Other',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
