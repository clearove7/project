import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../modifier/fancy_routes.dart';
import 'medication_list_page.dart';

class MedicationInputPage extends StatefulWidget {
  const MedicationInputPage({super.key, this.docId, this.initial});
  final String? docId;
  final Map<String, dynamic>? initial;

  @override
  State<MedicationInputPage> createState() => _MedicationInputPageState();
}

class _MedicationInputPageState extends State<MedicationInputPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final List<TimeOfDay> _times = [];
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  // 多选提醒开关
  bool _popupEnabled = false;
  bool _alarmEnabled = false;

  static const MethodChannel _ch = MethodChannel('alarm_channel');
  bool get _isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    if (m != null) {
      _name.text = (m['name'] ?? '').toString();
      _dose.text = (m['dose'] ?? '').toString();
      final ts =
          (m['times'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      _times.addAll(ts.map(_parseTime));
      _start = _toDate(m['startDate']);
      _end = _toDate(m['endDate']);
      _popupEnabled = m['popupEnabled'] == true;
      _alarmEnabled = m['alarmEnabled'] == true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  /* ---------------- helpers ---------------- */
  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  TimeOfDay _parseTime(String s) {
    try {
      final p = s.split(':');
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _reqCodeFor(DateTime when) => when.millisecondsSinceEpoch % 2147483647;

  /* --------------- pickers --------------- */
  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final rounded = TimeOfDay(
      hour: now.hour,
      minute: (now.minute / 5).round() * 5 % 60,
    );
    final t = await showTimePicker(
      context: context,
      initialTime: rounded,
      helpText: 'Select time',
    );
    if (t != null) {
      final exists = _times.any(
        (e) => e.hour == t.hour && e.minute == t.minute,
      );
      if (!exists) {
        setState(() {
          _times.add(t);
          _times.sort(
            (a, b) => a.hour * 60 + a.minute - (b.hour * 60 + b.minute),
          );
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This time already exists')),
        );
      }
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final init = start ? (_start ?? today) : (_end ?? (_start ?? today));
    final d = await showDatePicker(
      context: context,
      initialDate: init.isBefore(today) ? today : init,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
      helpText: start ? 'Select start date' : 'Select end date',
    );
    if (d != null) {
      setState(() {
        if (start) {
          _start = d;
          if (_end != null && _end!.isBefore(_start!)) _end = _start;
        } else {
          if (_start != null && d.isBefore(_start!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('End date cannot be earlier than start date'),
              ),
            );
          } else {
            _end = d;
          }
        }
      });
    }
  }

  /* ---------- permissions guides ---------- */
  Future<void> _ensureAlarmPermIfNeeded() async {
    if (!_alarmEnabled) return;
    final notif = await Permission.notification.status;
    if (notif.isDenied || notif.isRestricted) {
      await Permission.notification.request();
    }
    try {
      await _ch.invokeMethod('openExactAlarmSettings');
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<void> _openNotifSettings() async {
    try {
      await _ch.invokeMethod('openNotificationSettings');
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<void> _openBatterySettings() async {
    try {
      await _ch.invokeMethod('openBatterySettings');
    } catch (_) {
      await openAppSettings();
    }
  }

  /* -------- schedule / cancel ---------- */
  Future<void> _scheduleByModes({
    required bool popupEnabled,
    required bool alarmEnabled,
    required String name,
    required String dose,
    required List<TimeOfDay> times,
  }) async {
    if (!popupEnabled && !alarmEnabled) return;

    for (final t in times) {
      final now = DateTime.now();
      var when = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      if (when.isBefore(now)) when = when.add(const Duration(days: 1));

      if (alarmEnabled) {
        await _ch.invokeMethod('setExactAlarm', {
          'timestamp': when.millisecondsSinceEpoch,
          'medicine': name,
          'dose': dose,
        });
      }
      if (popupEnabled) {
        await _ch.invokeMethod('schedulePopup', {
          'timestamp': when.millisecondsSinceEpoch,
          'title': 'Time to take $name',
          'content': dose.isEmpty ? 'Reminder' : dose,
        });
      }
    }
  }

  Future<void> _cancelRecent() async {
    if (_times.isEmpty) return;
    int count = 0;
    for (final t in _times) {
      final now = DateTime.now();
      var when = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      if (when.isBefore(now)) when = when.add(const Duration(days: 1));
      final req = _reqCodeFor(when);
      try {
        await _ch.invokeMethod('cancelAlarm', {'requestCode': req});
        count++;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Canceled $count recent alarm(s).')));
  }

  /* ---------------- save ---------------- */
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose start & end dates')),
      );
      return;
    }
    if (_end!.isBefore(_start!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date cannot be earlier than start date'),
        ),
      );
      return;
    }
    if (_times.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one time')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }

    await _ensureAlarmPermIfNeeded();

    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'dose': _dose.text.trim(),
        'times': _times.map(_fmtTime).toList(),
        'startDate': Timestamp.fromDate(_start!),
        'endDate': Timestamp.fromDate(_end!),
        'popupEnabled': _popupEnabled,
        'alarmEnabled': _alarmEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final col = FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .collection('medications');
      if (widget.docId == null) {
        await col.add(data..['createdAt'] = FieldValue.serverTimestamp());
      } else {
        await col.doc(widget.docId!).update(data);
      }

      await _scheduleByModes(
        popupEnabled: _popupEnabled,
        alarmEnabled: _alarmEnabled,
        name: _name.text.trim(),
        dose: _dose.text.trim(),
        times: _times,
      );

      if (!mounted) return;
      final df = DateFormat('yyyy-MM-dd');
      final timeStr = _times.map(_fmtTime).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved • $timeStr  ${df.format(_start!)} → ${df.format(_end!)}  (${[if (_popupEnabled) 'Popup', if (_alarmEnabled) 'Alarm'].join('+')})',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /* ---------------- UI ---------------- */
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Medication' : 'Add Medication'),
        actions: [
          IconButton(
            tooltip: 'View list',
            icon: const Icon(Icons.list_rounded),
            onPressed: () => pushFadeScale(context, const MedicationListPage()),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: cs.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.06),
                blurRadius: 14,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancelRecent,
                  icon: const Icon(Icons.alarm_off_rounded),
                  label: const Text('Cancel recent alarms'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Saving...' : 'Save'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              _SectionCard(
                title: 'Basics',
                icon: Icons.vaccines_rounded,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Name *'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _dose,
                      decoration: const InputDecoration(
                        labelText: 'Dose (e.g., 200mg or 1 tab)',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Schedule',
                icon: Icons.schedule_rounded,
                trailing: IconButton(
                  tooltip: 'Add time',
                  icon: const Icon(Icons.add_alarm_rounded),
                  onPressed: _pickTime,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: -6,
                      children: _times.isEmpty
                          ? [
                              Text(
                                'No times selected',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ]
                          : _times
                                .asMap()
                                .entries
                                .map(
                                  (e) => InputChip(
                                    label: Text(_fmtTime(e.value)),
                                    onDeleted: () =>
                                        setState(() => _times.removeAt(e.key)),
                                  ),
                                )
                                .toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DateTile(
                            label: 'Start date',
                            value: _start,
                            onTap: () => _pickDate(start: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateTile(
                            label: 'End date',
                            value: _end,
                            onTap: () => _pickDate(start: false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Reminder',
                icon: Icons.notifications_active_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Popup'),
                          avatar: const Icon(
                            Icons.notification_important_outlined,
                          ),
                          selected: _popupEnabled,
                          onSelected: (v) => setState(() => _popupEnabled = v),
                        ),
                        FilterChip(
                          label: const Text('Alarm'),
                          avatar: const Icon(Icons.alarm_rounded),
                          selected: _alarmEnabled,
                          onSelected: (v) => setState(() => _alarmEnabled = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _PermGuide(
                      needAlarm: _alarmEnabled,
                      onOpenExactAlarm: _ensureAlarmPermIfNeeded,
                      onOpenNotif: _openNotifSettings,
                      onOpenBattery: _openBatterySettings,
                    ),
                    const SizedBox(height: 12),

                    // —— 修改处：让两个测试按钮平分一行，避免溢出 ——
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await _ch
                                  .invokeMethod('schedulePopup', {
                                    'timestamp': DateTime.now()
                                        .add(const Duration(seconds: 10))
                                        .millisecondsSinceEpoch,
                                    'title': 'Test popup',
                                    'content': 'In 10 seconds',
                                  });
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok == true ? 'Popup in 10s' : 'Failed',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.notification_important_outlined,
                            ),
                            label: const Text('Test popup (10s)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await _ch
                                  .invokeMethod('setExactAlarm', {
                                    'timestamp': DateTime.now()
                                        .add(const Duration(seconds: 10))
                                        .millisecondsSinceEpoch,
                                    'medicine': _name.text.trim().isEmpty
                                        ? 'Test'
                                        : _name.text.trim(),
                                    'dose': _dose.text.trim().isEmpty
                                        ? 'Demo'
                                        : _dose.text.trim(),
                                  });
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok == true ? 'Alarm in 10s' : 'Failed',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.alarm_rounded),
                            label: const Text('Test alarm (10s)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      !_popupEnabled && !_alarmEnabled
                          ? 'No reminder will be scheduled.'
                          : [
                              if (_popupEnabled) 'Popup',
                              if (_alarmEnabled) 'Alarm',
                            ].join(' + '),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ----------- UI bits ----------- */

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.secondaryContainer.withOpacity(.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // —— 修改处：label 使用 Expanded + 省略号，避免溢出 ——
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              value == null
                  ? '--/--/----'
                  : DateFormat('yyyy-MM-dd').format(value!),
              softWrap: false,
            ),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_month_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _PermGuide extends StatelessWidget {
  const _PermGuide({
    required this.needAlarm,
    required this.onOpenExactAlarm,
    required this.onOpenNotif,
    required this.onOpenBattery,
  });

  final bool needAlarm;
  final Future<void> Function() onOpenExactAlarm;
  final Future<void> Function() onOpenNotif;
  final Future<void> Function() onOpenBattery;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (needAlarm)
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.secondaryContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: onOpenExactAlarm,
                child: const Text('Exact Alarm Permission'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.secondaryContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: onOpenNotif,
                child: const Text('Notification Settings'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.secondaryContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: onOpenBattery,
                child: const Text('Battery Optimizations'),
              ),
            ],
          ),
      ],
    );
  }
}
