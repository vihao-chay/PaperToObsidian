import 'package:flutter/material.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xE6131313),
        border: const Border(bottom: BorderSide(color: Color(0xFF404752))),
      ),
      child: Row(
        children: [
          // Search Box
          Expanded(
            child: Container(
              height: 45,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: "Search tools or files...",
                  hintStyle: TextStyle(color: Color(0xFFC0C7D4)),
                  prefixIcon: Icon(Icons.search, color: Color(0xFFC0C7D4)),
                ),
              ),
            ),
          ),

          const SizedBox(width: 20),

          // Action Buttons
          _iconButton(Icons.help_outline),
          const SizedBox(width: 10),
          _iconButton(Icons.notifications_none),

          const SizedBox(width: 16),

          // Avatar
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFF353535),
            child: Icon(Icons.person, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        onPressed: () {},
        icon: Icon(icon),
        color: const Color(0xFFC0C7D4),
      ),
    );
  }
}
