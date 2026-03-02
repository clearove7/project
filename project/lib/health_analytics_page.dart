import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';

// PDF / print / share
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

// pages
import 'share_gate_page.dart';
import 'ai_assistant_page.dart';

class HealthAnalyticsPage extends StatefulWidget {
  const HealthAnalyticsPage({super.key});
  @override
  State<HealthAnalyticsPage> createState() => _HealthAnalyticsPageState();
}

enum Metric { snore, systolic, diastolic, weight, bmi }

class _HealthAnalyticsPageState extends State<HealthAnalyticsPage>
    with SingleTickerProviderStateMixin {
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  Duration _range = const Duration(days: 7);
  bool _normalize = false;
  final Set<Metric> _selected = {
    Metric.snore,
    Metric.systolic,
    Metric.diastolic,
    Metric.weight,
    Metric.bmi,
  };

  late Future<_SeriesBundle> _future;

  // capture chart
  final GlobalKey _chartKey = GlobalKey();

  // notes carried to PDF
  String _notes = '';

  // MethodChannel for snore segments
  static const MethodChannel _segmentsChannel = MethodChannel('snore_segments');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  Future<_SeriesBundle> _load() async {
    if (_uid == null) throw Exception('User not logged in');

    final now = DateTime.now();
    final from = now.subtract(
      _range == const Duration(days: 365) ? const Duration(days: 365) : _range,
    );

    // diagnostics
    int hrFetched = 0;
    int hrKept = 0;
    int snoreDailyHits = 0;

    // health_records
    final hrSnap = await FirebaseFirestore.instance
        .collection('Users')
        .doc(_uid)
        .collection('health_records')
        .where('timestamp', isGreaterThanOrEqualTo: from)
        .orderBy('timestamp')
        .get();

    hrFetched = hrSnap.docs.length;

    List<_Point> systolic = [];
    List<_Point> diastolic = [];
    List<_Point> weight = [];
    List<_Point> bmi = [];
    List<_Point> snore = [];

    for (final d in hrSnap.docs) {
      final m = d.data();
      final ts = _asDateTime(m['timestamp']);
      if (ts == null) continue;
      if (ts.isBefore(from) || ts.isAfter(now)) continue;
      hrKept++;

      if (m['systolic'] != null)
        systolic.add(_Point(ts, (m['systolic'] as num).toDouble()));
      if (m['diastolic'] != null)
        diastolic.add(_Point(ts, (m['diastolic'] as num).toDouble()));
      if (m['weight'] != null)
        weight.add(_Point(ts, (m['weight'] as num).toDouble()));
      if (m['bmi'] != null) bmi.add(_Point(ts, (m['bmi'] as num).toDouble()));
      if (m['snoreMin'] != null)
        snore.add(_Point(ts, (m['snoreMin'] as num).toDouble()));
    }

    // snore_daily (prefer)
    try {
      final sSnap = await FirebaseFirestore.instance
          .collection('Users')
          .doc(_uid)
          .collection('snore_daily')
          .where(
            'date',
            isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(from),
          )
          .orderBy('date')
          .get();
      snoreDailyHits = sSnap.docs.length;
      if (sSnap.docs.isNotEmpty) {
        snore.clear();
        for (final d in sSnap.docs) {
          final m = d.data();
          final dt = DateTime.tryParse((m['date'] ?? '') as String);
          if (dt == null) continue;
          final v = (m['minutes'] as num?)?.toDouble() ?? 0;
          snore.add(_Point(dt, v));
        }
      }
    } catch (_) {}

    // If no snore_daily data, fall back to local .wav files
    if (snore.isEmpty) {
      try {
        final List<dynamic>? paths = await _segmentsChannel.invokeMethod(
          'getSegments',
        );
        final List<String> filePaths =
            (paths as List?)?.map((e) => e as String).toList() ?? [];

        final Map<DateTime, double> dailyMinutes = {};
        for (final path in filePaths) {
          final File file = File(path);
          if (!await file.exists()) continue;

          // Extract date from filename: snore_yyyyMMdd_HHmmss.wav
          final basename = p.basenameWithoutExtension(path);
          DateTime? fileDate;
          if (basename.startsWith('snore_') && basename.length >= 17) {
            final dateStr = basename.substring(7, 15); // "20251025"
            try {
              fileDate = DateTime(
                int.parse(dateStr.substring(0, 4)),
                int.parse(dateStr.substring(4, 6)),
                int.parse(dateStr.substring(6, 8)),
              );
            } on FormatException {
              // Fallback to lastModified
              fileDate = await file.lastModified();
            }
          } else {
            // Fallback to lastModified
            fileDate = await file.lastModified();
          }

          final day = DateTime(fileDate.year, fileDate.month, fileDate.day);
          final bytes = await file.readAsBytes();
          final dur = _wavDuration(bytes) ?? Duration.zero;
          final mins = dur.inMilliseconds / 60000.0; // ms to minutes
          dailyMinutes[day] = (dailyMinutes[day] ?? 0) + mins;
        }

        snore = dailyMinutes.entries
            .map((e) => _Point(e.key, e.value))
            .toList();
        snore.sort((a, b) => a.t.compareTo(b.t));
      } catch (e) {
        debugPrint('Local snore analysis failed: $e');
      }
    }

    // down to days
    systolic = _reduceDaily(systolic);
    diastolic = _reduceDaily(diastolic);
    weight = _reduceDaily(weight);
    bmi = _reduceDaily(bmi);
    snore = _reduceDaily(snore);

    // x-axis days
    final days = _buildDays(from, now);
    final mapper = {
      for (int i = 0; i < days.length; i++) days[i]: i.toDouble(),
    };

    List<FlSpot> _toSpots(List<_Point> src) {
      final map = {for (final p in src) _dayOnly(p.t): p.v};
      return [
        for (final d in days)
          if (map.containsKey(d)) FlSpot(mapper[d]!, map[d]!),
      ]; // Fixed: use mapper[d]!
    }

    final lines = <Metric, List<FlSpot>>{
      Metric.snore: _toSpots(snore),
      Metric.systolic: _toSpots(systolic),
      Metric.diastolic: _toSpots(diastolic),
      Metric.weight: _toSpots(weight),
      Metric.bmi: _toSpots(bmi),
    };

    // stats
    double? _latest(List<_Point> l) => l.isEmpty ? null : l.last.v;

    final stats = _Stats(
      latestSys: _latest(systolic),
      latestDia: _latest(diastolic),
      latestW: _latest(weight),
      latestBmi: _latest(bmi),
      avgSnore: snore.isEmpty
          ? 0
          : snore.map((e) => e.v).reduce((a, b) => a + b) / snore.length,
    );

    // diagnostics points & latest ts
    DateTime? _latestTs(List<_Point> l) => l.isEmpty ? null : l.last.t;
    final pts = <Metric, int>{
      Metric.snore: lines[Metric.snore]?.length ?? 0,
      Metric.systolic: lines[Metric.systolic]?.length ?? 0,
      Metric.diastolic: lines[Metric.diastolic]?.length ?? 0,
      Metric.weight: lines[Metric.weight]?.length ?? 0,
      Metric.bmi: lines[Metric.bmi]?.length ?? 0,
    };
    final latestTs = <Metric, DateTime?>{
      Metric.snore: _latestTs(snore),
      Metric.systolic: _latestTs(systolic),
      Metric.diastolic: _latestTs(diastolic),
      Metric.weight: _latestTs(weight),
      Metric.bmi: _latestTs(bmi),
    };

    final diag = _Diagnostics(
      from: from,
      to: now,
      hrFetched: hrFetched,
      hrKept: hrKept,
      snoreDailyHits: snoreDailyHits,
      pts: pts,
      latestTs: latestTs,
    );

    final fmt = DateFormat('yyyy-MM-dd');
    final line =
        'DIAG range=${fmt.format(from)}~${fmt.format(now)} | health_records fetched=$hrFetched kept=$hrKept | '
        'snore_daily hits=$snoreDailyHits | pts{snore=${pts[Metric.snore]}, sys=${pts[Metric.systolic]}, '
        'dia=${pts[Metric.diastolic]}, w=${pts[Metric.weight]}, bmi=${pts[Metric.bmi]}}';
    print(line);

    return _SeriesBundle(
      days: days,
      xMap: mapper,
      lines: lines,
      stats: stats,
      diag: diag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Analytics & PDF'),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: () async {
              final bundle = await _future;
              final png = await _captureChartPng();
              if (!context.mounted) return;
              await _exportPdf(bundle, png);
            },
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _enter.drive(CurveTween(curve: Curves.easeOut)),
        child: FutureBuilder<_SeriesBundle>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError)
              return Center(child: Text('Load failed: ${snap.error}'));
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());

            final bundle = snap.data!;
            final rangeLabel = _rangeLabel();

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                // Range picker
                const _SectionTitle('Date Range'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _rangeChip('Last 7 days', const Duration(days: 7)),
                    _rangeChip('Last 30 days', const Duration(days: 30)),
                    _rangeChip('Last 90 days', const Duration(days: 90)),
                    _rangeChip('All', const Duration(days: 365)),
                  ],
                ),
                const SizedBox(height: 12),

                // Metrics multi-select
                const _SectionTitle('Metrics'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metricChip(
                      Metric.snore,
                      'Snore (min/day)',
                      Icons.self_improvement_outlined,
                    ),
                    _metricChip(
                      Metric.systolic,
                      'Systolic (mmHg)',
                      Icons.favorite,
                    ),
                    _metricChip(
                      Metric.diastolic,
                      'Diastolic',
                      Icons.favorite_border,
                    ),
                    _metricChip(
                      Metric.weight,
                      'Weight (kg)',
                      Icons.monitor_weight_outlined,
                    ),
                    _metricChip(Metric.bmi, 'BMI', Icons.show_chart_rounded),
                  ],
                ),
                const SizedBox(height: 12),

                // Risk cards
                _RiskCard(
                  color: _bpColor(
                    _bpStage(bundle.stats.latestSys, bundle.stats.latestDia),
                  ),
                  title:
                      'Blood Pressure: ${_bpStageLabel(_bpStage(bundle.stats.latestSys, bundle.stats.latestDia))}',
                  subtitle: _bpAdvice(
                    _bpStage(bundle.stats.latestSys, bundle.stats.latestDia),
                  ),
                ),
                const SizedBox(height: 10),
                if (bundle.stats.latestBmi != null)
                  _RiskCard(
                    color: _bmiColor(bundle.stats.latestBmi!),
                    title: 'BMI: ${_bmiLabel(bundle.stats.latestBmi!)}',
                    subtitle: 'Consider calorie control and more activity.',
                  ),
                const SizedBox(height: 10),
                _RiskCard(
                  color: _snoreColor(bundle.stats.avgSnore),
                  title: 'Snoring: ${_snoreLabel(bundle.stats.avgSnore)}',
                  subtitle:
                      'Likely ${bundle.stats.avgSnore <= 10 ? 'minimal' : 'non-trivial'} impact on sleep.',
                ),
                const SizedBox(height: 12),

                // Notes for PDF
                _NotesCard(onChanged: (s) => _notes = s),
                const SizedBox(height: 10),

                // Header + Normalize
                Row(
                  children: [
                    const _SectionTitle('Trends'),
                    const Spacer(),
                    const Text('Normalize'),
                    const SizedBox(width: 6),
                    Switch(
                      value: _normalize,
                      onChanged: (v) => setState(() => _normalize = v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Chart
                RepaintBoundary(
                  key: _chartKey,
                  child: _TrendsChart(
                    bundle: bundle,
                    selected: _selected,
                    normalize: _normalize,
                  ),
                ),

                const SizedBox(height: 14),
                _Legend(selected: _selected),

                const SizedBox(height: 12),
                // Ask AI button
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Ask AI about this range'),
                    onPressed: () async {
                      final png = await _captureChartPng();

                      final selectedLabels = _selected
                          .map((m) {
                            switch (m) {
                              case Metric.snore:
                                return 'Snore (min/day)';
                              case Metric.systolic:
                                return 'Systolic';
                              case Metric.diastolic:
                                return 'Diastolic';
                              case Metric.weight:
                                return 'Weight (kg)';
                              case Metric.bmi:
                                return 'BMI';
                            }
                          })
                          .join(', ');

                      final prompt =
                          """
Please analyze my health in this time window and call out risks if any.

WINDOW: $rangeLabel
METRICS_SELECTED: $selectedLabels

Focus on:
- Latest values and last-window averages
- Notable rises/drops
- Practical suggestions (diet, sleep, activity)
""";

                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AiAssistantPage(
                            initialPrompt: prompt,
                            initialRangeDays: _range.inDays == 365
                                ? 365
                                : _range.inDays,
                            initialImagePng: png,
                            autoSendInitial: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Export hint
                Center(
                  child: Text(
                    'Range: $rangeLabel  •  Long press the PDF icon to print/share',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Diagnostics
                _DataDiagnosticsCard(diag: bundle.diag),
              ],
            );
          },
        ),
      ),
    );
  }

  // chips
  Widget _rangeChip(String label, Duration d) {
    final selected = _range == d;
    final cs = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() {
        _range = d;
        _future = _load();
      }),
      selectedColor: cs.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? cs.onPrimaryContainer : cs.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _metricChip(Metric m, String label, IconData icon) {
    final on = _selected.contains(m);
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      avatar: Icon(
        icon,
        size: 18,
        color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      ),
      label: Text(label),
      selected: on,
      onSelected: (v) => setState(() {
        if (v) {
          _selected.add(m);
        } else {
          if (_selected.length > 1) _selected.remove(m);
        }
      }),
      selectedColor: cs.primaryContainer,
      labelStyle: TextStyle(
        color: on ? cs.onPrimaryContainer : cs.onSurface,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: cs.outlineVariant),
      showCheckmark: on,
    );
  }

  String _rangeLabel() {
    final now = DateTime.now();
    final from = now.subtract(
      _range == const Duration(days: 365) ? const Duration(days: 365) : _range,
    );
    final f = DateFormat('yyyy-MM-dd');
    return '${f.format(from)} ~ ${f.format(now)}';
  }

  // capture chart to PNG
  Future<Uint8List?> _captureChartPng() async {
    try {
      final boundary =
          _chartKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // PDF export → ShareGatePage
  Future<void> _exportPdf(_SeriesBundle b, Uint8List? png) async {
    final doc = pw.Document();
    final cs = Theme.of(context).colorScheme;
    final title = 'Health Analytics Report';
    final period = _rangeLabel();

    final bpStage = _bpStage(b.stats.latestSys, b.stats.latestDia);
    final bpLabel = _bpStageLabel(bpStage);
    final bpColor = _pdfC(_bpColor(bpStage));
    final bmiLabel = b.stats.latestBmi != null
        ? _bmiLabel(b.stats.latestBmi!)
        : 'Unknown';
    final bmiColor = _pdfC(
      b.stats.latestBmi != null ? _bmiColor(b.stats.latestBmi!) : Colors.grey,
    );
    final snoreLabel = _snoreLabel(b.stats.avgSnore);
    final snoreColor = _pdfC(_snoreColor(b.stats.avgSnore));

    doc.addPage(
      pw.MultiPage(
        pageTheme: await _pdfTheme(),
        build: (c) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(period),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'This report is auto-generated for general wellness tracking and is not medical advice.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 12),

          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _trafficRow('Blood Pressure: $bpLabel', bpColor),
                _trafficRow('BMI: $bmiLabel', bmiColor),
                _trafficRow('Snoring: $snoreLabel', snoreColor),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              _row('Avg Systolic', _fmtD(_avgFl(b.lines[Metric.systolic]))),
              _row('Avg Diastolic', _fmtD(_avgFl(b.lines[Metric.diastolic]))),
              _row('Latest Weight (kg)', _fmtD(b.stats.latestW)),
              _row('Latest BMI', _fmtD(b.stats.latestBmi)),
              _row('Avg Snore Minutes / Day', _fmtD(b.stats.avgSnore)),
            ],
          ),
          pw.SizedBox(height: 16),

          if (png != null) ...[
            pw.Text(
              'Trends (selected metrics)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(10),
                color: _pdfC(cs.primaryContainer),
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              padding: const pw.EdgeInsets.all(8),
              child: pw.Image(
                pw.MemoryImage(png),
                fit: pw.BoxFit.contain,
                height: 320,
              ),
            ),
            pw.SizedBox(height: 12),
          ],

          if (_notes.trim().isNotEmpty) ...[
            pw.Text(
              'Notes',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(_notes),
          ],
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/HealthReport_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareGatePage(
          title: 'Share Health Report',
          text: 'Health Analytics Report',
          files: [XFile(file.path)],
          autoPopOnReturn: true,
          autoPopDelayMs: 900,
        ),
      ),
    );
  }
}

