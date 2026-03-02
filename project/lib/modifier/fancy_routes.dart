import 'package:flutter/material.dart';
import 'package:animations/animations.dart';

Future<T?> pushFadeScale<T>(
  BuildContext context,
  Widget page, {
  Duration duration = const Duration(milliseconds: 420),
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder:
          (BuildContext _, Animation<double> __, Animation<double> ___) => page,
      transitionsBuilder:
          (
            BuildContext _,
            Animation<double> anim,
            Animation<double> __,
            Widget child,
          ) {
            final curve = CurvedAnimation(
              parent: anim,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curve,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(curve),
                child: child,
              ),
            );
          },
    ),
  );
}

Future<T?> pushSharedAxis<T>(
  BuildContext context,
  Widget page, {
  SharedAxisTransitionType type = SharedAxisTransitionType.horizontal,
  Duration duration = const Duration(milliseconds: 460),
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder:
          (BuildContext _, Animation<double> __, Animation<double> ___) => page,
      transitionsBuilder:
          (
            BuildContext _,
            Animation<double> anim,
            Animation<double> sec,
            Widget child,
          ) {
            return SharedAxisTransition(
              animation: anim,
              secondaryAnimation: sec,
              transitionType: type,
              child: child,
            );
          },
    ),
  );
}

Future<T?> pushFadeThrough<T>(
  BuildContext context,
  Widget page, {
  Duration duration = const Duration(milliseconds: 420),
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder:
          (BuildContext _, Animation<double> __, Animation<double> ___) => page,
      transitionsBuilder:
          (
            BuildContext _,
            Animation<double> anim,
            Animation<double> sec,
            Widget child,
          ) {
            return FadeThroughTransition(
              animation: anim,
              secondaryAnimation: sec,
              child: child,
            );
          },
    ),
  );
}

Future<T?> pushSlideFancy<T>(
  BuildContext context,
  Widget page, {
  AxisDirection from = AxisDirection.right,
  Duration duration = const Duration(milliseconds: 420),
}) {
  final begin = switch (from) {
    AxisDirection.up => const Offset(0, .08),
    AxisDirection.down => const Offset(0, -.08),
    AxisDirection.left => const Offset(.08, 0),
    AxisDirection.right => const Offset(-.08, 0),
  };
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder:
          (BuildContext _, Animation<double> __, Animation<double> ___) => page,
      transitionsBuilder:
          (
            BuildContext _,
            Animation<double> anim,
            Animation<double> __,
            Widget child,
          ) {
            final curve = CurvedAnimation(
              parent: anim,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: begin,
                  end: Offset.zero,
                ).animate(curve),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1.0).animate(curve),
                  child: child,
                ),
              ),
            );
          },
    ),
  );
}
