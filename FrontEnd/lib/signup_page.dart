import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'landing_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  String? _selectedRole;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _batchController = TextEditingController();
  String? _selectedProgram;
  String? _selectedFaculty;
  bool _isSubmitting = false;

  final List<String> _programs = [
    'Computer Engineering',
    'Information Technology',
    'Electronics & Communication',
    'Civil Engineering',
    'Business Administration',
    'Architecture',
  ];

  final List<String> _faculties = [
    'Architecture Department',
    'BBA Department',
    'ICT Department',
    'Civil Department',
  ];

  void _showMessage(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color ?? Colors.black87),
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final role = _selectedRole;
    final batch = _batchController.text.trim();

    if ([name, username, email, password, confirmPassword, role].contains(null) ||
        name.isEmpty || username.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showMessage('Please fill in all required fields', color: Colors.red);
      return;
    }

    if (password != confirmPassword) {
      _showMessage('Passwords do not match', color: Colors.red);
      return;
    }

    final isTeacher = role == 'Teacher';

    if (isTeacher && _selectedFaculty == null) {
      _showMessage('Please select faculty', color: Colors.red);
      return;
    }

    if (!isTeacher && (_selectedProgram == null || batch.isEmpty)) {
      _showMessage('Please enter program and batch', color: Colors.red);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        _showMessage('Verification email sent. Please check your inbox.', color: Colors.blue);
      }

      final userData = {
        'uid': user!.uid,
        'name': name,
        'email': email,
        'role': role,
        'username': username,
        'createdAt': FieldValue.serverTimestamp(),
        if (isTeacher)
          'faculty': _selectedFaculty
        else ...{
          'program': _selectedProgram,
          'batch': batch,
        }
      };

      await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username)
          .set(userData);

    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Signup failed', color: Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildInput(TextEditingController controller, String label, {bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTeacher = _selectedRole == 'Teacher';
    final isStudent = _selectedRole == 'Student';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LandingPage()),
          ),
        ),
      ),
      body: _isSubmitting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedRole,
              items: const [
                DropdownMenuItem(value: 'Student', child: Text('Student')),
                DropdownMenuItem(value: 'Teacher', child: Text('Teacher')),
              ],
              onChanged: (value) => setState(() => _selectedRole = value),
              decoration: const InputDecoration(
                labelText: 'Select Role',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildInput(_nameController, 'Full Name'),
            const SizedBox(height: 16),
            _buildInput(_usernameController, 'Username'),
            const SizedBox(height: 16),
            _buildInput(_emailController, 'Email'),
            const SizedBox(height: 16),
            _buildInput(_passwordController, 'Password', obscure: true),
            const SizedBox(height: 16),
            _buildInput(_confirmPasswordController, 'Confirm Password', obscure: true),
            const SizedBox(height: 16),
            if (isTeacher)
              DropdownButtonFormField<String>(
                value: _selectedFaculty,
                items: _faculties.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                onChanged: (value) => setState(() => _selectedFaculty = value),
                decoration: const InputDecoration(
                  labelText: 'Faculty',
                  border: OutlineInputBorder(),
                ),
              ),
            if (isStudent) ...[
              DropdownButtonFormField<String>(
                value: _selectedProgram,
                items: _programs.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (value) => setState(() => _selectedProgram = value),
                decoration: const InputDecoration(
                  labelText: 'Program',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _buildInput(_batchController, 'Batch'),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check_circle),
              label: const Text('Register'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: const Color(0xFF4A90E2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