/* ==================== widgets / helpers / models ==================== */

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
    );
  }
}

class _NotesCard extends StatefulWidget {
  const _NotesCard({required this.onChanged});
  final ValueChanged<String> onChanged;
  @override
  State<_NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<_NotesCard> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _c,
        onChanged: widget.onChanged,
        maxLines: 3,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Notes (will be added to PDF)',
          prefixIcon: Icon(Icons.edit_note_rounded),
        ),
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final Color color;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.selected});
  final Set<Metric> selected;
  @override
  Widget build(BuildContext context) {
    final items = [
      if (selected.contains(Metric.snore))
        _item(context, Metric.snore, 'Snore (min)'),
      if (selected.contains(Metric.systolic))
        _item(context, Metric.systolic, 'Systolic'),
      if (selected.contains(Metric.diastolic))
        _item(context, Metric.diastolic, 'Diastolic'),
      if (selected.contains(Metric.weight))
        _item(context, Metric.weight, 'Weight (kg)'),
      if (selected.contains(Metric.bmi)) _item(context, Metric.bmi, 'BMI'),
    ];
    return Wrap(spacing: 12, runSpacing: 6, children: items);
  }

  Widget _item(BuildContext context, Metric m, String label) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _metricColor(cs, m),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _TrendsChart extends StatelessWidget {
  const _TrendsChart({
    required this.bundle,
    required this.selected,
    required this.normalize,
  });
  final _SeriesBundle bundle;
  final Set<Metric> selected;
  final bool normalize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = bundle.days.length;
    if (n < 2) return _placeholder(context, 'No data');

    final lines = <LineChartBarData>[];
    double minY = double.infinity, maxY = -double.infinity;

    for (final m in Metric.values) {
      if (!selected.contains(m)) continue;
      var spots = bundle.lines[m] ?? const <FlSpot>[];
      if (spots.isEmpty) continue;

      if (normalize) {
        final ys = spots.map((e) => e.y).toList();
        final localMin = ys.reduce(math.min);
        final localMax = ys.reduce(math.max);
        final k = (localMax - localMin).abs() < 1e-6
            ? 1.0
            : (localMax - localMin);
        spots = [
          for (final s in spots) FlSpot(s.x, (s.y - localMin) / k * 100),
        ];
        minY = math.min(minY, 0);
        maxY = math.max(maxY, 100);
      } else {
        final ys = spots.map((e) => e.y).toList();
        minY = math.min(minY, ys.reduce(math.min));
        maxY = math.max(maxY, ys.reduce(math.max));
      }

      lines.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: .28,
          color: _metricColor(cs, m),
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                _metricColor(cs, m).withOpacity(.20),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      );
    }

    if (lines.isEmpty)
      return _placeholder(context, 'No selected metric has data');

    final step = (n ~/ 6).clamp(1, 9999);
    final isYear = n > 180;
    final fmt = DateFormat(isYear ? 'MM' : 'MM/dd');

    if (!normalize) {
      final span = (maxY - minY).abs() < 1e-6 ? 1 : (maxY - minY);
      final pad = span * 0.12;
      minY -= pad;
      maxY += pad;
    } else {
      minY = -5;
      maxY = 105;
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 12),
      height: 300,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: (maxY - minY) / 4,
            verticalInterval: step.toDouble(),
            getDrawingHorizontalLine: (v) => FlLine(
              color: cs.outlineVariant.withOpacity(.5),
              strokeWidth: 1,
              dashArray: [6, 6],
            ),
            getDrawingVerticalLine: (v) => FlLine(
              color: cs.outlineVariant.withOpacity(.35),
              strokeWidth: 1,
              dashArray: [4, 6],
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: (maxY - minY) / 4,
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: step.toDouble(),
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= bundle.days.length)
                    return const SizedBox.shrink();
                  final d = bundle.days[i];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      fmt.format(d),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: cs.outlineVariant),
              bottom: BorderSide(color: cs.outlineVariant),
            ),
          ),
          lineBarsData: lines,
        ),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Widget _placeholder(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      height: 220,
      child: Center(
        child: Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
      ),
    );
  }
}

