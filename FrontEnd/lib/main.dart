import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'landing_page.dart';
import 'signup_page.dart';
import 'student/student_dashboard.dart';
import 'teacher/teacher_dashboard.dart';
import 'push_subjects.dart';
import 'students_details.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Ensure data is pushed before starting the app
  await pushSubjectsToFirestore();
  await addStudentsToFirebase();

  runApp(const VedaSyncApp());
}

class VedaSyncApp extends StatelessWidget {
  const VedaSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VedaSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF3F8FE),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LandingPage(),           // Auto-login + fingerprint logic is here
        '/signup': (context) => const SignUpPage(),       // New user registration
        '/dashboard_student': (context) => const StudentDashboard(),  // Student dashboard
        '/dashboard_teacher': (context) => TeacherDashboard(),  // Teacher dashboard
      },
    );
  }
}
