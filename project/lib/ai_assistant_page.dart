// lib/ai_assistant_page.dart
//
// Requires:
//   image_picker: ^1.0.7
// Android permissions (if you don't have them yet):
// <uses-permission android:name="android.permission.CAMERA"/>
// <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
// <!-- for <= Android 12 -->
// <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
//
// Native side: handle 'askAi' on MethodChannel('com.example.health_app/ai')
// Expected payload:
// {
//   prompt: String,
//   rangeDays: int, // 7/30/90/365
//   attachments: [{name:String, mime:String, bytesBase64:String}, ...]
// }

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

const MethodChannel _aiCh = MethodChannel('com.example.health_app/ai');

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({
    super.key,
    this.initialPrompt,
    this.initialRangeDays = 7,
    this.initialImagePng,
    this.autoSendInitial = false,
  });

  final String? initialPrompt;
  final int initialRangeDays; // 7/30/90/365
  final Uint8List? initialImagePng;
  final bool autoSendInitial;

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage>
    with TickerProviderStateMixin {
  // UI state
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _showBg = true;
  bool _usingData = true;
  bool _sending = false;

  // range chips
  bool _rangeExpanded = true;
  int _rangeDays = 7;
  final List<int> _ranges = const [7, 30, 90, 365];

  // messages
  final List<_Msg> _messages = <_Msg>[
    _Msg.ai(
      "Hi! I'm your AI Assistant.\n"
      "Ask me about your blood pressure, weight/BMI, snoring, sleep — I can "
      "analyze your data over the selected range and give practical suggestions.",
    ),
  ];

  // attachments (pending to send)
  final List<_Attachment> _pending = <_Attachment>[];

  @override
  void initState() {
    super.initState();
    _rangeDays = widget.initialRangeDays;
    if (widget.initialImagePng != null) {
      _pending.add(
        _Attachment.memory(
          name: 'chart.png',
          bytes: widget.initialImagePng!,
          mime: 'image/png',
        ),
      );
    }
    if (widget.initialPrompt != null &&
        widget.initialPrompt!.trim().isNotEmpty) {
      _input.text = widget.initialPrompt!;
      if (widget.autoSendInitial) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _send());
      }
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /* ----------------------------- Image pick ----------------------------- */

  Future<void> _pickImage(ImageSource src) async {
    final picker = ImagePicker();
    final XFile? x = await picker.pickImage(
      source: src,
      imageQuality: 92,
      maxWidth: 2200,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _pending.add(
        _Attachment.memory(
          name: x.name,
          bytes: bytes,
          mime: _guessMime(x.path) ?? 'image/jpeg',
        ),
      );
    });
  }

  Future<void> _showPickSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Row(
            children: [
              Expanded(
                child: _bigAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _bigAction(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: cs.primary),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /* -------------------------------- Send -------------------------------- */

  Future<void> _send() async {
    if (_sending) return;

    final text = _input.text.trim(); // ← 绑定到 TextField 的 controller
    final hasAnything = text.isNotEmpty || _pending.isNotEmpty;
    if (!hasAnything) return;

    // add user message
    final userMsg = _Msg.user(text, atts: List.of(_pending));
    setState(() {
      _messages.add(userMsg);
      _input.clear();
      _sending = true;
      _pending.clear();
    });
    _scrollToEndSoon();

    // build final prompt with context
    final sb = StringBuffer();
    if (_usingData) {
      sb.writeln('SYSTEM_CONTEXT:');
      sb.writeln(
        '- Use the user’s health data for the selected range ($_rangeDays d). '
        'Be concise and practical; if risks detected, advise clinician contact.',
      );
      sb.writeln();
    }
    if (text.isNotEmpty) {
      sb.writeln('USER_MESSAGE:');
      sb.writeln(text);
    }

    // attachments payload
    final attPayload = <Map<String, dynamic>>[];
    for (final a in userMsg.atts) {
      final bytes = a.bytes ?? Uint8List(0);
      attPayload.add({
        'name': a.name,
        'mime': a.mime ?? 'application/octet-stream',
        'bytesBase64': base64Encode(bytes),
      });
    }

    // show thinking bubble
    setState(() {
      _messages.add(_Msg.ai('__thinking__'));
    });

    try {
      final res = await _aiCh.invokeMethod<String>('askAi', {
        'prompt': sb.toString(),
        'rangeDays': _rangeDays,
        'attachments': attPayload,
      });

      // replace thinking with real reply
      final idx = _messages.lastIndexWhere((m) => m.text == '__thinking__');
      if (idx != -1) _messages.removeAt(idx);

      setState(() {
        _messages.add(
          _Msg.ai(
            (res != null && res.trim().isNotEmpty)
                ? res.trim()
                : '(no response)',
          ),
        );
      });
    } catch (e) {
      final idx = _messages.lastIndexWhere((m) => m.text == '__thinking__');
      if (idx != -1) _messages.removeAt(idx);
      setState(() {
        _messages.add(_Msg.ai('Sorry, I ran into an error: $e'));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEndSoon();
    }
  }

  void _scrollToEndSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 240,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /* --------------------------------- UI --------------------------------- */

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          title: const Text('AI Assistant'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            IconButton(
              tooltip: _usingData ? 'Using your data' : 'Use my data',
              onPressed: () => setState(() => _usingData = !_usingData),
              icon: Icon(
                Icons.hub_outlined,
                color: _usingData ? const Color(0xFF27E1D7) : Colors.white70,
              ),
            ),
            IconButton(
              tooltip: _showBg ? 'Hide background' : 'Show background',
              onPressed: () => setState(() => _showBg = !_showBg),
              icon: Icon(
                Icons.auto_awesome_rounded,
                color: _showBg ? const Color(0xFF27E1D7) : Colors.white70,
              ),
            ),
            IconButton(
              tooltip: 'Clear chat',
              onPressed: () {
                setState(() {
                  _messages
                    ..clear()
                    ..add(
                      _Msg.ai(
                        "Hi! I'm your AI Assistant.\n"
                        "Ask me about your blood pressure, weight/BMI, snoring, sleep — I can "
                        "analyze your data over the selected range and give practical suggestions.",
                      ),
                    );
                });
              },
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_showBg) const Positioned.fill(child: _Starfield()),
            SafeArea(
              child: Column(
                children: [
                  _rangeHeader(cs),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        if (m.text == '__thinking__') {
                          return const _ThinkingBrain();
                        }
                        return _Bubble(
                          msg: m,
                          onCopy: () {
                            Clipboard.setData(ClipboardData(text: m.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied')),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (_pending.isNotEmpty) _pendingBar(),
                  _inputBar(cs), // ← 已修复：TextField 绑定 controller
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rangeHeader(ColorScheme cs) {
    final label = _rangeDays == 7
        ? '7d'
        : _rangeDays == 30
        ? '30d'
        : _rangeDays == 90
        ? '90d'
        : '365d';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _rangeExpanded = !_rangeExpanded),
            child: Row(
              children: [
                const Icon(Icons.show_chart_rounded, color: Color(0xFF27E1D7)),
                const SizedBox(width: 8),
                const Text(
                  'Range',
                  style: TextStyle(
                    color: Color(0xFF27E1D7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _rangeExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  color: const Color(0xFF27E1D7),
                ),
                if (!_rangeExpanded) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1A27E1D7),
                      border: Border.all(color: const Color(0x3327E1D7)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
          AnimatedCrossFade(
            crossFadeState: _rangeExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 240),
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 10,
                children: _ranges
                    .map(
                      (d) => _chip(
                        selected: _rangeDays == d,
                        label: d == 365 ? '365d' : '${d}d',
                        onTap: () => setState(() => _rangeDays = d),
                      ),
                    )
                    .toList(),
              ),
            ),
            secondChild: const SizedBox(height: 4),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF5B5FEF) : const Color(0xFF1B2536),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x8027E1D7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pending.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final a = _pending[i];
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    a.bytes ?? Uint8List(0),
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: InkWell(
                    onTap: () => setState(() => _pending.removeAt(i)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
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

  Widget _inputBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          // image button
          InkWell(
            onTap: _showPickSheet,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0x1A27E1D7),
                border: Border.all(color: const Color(0x3327E1D7)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.image_outlined, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          // input (FIX: 绑定 controller，不要 const)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(.70),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _input, // ← 关键修复
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(), // ← 回车可发送
                decoration: const InputDecoration(
                  hintText: 'Ask anything…',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // send
          ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(_sending ? 'Sending' : 'Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B5FEF),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/* ================================ Bubble ================================= */

enum _Role { user, ai }

class _Msg {
  _Msg(this.role, this.text, {List<_Attachment>? atts})
    : atts = atts ?? const [];
  _Msg.user(this.text, {List<_Attachment>? atts})
    : role = _Role.user,
      atts = atts ?? const [];
  _Msg.ai(this.text, {List<_Attachment>? atts})
    : role = _Role.ai,
      atts = atts ?? const [];

  final _Role role;
  final String text;
  final List<_Attachment> atts;
}

class _Attachment {
  _Attachment({required this.name, this.bytes, this.mime});
  _Attachment.memory({required this.name, required this.bytes, this.mime});

  final String name;
  final Uint8List? bytes;
  final String? mime;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.onCopy});
  final _Msg msg;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = msg.role == _Role.user;

    final bg = isUser
        ? const Color(0xFF3C2E87) // purple for user
        : cs.surfaceContainerHigh.withOpacity(.72);
    const fg = Colors.white;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Color(0x4027E1D7)),
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUser ? Icons.person : Icons.auto_awesome_rounded,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: SelectableText(
                    msg.text,
                    style: const TextStyle(color: fg, height: 1.35),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_all_rounded, size: 18, color: fg),
                  splashRadius: 16,
                ),
              ],
            ),
            if (msg.atts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: msg.atts
                    .map(
                      (a) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          a.bytes ?? Uint8List(0),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* ============================ Thinking Brain ============================= */

class _ThinkingBrain extends StatelessWidget {
  const _ThinkingBrain();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Center(child: SizedBox(width: 140, height: 140, child: _Brain())),
    );
  }
}

class _Brain extends StatefulWidget {
  @override
  State<_Brain> createState() => _BrainState();
}

class _BrainState extends State<_Brain> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(painter: _BrainPainter(_c.value));
        },
      ),
    );
  }
}

class _BrainPainter extends CustomPainter {
  _BrainPainter(this.t);
  final double t; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .28;

    // glow bg
    final glow = Paint()
      ..color = const Color(0xFF27E1D7).withOpacity(.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(c, radius * 1.6, glow);

    // rings
    for (int i = 0; i < 3; i++) {
      final sc = 1.0 + (t + i * .2) % 1 * .6;
      final alpha = (1 - (sc - 1) / .6).clamp(0.0, 1.0);
      final p = Paint()
        ..color = const Color(0xFF27E1D7).withOpacity(.55 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(c, radius * sc, p);
    }

    // brain circle
    final brain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF27E1D7);
    canvas.drawCircle(c, radius, brain);

    // data sweep
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = SweepGradient(
        colors: const [Color(0xFF27E1D7), Colors.transparent],
        stops: const [.0, .85],
        transform: GradientRotation(t * math.pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: radius * 1.2));
    final rect = Rect.fromCircle(center: c, radius: radius * 1.2);
    canvas.drawArc(rect, 0, math.pi * 1.6, false, sweep);

    // moving dot
    final len = math.pi * 1.6 * radius * 1.2;
    final theta = (t * len / (radius * 1.2));
    final pos = Offset(
      c.dx + math.cos(theta) * radius * 1.2,
      c.dy + math.sin(theta) * radius * 1.2,
    );
    final dot = Paint()..color = const Color(0xFF27E1D7);
    canvas.drawCircle(pos, 3.4, dot);

    // thinking sparks
    for (int i = 0; i < 10; i++) {
      final ang = (i / 10) * math.pi * 2;
      final r =
          radius * (.55 + .45 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + i)));
      final p = Offset(c.dx + math.cos(ang) * r, c.dy + math.sin(ang) * r);
      final s = Paint()
        ..color = const Color(0xFF9ADBF2).withOpacity(.65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(p, 2.2, s);
    }
  }

  @override
  bool shouldRepaint(covariant _BrainPainter oldDelegate) => true;
}

/* =============================== Starfield =============================== */

class _Starfield extends StatefulWidget {
  const _Starfield();

  @override
  State<_Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<_Starfield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _StarPainter(_c));
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.c) : super(repaint: c);
  final Animation<double> c;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF0B1220);
    canvas.drawRect(Offset.zero & size, bg);

    final n = (size.width * size.height / 12000).clamp(80, 220).toInt();
    final t = c.value;
    for (int i = 0; i < n; i++) {
      final x = (i * 91) % size.width;
      final y = (i * 57 + t * 30) % size.height;
      final r = (1 + (i % 3)) * .65;
      final col = [
        const Color(0xFFE1E6F8),
        const Color(0xFF9ADBF2),
        const Color(0xFFCBB9F8),
      ][i % 3].withOpacity(.85);
      final p = Paint()
        ..color = col
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(x.toDouble(), y.toDouble()), r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => true;
}

/* ================================ Utils ================================= */

String? _guessMime(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}