/* ==================== models / utils ==================== */

class _SeriesBundle {
  _SeriesBundle({
    required this.days,
    required this.xMap,
    required this.lines,
    required this.stats,
    required this.diag,
  });
  final List<DateTime> days;
  final Map<DateTime, double> xMap;
  final Map<Metric, List<FlSpot>> lines;
  final _Stats stats;
  final _Diagnostics diag;
}

class _Stats {
  _Stats({
    this.latestSys,
    this.latestDia,
    this.latestW,
    this.latestBmi,
    required this.avgSnore,
  });
  final double? latestSys;
  final double? latestDia;
  final double? latestW;
  final double? latestBmi;
  final double avgSnore;
}

class _Diagnostics {
  _Diagnostics({
    required this.from,
    required this.to,
    required this.hrFetched,
    required this.hrKept,
    required this.snoreDailyHits,
    required this.pts,
    required this.latestTs,
  });
  final DateTime from;
  final DateTime to;
  final int hrFetched;
  final int hrKept;
  final int snoreDailyHits;
  final Map<Metric, int> pts;
  final Map<Metric, DateTime?> latestTs;
}

class _Point {
  _Point(this.t, this.v);
  final DateTime t;
  final double v;
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

List<_Point> _reduceDaily(List<_Point> src) {
  final map = <DateTime, List<double>>{};
  for (final p in src) {
    final day = _dayOnly(p.t);
    map.putIfAbsent(day, () => []).add(p.v);
  }
  final out = <_Point>[];
  for (final e
      in map.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    final avg = e.value.reduce((a, b) => a + b) / e.value.length;
    out.add(_Point(e.key, avg));
  }
  return out;
}

List<DateTime> _buildDays(DateTime from, DateTime to) {
  final s = _dayOnly(from);
  final e = _dayOnly(to);
  final out = <DateTime>[];
  var cur = s;
  while (!cur.isAfter(e)) {
    out.add(cur);
    cur = cur.add(const Duration(days: 1));
  }
  return out;
}

double? _avgFl(List<FlSpot>? spots) {
  final s = spots ?? const <FlSpot>[];
  if (s.isEmpty) return null;
  return s.map((e) => e.y).reduce((a, b) => a + b) / s.length;
}

String _fmtD(double? v) => v == null
    ? '-'
    : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));

