import 'package:flutter/material.dart';

/// Warning banner displayed when chaos engineering is active.
class ChaosBanner extends StatelessWidget {
  final bool visible;
  final VoidCallback? onTap;

  const ChaosBanner({
    super.key,
    required this.visible,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange[100],
          border: Border(
            bottom: BorderSide(color: Colors.orange[300]!),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[800], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Chaos engineering is active',
                style: TextStyle(
                  color: Colors.orange[900],
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.orange[700], size: 20),
          ],
        ),
      ),
    );
  }
}
