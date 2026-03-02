import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';

import 'health_record_list_page.dart'; // ← 历史列表入口

enum BPStatus { low, normal, highNormal, stage1, stage2, stage3, unknown }

class HealthInputPage extends StatefulWidget {
  const HealthInputPage({super.key});
  @override
  State<HealthInputPage> createState() => _HealthInputPageState();
}

class _HealthInputPageState extends State<HealthInputPage> {
  final _formKey = GlobalKey<FormState>();
  final height = TextEditingController();
  final weight = TextEditingController();
  final systolic = TextEditingController();
  final diastolic = TextEditingController();

  double? bmi;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    height.addListener(_updateBMI);
    weight.addListener(_updateBMI);
    systolic.addListener(() => setState(() {}));
    diastolic.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    height.dispose();
    weight.dispose();
    systolic.dispose();
    diastolic.dispose();
    super.dispose();
  }

  void _updateBMI() {
    final h = double.tryParse(height.text);
    final w = double.tryParse(weight.text);
    if (h != null && h > 0 && w != null && w > 0) {
      final m = h / 100;
      setState(() => bmi = w / math.pow(m, 2));
    } else {
      setState(() => bmi = null);
    }
  }

  int? _toInt(String? s) => int.tryParse((s ?? '').trim());

  BPStatus classifyBP(int? sys, int? dia) {
    if (sys == null || dia == null) return BPStatus.unknown;
    if (sys < 90 || dia < 60) return BPStatus.low;
    if (sys < 120 && dia < 80) return BPStatus.normal;
    if ((sys >= 120 && sys <= 139) || (dia >= 80 && dia <= 89))
      return BPStatus.highNormal;
    if ((sys >= 140 && sys <= 159) || (dia >= 90 && dia <= 99))
      return BPStatus.stage1;
    if ((sys >= 160 && sys <= 179) || (dia >= 100 && dia <= 109))
      return BPStatus.stage2;
    if (sys >= 180 || dia >= 110) return BPStatus.stage3;
    return BPStatus.unknown;
  }

  String bpTitle(BPStatus s) {
    switch (s) {
      case BPStatus.low:
        return 'Low blood pressure';
      case BPStatus.normal:
        return 'Normal blood pressure';
      case BPStatus.highNormal:
        return 'High-normal blood pressure';
      case BPStatus.stage1:
        return 'Hypertension – Stage 1';
      case BPStatus.stage2:
        return 'Hypertension – Stage 2';
      case BPStatus.stage3:
        return 'Hypertensive crisis – Stage 3';
      default:
        return 'Blood pressure: Unknown';
    }
  }

  String bpAdvice(BPStatus s) {
    switch (s) {
      case BPStatus.low:
        return 'May cause dizziness or fatigue; monitor symptoms and hydration.';
      case BPStatus.normal:
        return 'Great! Keep healthy diet, exercise and regular checks.';
      case BPStatus.highNormal:
        return 'Reduce salt, manage weight, and recheck BP regularly.';
      case BPStatus.stage1:
        return 'Lifestyle changes recommended; consider medical review.';
      case BPStatus.stage2:
        return 'High risk; seek clinician advice for evaluation.';
      case BPStatus.stage3:
        return 'Very high risk; seek urgent medical attention.';
      default:
        return 'Enter both systolic and diastolic values.';
    }
  }

  Color bpColor(BPStatus s) {
    switch (s) {
      case BPStatus.low:
        return Colors.blue;
      case BPStatus.normal:
        return Colors.green;
      case BPStatus.highNormal:
        return Colors.orange;
      case BPStatus.stage1:
        return Colors.deepOrange;
      case BPStatus.stage2:
        return Colors.red;
      case BPStatus.stage3:
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Color _bmiColor(double v) {
    if (v < 18.5) return Colors.blue;
    if (v < 25) return Colors.green;
    if (v < 30) return Colors.orange;
    return Colors.red;
  }

  String _bmiLabel(double v) {
    if (v < 18.5) return 'Underweight';
    if (v < 25) return 'Normal weight';
    if (v < 30) return 'Overweight';
    return 'Obese';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || bmi == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete the form properly')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User is not logged in')));
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .collection('health_records')
          .add({
            'height': double.parse(height.text),
            'weight': double.parse(weight.text),
            'systolic': int.parse(systolic.text),
            'diastolic': int.parse(diastolic.text),
            'bmi': double.parse(bmi!.toStringAsFixed(2)),
            'timestamp': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to cloud ✅')));

      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withOpacity(.35),
        isScrollControlled: true,
        builder: (_) {
          final cs = Theme.of(context).colorScheme;
          return Center(
            child:
                Container(
                      width: 240,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: cs.outlineVariant.withOpacity(.4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.20),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: Lottie.asset(
                              'assets/lottie/success_check.json',
                              repeat: false,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.check_circle,
                                size: 72,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Saved to Cloud',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Great job! Keep tracking your health.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 200.ms)
                    .scale(duration: 280.ms, curve: Curves.easeOutBack),
          );
        },
      );

      // 清空
      height.clear();
      weight.clear();
      systolic.clear();
      diastolic.clear();
      setState(() => bmi = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final fields = <Widget>[
      TextFormField(
        controller: height,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Height (cm)',
          prefixIcon: Icon(Icons.height_rounded),
        ),
        validator: (v) {
          final x = double.tryParse((v ?? '').trim());
          if (x == null || x <= 0) return 'Enter a valid height';
          return null;
        },
      ),
      TextFormField(
        controller: weight,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Weight (kg)',
          prefixIcon: Icon(Icons.monitor_weight_outlined),
        ),
        validator: (v) {
          final x = double.tryParse((v ?? '').trim());
          if (x == null || x <= 0) return 'Enter a valid weight';
          return null;
        },
      ),
      TextFormField(
        controller: systolic,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Systolic (mmHg)',
          prefixIcon: Icon(Icons.favorite_outline),
        ),
        validator: (v) {
          final x = int.tryParse((v ?? '').trim());
          if (x == null || x <= 0) return 'Enter systolic value';
          return null;
        },
      ),
      TextFormField(
        controller: diastolic,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Diastolic (mmHg)',
          prefixIcon: Icon(Icons.favorite_border),
        ),
        validator: (v) {
          final x = int.tryParse((v ?? '').trim());
          if (x == null || x <= 0) return 'Enter diastolic value';
          return null;
        },
      ),
    ];

    final sys = _toInt(systolic.text);
    final dia = _toInt(diastolic.text);
    final status = classifyBP(sys, dia);
    final bpClr = bpColor(status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Data Input'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_edu_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HealthRecordListPage()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // 表单入场动画（Stagger）
                for (int i = 0; i < fields.length; i++)
                  fields[i]
                      .animate(delay: (120 * i).ms)
                      .fadeIn(duration: 260.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: .12,
                        end: 0,
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      ),
                const SizedBox(height: 16),

                // BMI 卡片
                if (bmi != null)
                  _StatCard(
                        title: 'BMI',
                        value: bmi!.toStringAsFixed(2),
                        subtitle: _bmiLabel(bmi!),
                        color: _bmiColor(bmi!),
                      )
                      .animate()
                      .fadeIn(duration: 250.ms)
                      .scale(
                        begin: const Offset(.96, .96),
                        end: const Offset(1, 1),
                        duration: 250.ms,
                      ),

                const SizedBox(height: 10),

                // 血压建议卡片
                if (sys != null && dia != null)
                  _AdviceCard(
                        title: bpTitle(status),
                        advice: bpAdvice(status),
                        color: bpClr,
                      )
                      .animate()
                      .fadeIn(duration: 260.ms)
                      .slideY(
                        begin: .08,
                        end: 0,
                        duration: 300.ms,
                        curve: Curves.easeOut,
                      ),

                const SizedBox(height: 22),

                // 保存
                SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(_saving ? 'Saving...' : 'Save'),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 260.ms)
                    .scale(
                      begin: const Offset(.98, .98),
                      end: const Offset(1, 1),
                    ),

                const SizedBox(height: 10),

                // 历史入口（底部）
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('View history'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HealthRecordListPage(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title: $value',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Health status: $subtitle',
                  style: TextStyle(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({
    required this.title,
    required this.advice,
    required this.color,
  });
  final String title;
  final String advice;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(advice, style: TextStyle(color: cs.onSurface)),
        ],
      ),
    );
  }
}
