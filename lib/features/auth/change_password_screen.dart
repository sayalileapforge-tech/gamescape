import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _passCtrl = TextEditingController();
  final _currentPassCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final newPassword = _passCtrl.text.trim();
    final currentPassword = _currentPassCtrl.text.trim();
    
    print('🔐 Save password clicked');
    print('   Current password length: ${currentPassword.length}');
    print('   New password length: ${newPassword.length}');
    
    if (newPassword.isEmpty) {
      setState(() => _error = 'New password is required');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (currentPassword.isEmpty) {
      setState(() => _error = 'Current password is required');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      print('   User: ${user?.email}');
      
      if (user == null) {
        throw Exception('No user logged in');
      }
      
      // Re-authenticate with current password
      print('   Re-authenticating...');
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      print('   ✅ Re-authentication successful');
      
      // Update to new password
      print('   Updating password...');
      await user.updatePassword(newPassword);
      print('   ✅ Password updated');
      
      // Clear mustChangePassword flag
      print('   Updating Firestore...');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'mustChangePassword': false,
        'passwordUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('   ✅ Firestore updated');

      if (mounted) {
        print('   Navigating to dashboard...');
        context.go('/dashboard');
      }
    } on FirebaseAuthException catch (e) {
      print('   ❌ FirebaseAuthException: ${e.code} - ${e.message}');
      if (mounted) {
        setState(() {
          _saving = false;
          if (e.code == 'wrong-password') {
            _error = 'Current password is incorrect';
          } else if (e.code == 'weak-password') {
            _error = 'Password is too weak';
          } else {
            _error = 'Error: ${e.message}';
          }
        });
      }
    } catch (e) {
      print('   ❌ General error: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to change password: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Set new password',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _currentPassCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Current password (temporary)',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'New password',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
