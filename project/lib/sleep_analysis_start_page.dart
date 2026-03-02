// lib/sleep_analysis_start_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'modifier/sleep_fx.dart'; // 星空背景（若暂无，可临时注释此行）
import 'snore_detection_page.dart'; // 监测页
import 'snore_segments_page.dart'; // 片段列表页

class SleepAnalysisStartPage extends StatefulWidget {
  const SleepAnalysisStartPage({super.key});
  @override
  State<SleepAnalysisStartPage> createState() => _SleepAnalysisStartPageState();
}

class _SleepAnalysisStartPageState extends State<SleepAnalysisStartPage>
    with TickerProviderStateMixin {
  // Native channels（与你现有保持一致）
  static const _ch = MethodChannel('snore_detection');
  static const _events = EventChannel('snore_volume_stream');

  StreamSubscription? _sub;

  bool _on = false;
  bool _micPaused = false;
  bool _askingPerm = false;

  int _segments = 0;
  double _db = 0;
  double _snoreProb = 0;
  bool _isSnoring = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _listenNative();
    _queryStatus();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /* ---------- Permission ---------- */

  Future<bool> _ensureMicPermission() async {
    if (_askingPerm) return false;
    _askingPerm = true;
    try {
      var status = await Permission.microphone.status;

      if (status.isGranted) return true;

      // 首次或普通拒绝 -> 发起请求
      if (status.isDenied || status.isRestricted || status.isLimited) {
        status = await Permission.microphone.request();
        if (mounted && status.isGranted) return true;
      }

      // 永久拒绝 -> 引导去设置
      if (status.isPermanentlyDenied) {
        if (!mounted) return false;
        final go = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Microphone permission'),
            content: const Text(
              'Microphone access is required to detect snoring.\n'
              'Please enable it in system Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        if (go == true) {
          await openAppSettings();
          // 回来后再查一次
          final ok = await Permission.microphone.status.isGranted;
          return ok;
        }
      }

      _snack('Microphone permission denied.');
      return false;
    } finally {
      _askingPerm = false;
    }
  }

  /* ---------- Native events ---------- */

  void _listenNative() {
    _sub = _events.receiveBroadcastStream().listen((event) {
      if (!mounted) return;
      if (event is Map) {
        final Map m = event;
        setState(() {
          if (m['started'] == true) _on = true;
          if (m['stopped'] == true) _on = false;
          if (m['micPaused'] == true) _micPaused = true;
          if (m['micResumed'] == true) _micPaused = false;

          if (m['db'] != null) _db = (m['db'] as num).toDouble();
          if (m['snoreProb'] != null)
            _snoreProb = (m['snoreProb'] as num).toDouble();
          if (m['isSnoring'] != null) _isSnoring = m['isSnoring'] == true;
          if (m['segmentSaved'] == true) _segments += 1;
        });
      }
    }, onError: (_) {});
  }

  Future<void> _queryStatus() async {
    try {
      final bool running = await _ch.invokeMethod('status');
      if (mounted) setState(() => _on = running);
    } catch (_) {}
  }

  /* ---------- Actions ---------- */

  Future<void> _startAndGo() async {
    // 先拿权限
    final ok = await _ensureMicPermission();
    if (!ok) {
      _snack('Microphone permission is required to start detection.');
      return;
    } //加了反馈

    try {
      await _ch.invokeMethod('start');
      if (!mounted) return;
      setState(() => _on = true);
      // 进入监测页
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SnoreDetectionPage()));
    } catch (e) {
      _snack('Start failed: $e');
    }
  }

  Future<void> _pauseMic() async {
    try {
      await _ch.invokeMethod('pauseMic');
      if (mounted) setState(() => _micPaused = true);
    } catch (e) {
      _snack('Pause mic failed: $e');
    }
  }

  Future<void> _resumeMic() async {
    try {
      await _ch.invokeMethod('resumeMic');
      if (mounted) setState(() => _micPaused = false);
    } catch (e) {
      _snack('Resume mic failed: $e');
    }
  }

  void _openSegments() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SnoreSegmentsPage()));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /* ---------- UI ---------- */

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0C1220),
      appBar: AppBar(
        title: const Text('Sleep Analysis'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // 星空背景（没有 SleepStarfield 时可注释下一行）
          const Positioned.fill(child: SleepStarfield()),

          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Column(
                children: [
                  _StatusCard(
                    on: _on,
                    segments: _segments,
                    db: _db,
                    prob: _snoreProb,
                  ),
                  const SizedBox(height: 20),

                  _MoonPulse(
                    db: _db,
                    prob: _snoreProb,
                    isSnoring: _isSnoring,
                    pulse: _pulse,
                  ),

                  const SizedBox(height: 20),

                  // 控制区：三按钮（Expanded 防溢出）
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: _micPaused ? Icons.mic_off : Icons.mic,
                          label: _micPaused ? 'Resume Mic' : 'Pause Mic',
                          onTap: _on
                              ? (_micPaused ? _resumeMic : _pauseMic)
                              : null,
                          color: cs.secondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Open Detector',
                          onTap: _startAndGo,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.library_music_rounded,
                          label: 'Clips',
                          onTap: _openSegments,
                          color: const Color(0xFF596780),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  _TipsCard(on: _on),

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* =================== Pieces =================== */

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.on,
    required this.segments,
    required this.db,
    required this.prob,
  });
  final bool on;
  final int segments;
  final double db;
  final double prob;

  @override
  Widget build(BuildContext context) {
    final title = on ? 'Detector is running' : 'Detector is idle';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.12)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hearing_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _OnBadge(on: on),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Detected: $segments segments    dB: ${db.toStringAsFixed(0)}    p: ${(prob * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _OnBadge extends StatelessWidget {
  const _OnBadge({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) {
    final color = on ? Colors.green : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            on ? Icons.power_settings_new : Icons.power_off,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            on ? 'ON' : 'OFF',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: Colors.white,
        backgroundColor: enabled ? color : color.withOpacity(.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
    );
  }
}

class _MoonPulse extends StatelessWidget {
  const _MoonPulse({
    required this.db,
    required this.prob,
    required this.isSnoring,
    required this.pulse,
  });

  final double db;
  final double prob;
  final bool isSnoring;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    final glow = isSnoring ? Colors.deepPurpleAccent : Colors.white;
    return SizedBox(
      height: 240,
      child: Center(
        child: AnimatedBuilder(
          animation: pulse,
          builder: (_, __) {
            final t = pulse.value;
            final spread = 22 + 10 * (isSnoring ? 1 : 0);
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 170 + spread * t,
                  height: 170 + spread * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: glow.withOpacity((1 - t) * .08),
                    border: Border.all(color: glow.withOpacity(.25), width: 2),
                  ),
                ),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity(.10),
                        Colors.white.withOpacity(.02),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(color: glow.withOpacity(.25), blurRadius: 30),
                    ],
                  ),
                  child: const Icon(
                    Icons.nights_stay_rounded,
                    color: Colors.white,
                    size: 46,
                  ),
                ),
                Positioned(
                  bottom: 10,
                  child: Opacity(
                    opacity: .9,
                    child: Row(
                      children: [
                        _chip('${db.toStringAsFixed(0)} dB'),
                        const SizedBox(width: 8),
                        _chip('prob ${(prob * 100).toStringAsFixed(0)}%'),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Text(
        on
            ? 'Detector is running. You can turn off the screen; Foreground Service keeps recording.\n'
                  '(Recommend ignoring battery optimizations.)'
            : 'Tap Open Detector to begin detection. The detector page gives you full control.',
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }
}

class _CautionBar extends StatelessWidget {
  const _CautionBar();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CautionPainter(),
          size: const Size(double.infinity, double.infinity),
        ),
      ),
    );
  }
}

class _CautionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = const Radius.circular(8);
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, radius);

    // 先裁剪到圆角矩形 —— 关键修复！
    canvas.save();
    canvas.clipRRect(rrect);

    // 背景（半透明深色）
    final bg = Paint()..color = const Color(0xFF1E1E1E).withOpacity(.55);
    canvas.drawRect(rect, bg);

    // 画黄黑斜纹
    final yel = Paint()..color = const Color(0xFFFFD740);
    final blk = Paint()..color = const Color(0xFF212121);
    const band = 8.0; // 条纹宽度
    final h = size.height;

    // 斜纹按对角线方向平移，避免在不同尺寸下“断裂”
    for (double x = -h; x < size.width + h; x += band * 2) {
      final pathY = Path()
        ..moveTo(x, 0)
        ..lineTo(x + band, 0)
        ..lineTo(x + band - h, h)
        ..lineTo(x - h, h)
        ..close();
      canvas.drawPath(pathY, yel);

      final pathB = Path()
        ..moveTo(x + band, 0)
        ..lineTo(x + band * 2, 0)
        ..lineTo(x + band * 2 - h, h)
        ..lineTo(x + band - h, h)
        ..close();
      canvas.drawPath(pathB, blk);
    }

    // 可选：内边框/内阴影，增加质感
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFFFFF).withOpacity(.10),
    );

    canvas.restore(); // 取消裁剪
  }

  @override
  bool shouldRepaint(covariant _CautionPainter oldDelegate) => false;
}
