import 'package:flutter/material.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.progress,
    required this.isLoading,
    required this.onConvert,
  });

  final double progress;
  final bool isLoading;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        border: Border(
          top: BorderSide(
            color: Color(0xFF404752),
          ),
        ),
      ),
      child: Row(
        children: [
          // Progress Section
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: const Color(0xFF404752),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF0078D4),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                Text(
                  "${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%",
                  style: const TextStyle(
                    color: Color(0xFFC0C7D4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // Clear Queue Button
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.delete_sweep),
            label: const Text("Clear Queue"),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC0C7D4),
            ),
          ),

          const SizedBox(width: 16),

          // Convert Button
          ElevatedButton.icon(
            onPressed: isLoading ? null : onConvert,
            icon: const Icon(Icons.play_circle),
            label: Text(isLoading ? "Converting..." : "Convert"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0078D4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}