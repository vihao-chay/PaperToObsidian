import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

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
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowedExtensions: ['pdf'],
      type: FileType.custom,
    );

    if (result != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  Future<void> handleUpload() async {
    setState(() {
      isLoading = true;
    });

    final file = await pickFile();

    if (file == null) {
      setState(() {
        isLoading = false;
      });
      print("No file selected");
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
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B1B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF404752), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF0078D4).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.upload_file,
              size: 50,
              color: Color(0xFF0078D4),
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            "Upload Your PDF",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          const SizedBox(
            width: 450,
            child: Text(
              "Support for single or batch processing. Your files are encrypted and processed locally for maximum security.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFC0C7D4), fontSize: 15),
            ),
          ),

          const SizedBox(height: 20),

          // 👉 hiển thị file đã chọn
          if (selectedFile != null)
            Text(
              "Selected: ${selectedFile!.path.split('/').last}",
              style: const TextStyle(color: Colors.greenAccent),
            ),

          const SizedBox(height: 20),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0078D4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
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
                    selectedFile == null ? "Select PDF" : "Choose Other",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
