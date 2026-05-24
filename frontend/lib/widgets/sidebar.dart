import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: const Color(0xE60E0E0E),
        border: Border(right: BorderSide(color: const Color(0xFF404752))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            // Logo Section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "ObsiMark",
                    style: TextStyle(
                      color: Color(0xFFE5E2E1),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Pro Edition",
                    style: TextStyle(color: Color(0xFFC0C7D4), fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Navigation Items
            _buildNavItem(icon: Icons.home, title: "Home", active: true),

            _buildNavItem(icon: Icons.history, title: "Recent"),

            _buildNavItem(icon: Icons.settings, title: "Settings"),

            const Spacer(),

            // Upgrade Button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0078D4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {},
                  child: const Text(
                    "Upgrade to Pro",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String title,
    bool active = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: active ? const Color(0xFF41474E) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            leading: Icon(
              icon,
              color: active ? Colors.white : const Color(0xFFC0C7D4),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFFC0C7D4),
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {},
          ),
        ),
      ),
    );
  }
}
