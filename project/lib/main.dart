import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'register_page.dart'; // 改成你实际文件名
import 'home_page.dart';
// import 'firebase_options.dart'; // 如果你用了 flutterfire configure，就打开这行

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 如果你有 firebase_options.dart，推荐这样初始化：
  // await Firebase.initializeApp(
  //   options: DefaultFirebaseOptions.currentPlatform,
  // );

  // 如果你暂时没有 firebase_options.dart，可先这样：
  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),

      // 方式1：直接让注册页作为启动页
      home: const RegisterPage(),

      // 方式2：命名路由（可选）
      routes: {
        '/register': (_) => const RegisterPage(),
        '/home': (_) => const HomePage(),
      },
    );
  }
}
