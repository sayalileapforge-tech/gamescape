import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  int _secretTapCount = 0;

  Future<void> _login() async {
    setState(() => _loading = true);
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    try {
      // Normal login flow
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (mounted) context.go('/dashboard');
    } on FirebaseAuthException catch (e) {
      // Attempt first-time bootstrap using tempPassword stored in Firestore
      bool bootstrapped = false;

      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

          if (snap.docs.isNotEmpty) {
            final doc = snap.docs.first;
            final data = doc.data() as Map<String, dynamic>;
            final tempPwd = data['tempPassword']?.toString();

            if (tempPwd != null && tempPwd.isNotEmpty && tempPwd == password) {
              final cred = await FirebaseAuth.instance
                  .createUserWithEmailAndPassword(email: email, password: password);
              final uid = cred.user?.uid;

              if (uid != null) {
                final usersColl = FirebaseFirestore.instance.collection('users');
                await usersColl.doc(uid).set({
                  ...data,
                  'email': email,
                  'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (doc.id != uid) {
                  await doc.reference.delete();
                }
              }

              bootstrapped = true;
              if (mounted) context.go('/dashboard');
            }
          }
        } catch (_) { /* ignore bootstrap errors */ }
      }

      if (!bootstrapped) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Login failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSecretTap() {
    _secretTapCount++;
    if (_secretTapCount >= 5) {
      _secretTapCount = 0;
      context.go('/bootstrap-admin');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppTheme.bg1,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            // uses Theme.cardTheme colors/radius
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _onSecretTap,
                    child: Column(
                      children: [
                        Text(
                          'GameScape',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppTheme.textStrong,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Admin Panel',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: AppTheme.textMute,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Inputs (benefit from global InputDecorationTheme)
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tip: Tap the “GameScape” title 5 times to setup the first admin.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textFaint,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: size.height < 660 ? 8 : 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
