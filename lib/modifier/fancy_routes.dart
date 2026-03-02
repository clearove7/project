import 'package:flutter/material.dart';

Future<T?> pushFadeScale<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

Future<T?> pushSharedAxis<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

Future<T?> pushSlideFancy<T>(BuildContext context, Widget page, {AxisDirection? from}) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}
