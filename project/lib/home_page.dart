import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:getwidget/getwidget.dart';
import 'package:animations/animations.dart';

import 'modifier/auth_animations.dart';
import 'modifier/fancy_routes.dart';

// your pages
import 'health_input_page.dart';
import 'medication_input_page.dart';
import 'medication_list_page.dart';
import 'health_analytics_page.dart';
import 'sleep_analysis_start_page.dart';
import 'ai_assistant_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bg = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _bg.dispose();
    super.dispose();
  }

  String get _helloName {
    final u = FirebaseAuth.instance.currentUser;
    return (u?.displayName?.trim().isNotEmpty ?? false)
        ? u!.displayName!.trim()
        : (u?.email?.split('@').first ?? 'User');
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();

      // ********** THE ONLY IMPORTANT CHANGE **********
      // Clear the entire stack to root ('/'), which is your AuthGate.
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);

      // 如果你没有用命名路由，也可以用下面这个（记得 import AuthGate 所在文件）：
      // Navigator.of(context).pushAndRemoveUntil(
      //   MaterialPageRoute(builder: (_) => const AuthGate()),
      //   (route) => false,
      // );
      // ***********************************************
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      floatingActionButton: GFButton(
        onPressed: () => pushFadeScale(context, const AiAssistantPage()),
        icon: const Icon(Icons.smart_toy_outlined, color: Colors.white),
        text: 'AI Assistant',
        type: GFButtonType.solid,
        shape: GFButtonShape.pills,
        size: GFSize.LARGE,
        color: cs.primary,
      ),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bg,
            builder: (_, __) {
              final t = _bg.value * 2 * math.pi;
              final bgStops = isDark
                  ? [
                      cs.surfaceVariant.withOpacity(.18),
                      cs.surface.withOpacity(.16),
                      Colors.black.withOpacity(.20),
                    ]
                  : [
                      cs.primaryContainer.withOpacity(.32),
                      cs.secondaryContainer.withOpacity(.28),
                      cs.tertiaryContainer.withOpacity(.24),
                    ];
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: bgStops,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    _blob(
                      220,
                      Offset(90 * math.sin(t), 60 * math.cos(t)),
                      cs.primary.withOpacity(isDark ? .12 : .18),
                    ),
                    _blob(
                      280,
                      Offset(-110 * math.cos(t), 70 * math.sin(t)),
                      cs.secondary.withOpacity(isDark ? .10 : .14),
                    ),
                    _blob(
                      180,
                      Offset(60 * math.cos(t * .8), -90 * math.sin(t * .9)),
                      cs.tertiary.withOpacity(isDark ? .08 : .12),
                    ),
                  ],
                ),
              );
            },
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $_helloName',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: _MiniStatGF(
                          icon: Icons.favorite_rounded,
                          label: 'Well-being',
                          value: 'Stable',
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MiniStatGF(
                          icon: Icons.nightlight_round,
                          label: 'Sleep',
                          value: 'Ready',
                          color: cs.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _ActionCardGF(
                    heroTag: 'hero-health',
                    icon: Icons.favorite_border_rounded,
                    title: 'Health Data Input',
                    subtitle: 'Enter BP / Height / Weight; auto-calc BMI',
                    onTap: () =>
                        pushSharedAxis(context, const HealthInputPage()),
                  ),
                  const SizedBox(height: 12),

                  _ActionCardGF(
                    heroTag: 'hero-meds',
                    icon: Icons.medication_liquid_outlined,
                    title: 'Medication Records & Reminders',
                    subtitle: 'Add meds and set local reminders',
                    onTap: () => pushSlideFancy(
                      context,
                      const MedicationInputPage(),
                      from: AxisDirection.right,
                    ),
                    trailing: IconButton(
                      tooltip: 'View list',
                      icon: const Icon(Icons.list_rounded),
                      onPressed: () =>
                          pushFadeScale(context, const MedicationListPage()),
                    ),
                  ),
                  const SizedBox(height: 12),

                  OpenContainer(
                    transitionDuration: const Duration(milliseconds: 520),
                    openColor: Theme.of(context).colorScheme.surface,
                    closedElevation: 0,
                    closedShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    openBuilder: (_, __) => const HealthAnalyticsPage(),
                    closedBuilder: (_, open) => _ActionCardGF(
                      heroTag: 'hero-analytics',
                      icon: Icons.show_chart_rounded,
                      title: 'Health Analytics & Report',
                      subtitle: 'Dynamic charts, export to PDF',
                      trailing: _PillBadge(
                        icon: Icons.picture_as_pdf_rounded,
                        label: 'PDF',
                      ),
                      onTap: open,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _ActionCardGF(
                    heroTag: 'hero-sleep',
                    icon: Icons.dark_mode_rounded,
                    title: 'Sleep Analysis',
                    subtitle: 'Start screen → real-time snore detection',
                    trailing: GFButton(
                      onPressed: () => pushSlideFancy(
                        context,
                        const SleepAnalysisStartPage(),
                        from: AxisDirection.up,
                      ),
                      text: 'Start',
                      icon: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                      type: GFButtonType.solid,
                      shape: GFButtonShape.pills,
                      color: cs.primary,
                      size: GFSize.MEDIUM,
                    ),
                    onTap: () => pushSlideFancy(
                      context,
                      const SleepAnalysisStartPage(),
                      from: AxisDirection.up,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Offset offset, Color color) => Align(
    alignment: Alignment.center,
    child: Transform.translate(
      offset: offset,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(.35),
              blurRadius: 80,
              spreadRadius: 10,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionCardGF extends StatelessWidget {
  const _ActionCardGF({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    required this.heroTag,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GFCard(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: cs.surface.withOpacity(.70),
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      content: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Hero(
                tag: heroTag,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: cs.primary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(' ', style: TextStyle(height: 0)),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withOpacity(.8),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStatGF extends StatelessWidget {
  const _MiniStatGF({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GFCard(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(0),
      elevation: 1.5,
      margin: EdgeInsets.zero,
      content: Container(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 12, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
