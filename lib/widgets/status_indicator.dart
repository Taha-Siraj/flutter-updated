import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class StatusIndicator extends StatelessWidget {
  final bool isActive;
  final String label;
  final double size;

  const StatusIndicator({
    super.key,
    required this.isActive,
    this.label = '',
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: size,
          width: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            boxShadow: [
              BoxShadow(
                color: isActive 
                    ? const Color(0xFF10B981).withOpacity(0.6)
                    : const Color(0xFFEF4444).withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
        )
            .animate(onPlay: (controller) => controller.repeat(reverse: true))
            .scale(
              duration: 1000.ms,
              begin: const Offset(1.0, 1.0),
              end: const Offset(1.2, 1.2),
            ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: size + 2,
              fontWeight: FontWeight.w600,
              color: isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            ),
          ),
        ],
      ],
    );
  }
}