Color _metricColor(ColorScheme cs, Metric m) {
  switch (m) {
    case Metric.snore:
      return Colors.teal;
    case Metric.systolic:
      return Colors.deepPurple;
    case Metric.diastolic:
      return Colors.orange;
    case Metric.weight:
      return Colors.blue;
    case Metric.bmi:
      return Colors.brown;
  }
}

enum _BPStage { low, normal, highNormal, stage1, stage2, stage3, unknown }

_BPStage _bpStage(double? sys, double? dia) {
  if (sys == null || dia == null) return _BPStage.unknown;
  if (sys < 90 || dia < 60) return _BPStage.low;
  if (sys < 120 && dia < 80) return _BPStage.normal;
  if ((sys >= 120 && sys <= 139) || (dia >= 80 && dia <= 89))
    return _BPStage.highNormal;
  if ((sys >= 140 && sys <= 159) || (dia >= 90 && dia <= 99))
    return _BPStage.stage1;
  if ((sys >= 160 && sys <= 179) || (dia >= 100 && dia <= 109))
    return _BPStage.stage2;
  if (sys >= 180 || dia >= 110) return _BPStage.stage3;
  return _BPStage.unknown;
}

Color _bpColor(_BPStage s) {
  switch (s) {
    case _BPStage.low:
      return Colors.blue;
    case _BPStage.normal:
      return Colors.green;
    case _BPStage.highNormal:
      return Colors.amber;
    case _BPStage.stage1:
      return Colors.deepOrange;
    case _BPStage.stage2:
      return Colors.red;
    case _BPStage.stage3:
      return Colors.redAccent;
    case _BPStage.unknown:
      return Colors.grey;
  }
}

