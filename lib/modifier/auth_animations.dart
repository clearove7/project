import 'package:flutter/material.dart';

class FancyAuthBackground extends StatelessWidget {
  const FancyAuthBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      );
}

class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0});
  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) => child;
}

class ScaleIn extends StatelessWidget {
  const ScaleIn({super.key, required this.child, this.delayMs = 0});
  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) => child;
}

class GlowTitle extends StatelessWidget {
  const GlowTitle(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(text, textAlign: TextAlign.center, style: style);
}

class BreathingButton extends StatelessWidget {
  const BreathingButton({super.key, required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onPressed, child: child);
}

class GradientOutlineButton extends StatelessWidget {
  const GradientOutlineButton({super.key, required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => OutlinedButton(onPressed: onPressed, child: child);
}
