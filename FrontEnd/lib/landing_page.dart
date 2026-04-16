// landing_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _storage = const FlutterSecureStorage();
  final _auth = FirebaseAuth.instance;

  String? _selectedRole;
  bool _showForm = false;
  bool _isLoading = false;
  bool _showPassword = false;

  final _usernameController = TextEditingController();
  final _batchController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _attemptAutoLogin();
  }

  Future<void> _attemptAutoLogin() async {
    final savedUsername = await _storage.read(key: 'username');
    if (savedUsername != null) {
      final snapshot = await _getUserSnapshot(savedUsername, null);
      if (!snapshot.exists) return;

      final email = snapshot['email'];
      final role = snapshot['role'];

      final user = _auth.currentUser;
      if (user != null && user.emailVerified) {
        if (role.toLowerCase() == 'student') {
          Navigator.pushReplacementNamed(context, '/dashboard_student');
        } else {
          Navigator.pushReplacementNamed(context, '/dashboard_teacher');
        }
      }
    }
  }

  void _selectRole(String role) async {
    await FirebaseAuth.instance.signOut();
    _usernameController.clear();
    _passwordController.clear();
    _batchController.clear();

    setState(() {
      _selectedRole = role;
      _showForm = true;
    });
  }

  void _showMessage(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color ?? Colors.black87),
    );
  }

  Future<bool> _checkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<DocumentSnapshot> _getUserSnapshot(String username, String? batch) async {
    const maxAttempts = 4;
    int attempt = 0;
    final key = username;

    while (attempt < maxAttempts) {
      try {
        return await FirebaseFirestore.instance
            .collection('usernames')
            .doc(key)
            .get(const GetOptions(source: Source.server));
      } catch (_) {
        attempt++;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    throw Exception('Unable to fetch user document after $maxAttempts attempts.');
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMessage('Please fill in all fields', color: Colors.red);
      return;
    }

    if (!await _checkConnection()) {
      _showMessage('No internet connection detected. Please check your connection.', color: Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final snapshot = await _getUserSnapshot(username, null);

      if (!snapshot.exists) {
        _showMessage('User not found', color: Colors.red);
        return;
      }

      final email = snapshot['email'];
      final role = snapshot['role'];

      if (_selectedRole == null || role.toLowerCase() != _selectedRole!.toLowerCase()) {
        _showMessage('Access denied: You are registered as $role.', color: Colors.red);
        return;
      }

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;

      if (user == null || !user.emailVerified) {
        await FirebaseAuth.instance.signOut();
        _showMessage('Please verify your email before logging in.', color: Colors.orange);
        return;
      }

      await _storage.write(key: 'username', value: username);

      _showMessage('Login successful!', color: Colors.green);

      if (role.toLowerCase() == 'student') {
        Navigator.pushReplacementNamed(context, '/dashboard_student');
      } else {
        Navigator.pushReplacementNamed(context, '/dashboard_teacher');
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Login failed', color: Colors.red);
    } catch (e) {
      _showMessage('Error: $e', color: Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _showForm ? _buildForm() : _buildModeSelection(),
      ),
    );
  }

  Widget _buildModeSelection() {
    return Container(
      key: const ValueKey('modeSelection'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4A90E2), Color(0xFF00BCD4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 100),
            const SizedBox(height: 24),
            const Text('VedaSync',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text('Smart Classroom Companion', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _selectRole('Teacher'),
              icon: const Icon(Icons.person_outline),
              label: const Text('Teacher Mode'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF4A90E2),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _selectRole('Student'),
              icon: const Icon(Icons.school_outlined),
              label: const Text('Student Mode'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF00BCD4),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/signup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
              child: const Text('Sign Up'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      key: const ValueKey('formPage'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4A90E2), Color(0xFF00BCD4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('Login as $_selectedRole',
                  style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF4A90E2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
