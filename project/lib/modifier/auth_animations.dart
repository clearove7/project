// lib/auth_animations.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// ===============================================================
/// =============== 背景（柔和渐变 + 玻璃卡片壳） ====================
/// ===============================================================
class FancyAuthBackground extends StatelessWidget {
  final Widget child;
  final bool showOrbs; // 浮动霓虹球开关
  final EdgeInsetsGeometry padding;

  const FancyAuthBackground({
    super.key,
    required this.child,
    this.showOrbs = true,
    this.padding = const EdgeInsets.fromLTRB(18, 40, 18, 18),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        // 渐变背景
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withOpacity(.08),
                cs.secondary.withOpacity(.08),
                cs.tertiary.withOpacity(.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        if (showOrbs) const _FloatingOrbs(),
        // 内容卡片
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: padding,
              child: _GlassCard(child: child),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: cs.surface.withOpacity(.78),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outline.withOpacity(.12)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(.08),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// ===============================================================
/// =================== 背景霓虹光球（可选） =======================
/// ===============================================================
class _FloatingOrbs extends StatefulWidget {
  const _FloatingOrbs();
  @override
  State<_FloatingOrbs> createState() => _FloatingOrbsState();
}

class _FloatingOrbsState extends State<_FloatingOrbs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return CustomPaint(
            painter: _OrbPainter(t, [
              cs.primary.withOpacity(.18),
              cs.secondary.withOpacity(.16),
              cs.tertiary.withOpacity(.14),
            ]),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  _OrbPainter(this.t, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide * .18;
    final centers = [
      Offset(
        size.width * (.20 + .02 * math.sin(t * math.pi * 2)),
        size.height * (.28 + .03 * math.cos(t * 2)),
      ),
      Offset(
        size.width * (.82 + .02 * math.cos(t * 2.1)),
        size.height * (.20 + .02 * math.sin(t * 1.6)),
      ),
      Offset(
        size.width * (.72 + .01 * math.sin(t * 1.7)),
        size.height * (.82 + .02 * math.cos(t * 1.4)),
      ),
    ];
    for (int i = 0; i < centers.length; i++) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [colors[i], Colors.transparent],
        ).createShader(Rect.fromCircle(center: centers[i], radius: radius));
      canvas.drawCircle(centers[i], radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) => true;
}

/// ===============================================================
/// ===================== 入场动画组件 ============================
/// ===============================================================

/// 淡入 + 轻微上浮
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final Duration duration;
  final Offset beginOffset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.duration = const Duration(milliseconds: 420),
    this.beginOffset = const Offset(0, .06),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: widget.beginOffset,
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_c);

  @override
  void initState() {
    super.initState();
    if (widget.delayMs <= 0) {
      _c.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

/// 轻微缩放进入
class ScaleIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final Duration duration;
  final double beginScale;

  const ScaleIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.duration = const Duration(milliseconds: 420),
    this.beginScale = .96,
  });

  @override
  State<ScaleIn> createState() => _ScaleInState();
}

class _ScaleInState extends State<ScaleIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: widget.beginScale,
    end: 1.0,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_c);

  @override
  void initState() {
    super.initState();
    if (widget.delayMs <= 0) {
      _c.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
    child: widget.child,
  );
} // <<< 这一行是上一版漏掉的“收口”，务必存在！

/// ===============================================================
/// ===================== 炫酷增强组件 ============================
/// ===============================================================

/// 发光标题（霓虹 + 细描边）
class GlowTitle extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final List<Color>? glowColors;
  final double blur;
  final double strokeWidth;

  const GlowTitle(
    this.text, {
    super.key,
    this.style,
    this.glowColors,
    this.blur = 16,
    this.strokeWidth = 1.4,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors =
        glowColors ??
        [cs.primary.withOpacity(.9), cs.secondary.withOpacity(.9)];

    // 发光层（外发光 + 渐变填充）
    final glow = Stack(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: (style ?? Theme.of(context).textTheme.headlineSmall)!.copyWith(
            foreground: Paint()
              ..color = colors.first
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
          ),
        ),
        ShaderMask(
          shaderCallback: (r) => LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(r),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: (style ?? Theme.of(context).textTheme.headlineSmall)!
                .copyWith(color: Colors.white),
          ),
        ),
      ],
    );

    // 细描边
    final stroke = Text(
      text,
      textAlign: TextAlign.center,
      style: (style ?? Theme.of(context).textTheme.headlineSmall)!.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = Colors.white.withOpacity(.55),
      ),
    );

    return Stack(alignment: Alignment.center, children: [glow, stroke]);
  }
}

/// 呼吸发光按钮（主操作）
class BreathingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Duration period;
  final double glowSpread;
  final double glowBlur;

  const BreathingButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.period = const Duration(milliseconds: 1600),
    this.glowSpread = 6,
    this.glowBlur = 18,
  });

  @override
  State<BreathingButton> createState() => _BreathingButtonState();
}

class _BreathingButtonState extends State<BreathingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat(reverse: true);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _t,
      builder: (_, __) {
        final k = _t.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withOpacity(.45 * k),
                blurRadius: widget.glowBlur + 10 * k, // ← 修正
                spreadRadius: widget.glowSpread * k, // ← 修正
              ),
            ],
          ),
          child: FilledButton(
            onPressed: widget.onPressed,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// 渐变描边 + 玻璃内填色按钮（副操作）
class GradientOutlineButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final List<Color>? colors;
  final double borderWidth;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GradientOutlineButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.colors,
    this.borderWidth = 1.6,
    this.padding = const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gradient = LinearGradient(
      colors: colors ?? [cs.primary, cs.secondary],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: Colors.transparent, width: borderWidth),
        ),
        gradient: gradient,
      ),
      child: Padding(
        padding: EdgeInsets.all(borderWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius - 2),
            color: cs.surface.withOpacity(.75),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(radius - 2),
              child: Padding(
                padding: padding,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
