import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';

import 'student_notification.dart';
import 'student_calendar.dart';
import 'student_grades.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> with TickerProviderStateMixin {
  int _currentIndex = 0;
  File? _profileImage;
  bool _isDarkMode = false;

  String? fullName;
  String? batch;
  String? program;
  String? selectedSubject;

  List<String> subjects = [];
  Map<String, Map<String, dynamic>> attendanceData = {};
  bool isLoadingSubjects = false;
  bool isLoadingAttendance = false;

  // Animation controllers for interactivity
  late AnimationController _cardAnimationController;
  late AnimationController _statsAnimationController;
  late AnimationController _fadeAnimationController;

  // Animations
  late Animation<double> _cardAnimation;
  late Animation<double> _statsAnimation;
  late Animation<double> _fadeAnimation;

  // Interactive states
  bool _isRefreshing = false;
  String? _hoveredCard;

  // Color palette based on #3399dd
  static const Color primaryColor = Color(0xFF3399DD);
  static const Color secondaryColor = Color(0xFF66B3FF);
  static const Color accentColor = Color(0xFF0066CC);
  static const Color successColor = Color(0xFF00C896);
  static const Color warningColor = Color(0XFFFF8C42);
  static const Color errorColor = Color(0XFFFF5722);
  static const Color surfaceColor = Color(0XFFF8FAFF);
  static const Color cardColor = Color(0XFFFFFFFF);
  static const Color gradientStart = Color(0xFF3399DD);
  static const Color gradientEnd = Color(0xFF66B3FF);

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadUserInfo();
  }

  void _initAnimations() {
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _statsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _cardAnimation = CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.elasticOut,
    );

    _statsAnimation = CurvedAnimation(
      parent: _statsAnimationController,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeAnimationController,
      curve: Curves.easeInOut,
    );

    // Start animations
    _cardAnimationController.forward();
    _statsAnimationController.forward();
    _fadeAnimationController.forward();
  }

  @override
  void dispose() {
    _cardAnimationController.dispose();
    _statsAnimationController.dispose();
    _fadeAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('usernames')
          .where('email', isEqualTo: user.email)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        setState(() {
          fullName = data['name'];
          batch = data['batch'];
          program = data['program'];
        });

        if (fullName != null && batch != null && program != null) {
          await _loadSubjects();
          await _loadAttendanceData();
        }
      }
    } catch (e) {
      debugPrint('Error loading user info: $e');
    }
  }

  Future<void> _loadSubjects() async {
    if (program == null || batch == null) return;

    setState(() {
      isLoadingSubjects = true;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('programs')
          .doc(program)
          .collection('batches')
          .doc(batch)
          .get();

      if (doc.exists) {
        final courseData = doc.data()?['courses'] ?? [];
        List<String> subjectList = [];

        for (var course in courseData) {
          if (course['subject'] != null) {
            subjectList.add(course['subject']);
          }
        }

        setState(() {
          subjects = subjectList;
          isLoadingSubjects = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading subjects: $e');
      setState(() {
        isLoadingSubjects = false;
      });
    }
  }

  Future<void> _loadAttendanceData() async {
    if (fullName == null || program == null || batch == null) return;

    setState(() {
      isLoadingAttendance = true;
    });

    try {
      Map<String, Map<String, dynamic>> subjectAttendance = {};

      for (String subject in subjects) {
        final attendanceQuery = await FirebaseFirestore.instance
            .collection('attendance')
            .where('student_name', isEqualTo: fullName)
            .where('selectedProgram', isEqualTo: program)
            .where('selectedBatch', isEqualTo: batch)
            .where('selectedSubject', isEqualTo: subject)
            .get();

        final totalClassesDoc = await FirebaseFirestore.instance
            .collection('subjectClasses')
            .doc('$batch-$program-$subject')
            .get();

        int totalClasses = 0;
        if (totalClassesDoc.exists) {
          totalClasses = totalClassesDoc.data()?['totalClasses'] ?? 0;
        }

        int presentClasses = 0;
        List<DateTime> attendanceDates = [];

        for (var doc in attendanceQuery.docs) {
          final data = doc.data();
          bool isPresent = false;

          var statusField = data['status'];
          if (statusField is bool) {
            isPresent = statusField;
          } else if (statusField is String) {
            isPresent = statusField.toLowerCase() == 'present' ||
                statusField.toLowerCase() == 'true';
          }

          if (isPresent) {
            presentClasses++;
            if (data['timestamp'] != null) {
              try {
                DateTime date = (data['timestamp'] as Timestamp).toDate();
                attendanceDates.add(date);
              } catch (e) {
                debugPrint('Error parsing timestamp: $e');
              }
            }
          }
        }

        double percentage = totalClasses > 0 ? (presentClasses / totalClasses) * 100 : 0;

        subjectAttendance[subject] = {
          'totalClasses': totalClasses,
          'presentClasses': presentClasses,
          'percentage': percentage,
          'attendanceDates': attendanceDates,
        };
      }

      setState(() {
        attendanceData = subjectAttendance;
        isLoadingAttendance = false;
      });
    } catch (e) {
      debugPrint('Error loading attendance data: $e');
      setState(() {
        isLoadingAttendance = false;
      });
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    _cardAnimationController.reset();
    _statsAnimationController.reset();

    await _loadUserInfo();

    _cardAnimationController.forward();
    _statsAnimationController.forward();

    setState(() {
      _isRefreshing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Data refreshed successfully!'),
          ],
        ),
        backgroundColor: successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _pickImage() async {
    final result = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source', style: TextStyle(fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _isDarkMode ? Colors.grey[850] : cardColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildImageSourceTile(Icons.camera_alt, 'Camera', ImageSource.camera),
            const SizedBox(height: 8),
            _buildImageSourceTile(Icons.photo_library, 'Gallery', ImageSource.gallery),
          ],
        ),
      ),
    );

    if (result != null) {
      final pickedFile = await ImagePicker().pickImage(source: result);
      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
      }
    }
  }

  Widget _buildImageSourceTile(IconData icon, String title, ImageSource source) {
    return InkWell(
      onTap: () => Navigator.pop(context, source),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryColor.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: primaryColor),
            ),
            const SizedBox(width: 16),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _logout() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Confirmation', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to logout?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _isDarkMode ? Colors.grey[850] : cardColor,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: errorColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    }
  }

  Widget _buildAttendanceOverview() {
    if (attendanceData.isEmpty) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _isDarkMode ? Colors.grey[850] : cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.school_outlined,
                    size: 64,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'No Attendance Data',
                  style: TextStyle(
                    fontSize: 20,
                    color: _isDarkMode ? Colors.white : Colors.grey[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your attendance records will appear here',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _refreshData,
                  icon: _isRefreshing
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.refresh, color: Colors.white),
                  label: Text(
                    _isRefreshing ? 'Refreshing...' : 'Refresh Data',
                    style: const TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    elevation: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    int totalClassesOverall = 0;
    int totalPresentOverall = 0;

    for (var data in attendanceData.values) {
      totalClassesOverall += data['totalClasses'] as int;
      totalPresentOverall += data['presentClasses'] as int;
    }

    double overallPercentage = totalClassesOverall > 0
        ? (totalPresentOverall / totalClassesOverall) * 100
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall Statistics Card with improved design
        ScaleTransition(
          scale: _cardAnimation,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [gradientStart, gradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.analytics, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Overall Attendance',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _statsAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _statsAnimation.value,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Total Classes', totalClassesOverall.toString(), Icons.book),
                          _buildStatItem('Present', totalPresentOverall.toString(), Icons.check_circle),
                          _buildStatItem('Percentage', '${overallPercentage.toStringAsFixed(1)}%', Icons.trending_up),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Enhanced Subject Selection Dropdown
        FadeTransition(
          opacity: _fadeAnimation,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor.withOpacity(0.1), secondaryColor.withOpacity(0.1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: _isDarkMode ? Colors.grey[850] : cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedSubject,
                  hint: Row(
                    children: [
                      Icon(Icons.subject, color: primaryColor, size: 20),
                      const SizedBox(width: 12),
                      const Text(
                        'Select a subject to view details',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  isExpanded: true,
                  icon: Icon(Icons.expand_more, color: primaryColor),
                  items: subjects.map((subject) {
                    return DropdownMenuItem<String>(
                      value: subject,
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              subject,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedSubject = value;
                    });
                  },
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Subject-specific details with enhanced design
        if (selectedSubject != null && attendanceData.containsKey(selectedSubject))
          _buildSubjectDetails(),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectDetails() {
    final data = attendanceData[selectedSubject]!;
    final totalClasses = data['totalClasses'] as int;
    final presentClasses = data['presentClasses'] as int;
    final percentage = data['percentage'] as double;
    final attendanceDates = data['attendanceDates'] as List<DateTime>;

    Color percentageColor = percentage >= 75 ? successColor :
    percentage >= 50 ? warningColor : errorColor;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor, primaryColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.menu_book, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    selectedSubject!,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Subject Statistics Cards
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  'Total Classes',
                  totalClasses.toString(),
                  Icons.school,
                  primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  'Present',
                  presentClasses.toString(),
                  Icons.check_circle,
                  successColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  'Percentage',
                  '${percentage.toStringAsFixed(1)}%',
                  Icons.trending_up,
                  percentageColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Attendance Chart with enhanced design
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _isDarkMode ? Colors.grey[850] : cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.pie_chart, color: primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Attendance Distribution',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 200,
                  child: totalClasses > 0 ? PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          value: presentClasses.toDouble(),
                          title: '${((presentClasses/totalClasses)*100).toStringAsFixed(1)}%',
                          color: successColor,
                          radius: 70,
                          titleStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          value: (totalClasses - presentClasses).toDouble(),
                          title: '${(((totalClasses - presentClasses)/totalClasses)*100).toStringAsFixed(1)}%',
                          color: errorColor,
                          radius: 70,
                          titleStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                      sectionsSpace: 3,
                      centerSpaceRadius: 50,
                    ),
                  ) : Center(
                    child: Text(
                      'No data to display',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildLegendItem('Present', successColor, presentClasses),
                    _buildLegendItem('Absent', errorColor, totalClasses - presentClasses),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Recent Attendance with enhanced design
          if (attendanceDates.isNotEmpty) _buildRecentAttendance(attendanceDates),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label ($value)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDarkMode ? Colors.grey[850] : cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: _isDarkMode ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAttendance(List<DateTime> dates) {
    dates.sort((a, b) => b.compareTo(a));
    final recentDates = dates.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDarkMode ? Colors.grey[850] : cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.history, color: successColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Recent Attendance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...recentDates.asMap().entries.map((entry) {
            int index = entry.key;
            DateTime date = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: successColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: successColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: successColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${date.day}/${date.month}/${date.year}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _getWeekday(date.weekday),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: successColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Present',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  String _getWeekday(int weekday) {
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return weekdays[weekday - 1];
  }

  Widget _buildHomePage() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: primaryColor,
      backgroundColor: _isDarkMode ? Colors.grey[850] : cardColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), // Extra bottom padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header with enhanced design
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _isDarkMode ? Colors.grey[800]! : surfaceColor,
                    _isDarkMode ? Colors.grey[700]! : Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryColor.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.waving_hand, color: warningColor, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back,',
                              style: TextStyle(
                                fontSize: 16,
                                color: _isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${fullName?.split(' ').first ?? 'Student'}!',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: _isDarkMode ? Colors.white : Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: primaryColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Here\'s your attendance overview and academic progress',
                            style: TextStyle(
                              fontSize: 14,
                              color: _isDarkMode ? Colors.grey[300] : Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Loading or Content
            if (isLoadingSubjects || isLoadingAttendance)
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: _isDarkMode ? Colors.grey[850] : cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading your data...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildAttendanceOverview(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _isDarkMode
        ? ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    )
        : ThemeData.light().copyWith(
      scaffoldBackgroundColor: surfaceColor,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );

    final List<Widget> pages = [
      _buildHomePage(),
      const StudentNotification(),
      StudentCalendar(),
      const StudentGrades(),
    ];

    return MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Student Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          actions: [
            IconButton(
              onPressed: _refreshData,
              icon: _isRefreshing
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              children: [
                // Header with flexible height
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 200,
                    maxHeight: 250,
                  ),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isDarkMode
                          ? [Colors.grey[900]!, Colors.grey[800]!]
                          : [gradientStart, gradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 35,
                            backgroundImage: _profileImage != null
                                ? FileImage(_profileImage!)
                                : null,
                            backgroundColor: Colors.white,
                            child: _profileImage == null
                                ? const Icon(Icons.person, size: 35, color: Colors.grey)
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          fullName ?? 'Loading...',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDrawerInfoChip("Program", program ?? '...'),
                      const SizedBox(height: 4),
                      _buildDrawerInfoChip("Batch", batch ?? '...'),
                    ],
                  ),
                ),

                // Expanded content area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Dark mode toggle
                        Container(
                          decoration: BoxDecoration(
                            color: _isDarkMode ? Colors.grey[800] : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: primaryColor.withOpacity(0.2)),
                          ),
                          child: SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: const Text(
                              'Dark Mode',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            value: _isDarkMode,
                            onChanged: (val) {
                              setState(() {
                                _isDarkMode = val;
                              });
                            },
                            secondary: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _isDarkMode ? warningColor.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                _isDarkMode ? Icons.dark_mode : Icons.light_mode,
                                color: _isDarkMode ? warningColor : Colors.grey[600],
                                size: 20,
                              ),
                            ),
                            activeColor: primaryColor,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Logout button
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: errorColor.withOpacity(0.2)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: errorColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.logout, color: errorColor, size: 20),
                            ),
                            title: Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: errorColor,
                              ),
                            ),
                            onTap: _logout,
                          ),
                        ),

                        // Spacer to push content up
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: pages[_currentIndex],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: _isDarkMode ? Colors.grey[900] : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              selectedItemColor: primaryColor,
              unselectedItemColor: Colors.grey[400],
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
              items: [
                BottomNavigationBarItem(
                  icon: _buildNavIcon(Icons.home_outlined, Icons.home, 0),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: _buildNavIcon(Icons.notifications_outlined, Icons.notifications, 1),
                  label: 'Notifications',
                ),
                BottomNavigationBarItem(
                  icon: _buildNavIcon(Icons.calendar_today_outlined, Icons.calendar_today, 2),
                  label: 'Calendar',
                ),
                BottomNavigationBarItem(
                  icon: _buildNavIcon(Icons.grade_outlined, Icons.grade, 3),
                  label: 'Grades',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Text(
        "$label: $value",
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildNavIcon(IconData outlined, IconData filled, int index) {
    bool isSelected = _currentIndex == index;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSelected ? primaryColor.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isSelected ? filled : outlined,
        size: 24,
      ),
    );
  }
}