String _bpStageLabel(_BPStage s) {
  switch (s) {
    case _BPStage.low:
      return 'Low';
    case _BPStage.normal:
      return 'Normal';
    case _BPStage.highNormal:
      return 'High-normal';
    case _BPStage.stage1:
      return 'Stage 1';
    case _BPStage.stage2:
      return 'Stage 2';
    case _BPStage.stage3:
      return 'Stage 3';
    case _BPStage.unknown:
      return 'Unknown';
  }
}

String _bpAdvice(_BPStage s) {
  switch (s) {
    case _BPStage.low:
      return 'May cause dizziness or fatigue; monitor hydration.';
    case _BPStage.normal:
      return 'Great! Keep healthy diet, exercise and checks.';
    case _BPStage.highNormal:
      return 'Reduce salt, manage weight, and recheck regularly.';
    case _BPStage.stage1:
      return 'Lifestyle changes recommended; consider medical review.';
    case _BPStage.stage2:
      return 'High risk; seek clinician advice for evaluation.';
    case _BPStage.stage3:
      return 'Very high risk; urgent medical attention.';
    case _BPStage.unknown:
      return 'Enter BP values to evaluate.';
  }
}

String _bmiLabel(double v) {
  if (v < 18.5) return 'Underweight';
  if (v < 25) return 'Normal';
  if (v < 30) return 'Overweight';
  return 'Obese';
}

