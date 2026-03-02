import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'modifier/auth_animations.dart'; // GlowTitle / BreathingButton / GradientOutlineButton / 背景+入场动画
import 'home_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_password.text.trim() != _confirm.text.trim()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      await cred.user?.updateDisplayName(_name.text.trim());

      await FirebaseFirestore.instance
          .collection('Users')
          .doc(cred.user!.uid)
          .set({
            'uid': cred.user!.uid,
            'email': _email.text.trim(),
            'name': _name.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account created 🎉')));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'email-already-in-use' => 'Email already in use.',
        'weak-password' => 'Password is too weak.',
        'invalid-email' => 'Invalid email address.',
        _ => e.message ?? 'Registration failed.',
      };
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Registration failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(String label, {Widget? suffix}) => InputDecoration(
    labelText: label,
    filled: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outline.withOpacity(.4),
      ),
    ),
    suffixIcon: suffix,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: FancyAuthBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        FadeSlideIn(
                          child: GlowTitle(
                            'Create account',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FadeSlideIn(
                          delayMs: 80,
                          child: Text(
                            'Join and start tracking your health',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 18),

                        FadeSlideIn(
                          delayMs: 120,
                          child: TextFormField(
                            controller: _name,
                            decoration: _dec('Full name'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Name is required'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),

                        FadeSlideIn(
                          delayMs: 160,
                          child: TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _dec('Email'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Email is required'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),

                        FadeSlideIn(
                          delayMs: 200,
                          child: TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: _dec(
                              'Password',
                              suffix: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            validator: (v) => (v == null || v.trim().length < 6)
                                ? 'At least 6 characters'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),

                        FadeSlideIn(
                          delayMs: 240,
                          child: TextFormField(
                            controller: _confirm,
                            obscureText: _obscure,
                            decoration: _dec('Confirm password'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Confirm your password'
                                : null,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 呼吸发光主按钮
                        ScaleIn(
                          delayMs: 280,
                          child: BreathingButton(
                            onPressed: _loading ? null : _register,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_loading)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(Icons.person_add),
                                const SizedBox(width: 8),
                                const Text('Create account'),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // 渐变描边副按钮（返回登录）
                        FadeSlideIn(
                          delayMs: 320,
                          child: GradientOutlineButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Back to sign in'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
