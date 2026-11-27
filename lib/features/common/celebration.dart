import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:material_ui/material_ui.dart';

/// Confetti that falls over [child] when [burst] or [bigBurst] is called.
class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({super.key, required this.child});

  final Widget child;

  static CelebrationOverlayState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<CelebrationOverlayState>();

  @override
  State<CelebrationOverlay> createState() => CelebrationOverlayState();
}

class CelebrationOverlayState extends State<CelebrationOverlay> {
  final _small = ConfettiController(
    duration: const Duration(milliseconds: 350),
  );
  final _big = ConfettiController(duration: const Duration(seconds: 2));

  /// A short burst for finishing one task.
  void burst() => _small.play();

  /// A big shower for clearing the whole day.
  void bigBurst() => _big.play();

  @override
  void dispose() {
    _small.dispose();
    _big.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      const Color(0xFFF59E0B),
      const Color(0xFF16A34A),
      const Color(0xFFEC4899),
    ];
    return Stack(
      children: [
        widget.child,
        // Confetti never blocks taps.
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _small,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 18,
              emissionFrequency: 0.6,
              maxBlastForce: 28,
              minBlastForce: 10,
              gravity: 0.35,
              colors: colors,
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _big,
              blastDirection: math.pi / 2,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 30,
              emissionFrequency: 0.08,
              maxBlastForce: 35,
              minBlastForce: 12,
              gravity: 0.2,
              colors: colors,
            ),
          ),
        ),
      ],
    );
  }
}