Color _bmiColor(double v) {
  if (v < 18.5) return Colors.blue;
  if (v < 25) return Colors.green;
  if (v < 30) return Colors.orange;
  return Colors.red;
}

String _snoreLabel(double minutes) {
  if (minutes <= 5) return 'Low snoring time';
  if (minutes <= 30) return 'Moderate snoring';
  return 'High snoring time';
}

Color _snoreColor(double minutes) {
  if (minutes <= 5) return Colors.green;
  if (minutes <= 30) return Colors.orange;
  return Colors.red;
}

// pdf helpers
pw.TableRow _row(String k, String v) => pw.TableRow(
  children: [
    pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Text(k)),
    pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: pw.Alignment.centerRight,
      child: pw.Text(v),
    ),
  ],
);

pw.Widget _trafficRow(String text, PdfColor dot) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 6),
  child: pw.Row(
    children: [
      pw.Container(
        width: 8,
        height: 8,
        decoration: pw.BoxDecoration(color: dot, shape: pw.BoxShape.circle),
      ),
      pw.SizedBox(width: 6),
      pw.Text(text),
    ],
  ),
);

PdfColor _pdfC(Color c) => PdfColor.fromInt(c.value);

Future<pw.PageTheme> _pdfTheme() async {
  final base = await PdfGoogleFonts.nunitoRegular();
  final bold = await PdfGoogleFonts.nunitoBold();
  return pw.PageTheme(
    theme: pw.ThemeData.withFont(base: base, bold: bold),
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
  );
}

/* ==================== Diagnostics card ==================== */

class _DataDiagnosticsCard extends StatelessWidget {
  const _DataDiagnosticsCard({required this.diag});
  final _Diagnostics diag;

  String _fmtDate(DateTime? d) =>
      d == null ? '-' : DateFormat('yyyy-MM-dd HH:mm').format(d);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dayFmt = DateFormat('yyyy-MM-dd');
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          initiallyExpanded: false,
          leading: const Icon(Icons.bug_report),
          title: const Text(
            'Data Diagnostics',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Query: ${dayFmt.format(diag.from)} ~ ${dayFmt.format(diag.to)}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          children: [
            _rowK(
              'health_records fetched',
              '${diag.hrFetched} (raw snapshot count)',
            ),
            _rowK(
              'health_records kept (within range & parse ok)',
              '${diag.hrKept}',
            ),
            _rowK('snore_daily hits', '${diag.snoreDailyHits}'),
            const SizedBox(height: 4),
            _hdr('Points per metric'),
            _rowK('Snore (min/day)', '${diag.pts[Metric.snore] ?? 0}'),
            _rowK('Systolic', '${diag.pts[Metric.systolic] ?? 0}'),
            _rowK('Diastolic', '${diag.pts[Metric.diastolic] ?? 0}'),
            _rowK('Weight', '${diag.pts[Metric.weight] ?? 0}'),
            _rowK('BMI', '${diag.pts[Metric.bmi] ?? 0}'),
            const SizedBox(height: 4),
            _hdr('Latest timestamp per metric'),
            _rowK('Snore', _fmtDate(diag.latestTs[Metric.snore])),
            _rowK('Systolic', _fmtDate(diag.latestTs[Metric.systolic])),
            _rowK('Diastolic', _fmtDate(diag.latestTs[Metric.diastolic])),
            _rowK('Weight', _fmtDate(diag.latestTs[Metric.weight])),
            _rowK('BMI', _fmtDate(diag.latestTs[Metric.bmi])),
            const SizedBox(height: 4),
            Text(
              'Tips: If fetched > 0 but each indicator pts = 0, it is usually due to a mismatch in field name/type/time; '
              'if fetched = 0, then there are indeed no records in the collection within this range.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hdr(String t) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _rowK(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(k)),
        Text(
          v,
          style: const TextStyle(
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

// Add this helper function to parse WAV duration
Duration? _wavDuration(Uint8List data) {
  if (data.length < 44) return null;
  final bd = ByteData.sublistView(data);
  final sr = bd.getUint32(24, Endian.little);
  final ch = bd.getUint16(22, Endian.little);
  final bps = bd.getUint16(34, Endian.little);
  final dataBytes = bd.getUint32(40, Endian.little);
  if (sr == 0 || ch == 0 || bps == 0) return null;
  final samples = (dataBytes * 8) ~/ (bps * ch);
  return Duration(milliseconds: (samples * 1000 ~/ sr));
}
