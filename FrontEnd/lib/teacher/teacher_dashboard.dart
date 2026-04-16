import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'teacher_notifications.dart';
import 'teacher_events.dart';

class TeacherDashboard extends StatefulWidget {
  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> with TickerProviderStateMixin {
  String? selectedProgram;
  String? selectedBatch;
  String? selectedSubject;
  String? selectedDuration;
  bool isRecognitionRunning = false;
  bool isLoading = false;
  bool isVideoMuted = true;
  int totalClasses = 0;
  bool isDarkMode = false;

  // Timer related variables
  Timer? _classTimer;
  int _remainingSeconds = 0;
  String _timerDisplay = "00:00";

  // Attendance related variables
  List<Map<String, dynamic>> studentAttendance = [];
  bool isLoadingAttendance = false;
  String? _attendanceFilter; // null = all, 'present', 'absent'

  File? _profileImage;

  List<String> programs = [];
  List<String> batches = [];
  List<String> subjects = [];
  List<String> durations = ['1 minutes', '5 minutes', '10 minutes', '45 minutes', '90 minutes'];

  String? teacherName;
  String? faculty;
  String? currentSessionId;

  int _currentIndex = 0;

  VlcPlayerController? _vlcViewController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _notificationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _notificationAnimation;

  @override
  void initState() {
    super.initState();
    loadUserInfo();
    fetchPrograms();

    // Initialize animation controllers
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _notificationController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    _notificationAnimation = Tween<Offset>(
      begin: Offset(0, -1),
      end: Offset(0, 0),
    ).animate(CurvedAnimation(
      parent: _notificationController,
      curve: Curves.elasticOut,
    ));

    _fadeController.forward();
  }

  @override
  void dispose() {
    _vlcViewController?.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _notificationController.dispose();
    _classTimer?.cancel();
    super.dispose();
  }

  void _initializeVideoController() {
    try {
      _vlcViewController?.dispose();
      _vlcViewController = VlcPlayerController.network(
        'rtsp://admin:L29F8CC9@10.142.212.173:554/cam/realmonitor?channel=1&subtype=0',
        //'rtsp://admin:L29F8CC9@172.16.23.94:554/cam/realmonitor?channel=1&subtype=0',
        //'rtsp://admin:L29F8CC9@192.168.1.106:554/cam/realmonitor?channel=1&subtype=0',
        hwAcc: HwAcc.auto,
        autoPlay: true,
        options: VlcPlayerOptions(
          audio: VlcAudioOptions([
            '--audio-desync=0',
          ]),
          video: VlcVideoOptions([
            '--video-filter=',
          ]),
          advanced: VlcAdvancedOptions([
            '--no-audio', // Start muted
          ]),
        ),
      );
      // Ensure video starts muted
      _vlcViewController?.setVolume(0);
    } catch (e) {
      print('Error initializing video controller: $e');
    }
  }

  // Convert duration string to seconds
  int _parseDurationToSeconds(String duration) {
    switch (duration) {
      case '1 minutes':
        return 1 * 60;
      case '5 minutes':
        return 5 * 60;
      case '10 minutes':
        return 10 * 60;
      case '45 minutes':
        return 45 * 60;
      case '90 minutes':
        return 90 * 60;
      default:
        return 45 * 60; // Default to 45 minutes
    }
  }

  // Format seconds to MM:SS format
  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // Start the class timer
  void _startClassTimer() {
    _remainingSeconds = _parseDurationToSeconds(selectedDuration!);
    _timerDisplay = _formatTime(_remainingSeconds);

    _classTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          _timerDisplay = _formatTime(_remainingSeconds);
        } else {
          // Timer reached zero, end class automatically
          _endClassSession(isAutomatic: true);
        }
      });
    });
  }

  // Stop the class timer
  void _stopClassTimer() {
    _classTimer?.cancel();
    _classTimer = null;
  }

  Future<void> loadUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('usernames')
          .where('email', isEqualTo: user.email)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        final data = snapshot.docs.first.data();
        setState(() {
          teacherName = data['name'];
          faculty = data['faculty'];
        });
      }
    } catch (e) {
      print('Error loading user info: $e');
    }
  }

  Future<void> fetchPrograms() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('programs').get();
      if (mounted) {
        setState(() {
          programs = snapshot.docs.map((doc) => doc.id).toList();
        });
      }
    } catch (e) {
      print('Error fetching programs: $e');
    }
  }

  Future<void> fetchBatches(String program) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('programs')
          .doc(program)
          .collection('batches')
          .get();
      if (mounted) {
        setState(() {
          batches = snapshot.docs.map((doc) => doc.id).toList();
        });
      }
    } catch (e) {
      print('Error fetching batches: $e');
    }
  }

  Future<void> fetchSubjects(String program, String batch) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('programs')
          .doc(program)
          .collection('batches')
          .doc(batch)
          .get();

      final courseData = doc.data()?['courses'] ?? [];
      List<String> subjectList = [];

      for (var course in courseData) {
        if (course['subject'] != null) {
          subjectList.add(course['subject']);
        }
      }

      if (mounted) {
        setState(() {
          subjects = subjectList;
        });
      }
    } catch (e) {
      print('Error fetching subjects: $e');
    }
  }

  Future<void> pickProfileImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null && mounted) {
        setState(() {
          _profileImage = File(picked.path);
        });
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  Future<void> incrementClassCountAndNotify() async {
    try {
      final docId = '$selectedBatch-$selectedProgram-$selectedSubject';
      final docRef = FirebaseFirestore.instance.collection('subjectClasses').doc(docId);

      final snapshot = await docRef.get();
      if (snapshot.exists) {
        await docRef.update({'totalClasses': FieldValue.increment(1)});
      } else {
        await docRef.set({'totalClasses': 1});
      }

      final updatedDoc = await docRef.get();
      if (mounted) {
        setState(() {
          totalClasses = updatedDoc['totalClasses'] ?? 0;
        });
      }

      await sendNotification();
    } catch (e) {
      print('Error incrementing class count: $e');
    }
  }

  Future<void> sendNotification() async {
    try {
      final now = TimeOfDay.now();
      final time = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";

      final payload = {
        'teacherName': teacherName,
        'subject': selectedSubject,
        'batch': selectedBatch,
        'program': selectedProgram,
        'startTime': time,
        'totalClasses': totalClasses.toString(),
      };

      final url = Uri.parse("https://your-api-endpoint.com/sendClassNotification");

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        print("Notification sent.");
      } else {
        print("Failed to send notification: ${response.body}");
      }
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  // Send POST request to Flask backend for face recognition
  Future<void> sendFaceRecognitionRequest() async {
    try {
      final now = DateTime.now();
      final payload = {
        'teacherName': teacherName, // Match Flask backend field names
        'selectedBatch': selectedBatch,
        'selectedProgram': selectedProgram,
        'selectedSubject': selectedSubject,
        'classDuration': selectedDuration,
        'createdAt': now.toIso8601String(),
        'timestamp': now.toIso8601String(),
      };

      // Update URL to match your Flask backend (port 5050)
      //final url = Uri.parse("http://192.168.1.102:5050/start_class");
      //final url = Uri.parse("http://172.16.22.153:5050/start_class");
      final url = Uri.parse("http://10.142.212.157:5050/start_class");

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print("Face recognition started successfully: ${responseData['message']}");
        _showSnackBar("Face recognition started successfully!", Colors.green);
      } else {
        final responseData = jsonDecode(response.body);
        print("Failed to start face recognition: ${responseData['message']}");
        _showSnackBar("Face recognition failed: ${responseData['message']}", Colors.orange);
      }
    } catch (e) {
      print('Error sending face recognition request: $e');
      _showSnackBar("Face recognition request failed - continuing with class", Colors.orange);
      // Continue with class session even if face recognition fails
    }
  }

  // Fetch student attendance from Firebase
  Future<void> fetchStudentAttendance() async {
    if (selectedProgram == null || selectedBatch == null || selectedSubject == null) {
      _showSnackBar("Please select program, batch, and subject first", Colors.orange);
      return;
    }

    setState(() {
      isLoadingAttendance = true;
    });

    try {
      print('Fetching attendance for: $selectedProgram, $selectedBatch, $selectedSubject');

      // First, try to fetch from attendance collection
      QuerySnapshot attendanceSnapshot;

      try {
        attendanceSnapshot = await FirebaseFirestore.instance
            .collection('attendance')
            .where('selectedProgram', isEqualTo: selectedProgram)
            .where('selectedBatch', isEqualTo: selectedBatch)
            .where('selectedSubject', isEqualTo: selectedSubject)
            .get();
      } catch (e) {
        print('Error with compound query, trying simpler approach: $e');
        // If compound query fails, try a simpler approach
        attendanceSnapshot = await FirebaseFirestore.instance
            .collection('attendance')
            .get();
      }

      List<Map<String, dynamic>> attendanceList = [];

      print('Found ${attendanceSnapshot.docs.length} attendance documents');

      for (var doc in attendanceSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        print('Document data: $data');

        // Filter manually if needed
        if (data['selectedProgram'] == selectedProgram &&
            data['selectedBatch'] == selectedBatch &&
            data['selectedSubject'] == selectedSubject) {

          bool isPresent = false;
          var statusField = data['status'];

          // Handle different status formats
          if (statusField is bool) {
            isPresent = statusField;
          } else if (statusField is String) {
            isPresent = statusField.toLowerCase() == 'present' || statusField.toLowerCase() == 'true';
          }

          attendanceList.add({
            'student_name': data['student_name']?.toString() ?? 'Unknown',
            'student_id': data['roll_no']?.toString() ?? 'N/A',
            'status': isPresent ? 'present' : 'absent',
            'timestamp': data['timestamp'],
            'recognition_count': data['recognition_count'] ?? 0,
          });
        }
      }

      // Calculate attendance count per student for this subject
      Map<String, int> studentAttendanceCount = {};
      for (var record in attendanceList) {
        String studentName = record['student_name'];
        if (record['status'] == 'present') {
          studentAttendanceCount[studentName] = (studentAttendanceCount[studentName] ?? 0) + 1;
        }
      }

      // If no attendance records found, try to fetch all students for the class
      if (attendanceList.isEmpty) {
        print('No attendance records found, fetching student list...');
        await _fetchStudentList();
        return;
      }

      // Remove duplicates (keep only the latest record for each student) and add attendance count
      Map<String, Map<String, dynamic>> uniqueStudents = {};
      for (var student in attendanceList) {
        String studentName = student['student_name'];
        if (!uniqueStudents.containsKey(studentName) ||
            (student['timestamp'] != null && uniqueStudents[studentName]!['timestamp'] != null)) {
          student['classes_attended'] = studentAttendanceCount[studentName] ?? 0;
          uniqueStudents[studentName] = student;
        }
      }

      setState(() {
        studentAttendance = uniqueStudents.values.toList();
        isLoadingAttendance = false;
      });

      print('Processed ${studentAttendance.length} unique students');

      if (studentAttendance.isEmpty) {
        _showSnackBar("No attendance records found for this class", Colors.orange);
        // Still show the dialog with empty state
        _showAttendanceDialog();
      } else {
        _showAttendanceDialog();
      }
    } catch (e) {
      print('Error fetching attendance: $e');
      setState(() {
        isLoadingAttendance = false;
      });
      _showSnackBar("Failed to fetch attendance: ${e.toString()}", Colors.red);
    }
  }

  // Fetch student list if no attendance records exist
  Future<void> _fetchStudentList() async {
    try {
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('student_programs')
          .doc(selectedProgram)
          .collection('batches')
          .doc(selectedBatch)
          .collection('students')
          .get();

      List<Map<String, dynamic>> studentList = [];

      for (var doc in studentsSnapshot.docs) {
        final data = doc.data();
        studentList.add({
          'student_name': doc.id,
          'student_id': data['rollNo']?.toString() ?? 'N/A',
          'status': 'absent', // Default to absent if no attendance record
          'timestamp': null,
          'recognition_count': 0,
          'classes_attended': 0, // No classes attended yet
        });
      }

      setState(() {
        studentAttendance = studentList;
        isLoadingAttendance = false;
      });

      if (studentList.isNotEmpty) {
        _showSnackBar("Showing all students (no attendance records found)", Colors.blue);
        _showAttendanceDialog();
      } else {
        _showSnackBar("No students found for this class", Colors.orange);
      }
    } catch (e) {
      print('Error fetching student list: $e');
      setState(() {
        isLoadingAttendance = false;
      });
      _showSnackBar("Failed to fetch student list: ${e.toString()}", Colors.red);
    }
  }

  // Show floating notification
  void _showFloatingNotification(String message) {
    _notificationController.forward().then((_) {
      Timer(Duration(seconds: 3), () {
        if (mounted) {
          _notificationController.reverse();
        }
      });
    });
  }

  Future<void> startClassSession() async {
    if (selectedProgram == null ||
        selectedBatch == null ||
        selectedSubject == null ||
        selectedDuration == null) {
      _showSnackBar("Please select all fields first", Colors.orange);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Create session data
      final sessionData = {
        'teacherName': teacherName,
        'selectedBatch': selectedBatch,
        'selectedProgram': selectedProgram,
        'selectedSubject': selectedSubject,
        'classDuration': selectedDuration,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'active',
      };

      // Add to Firestore and get session ID
      final docRef = await FirebaseFirestore.instance
          .collection('class_sessions')
          .add(sessionData);

      currentSessionId = docRef.id;

      setState(() {
        isRecognitionRunning = true;
      });

      _pulseController.repeat(reverse: true);
      _startClassTimer(); // Start the timer
      await incrementClassCountAndNotify();
      await sendFaceRecognitionRequest(); // Send face recognition request

      _showSnackBar("Class session started successfully!", Colors.green);
    } catch (e) {
      print('Error starting class session: $e');
      _showSnackBar("Failed to start class session", Colors.red);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // End class session (only automatic when timer expires)
  Future<void> _endClassSession({bool isAutomatic = false}) async {
    try {
      // Update session status in Firestore
      if (currentSessionId != null) {
        await FirebaseFirestore.instance
            .collection('class_sessions')
            .doc(currentSessionId)
            .update({
          'status': 'completed',
          'endTime': DateTime.now().toIso8601String(),
          'endedAutomatically': isAutomatic,
        });
      }

      setState(() {
        isRecognitionRunning = false;
        isVideoMuted = true;
      });

      _vlcViewController?.setVolume(0);
      _pulseController.stop();
      _pulseController.reset();
      _stopClassTimer();

      // Show floating notification
      String message = "Class session ended automatically (timer expired)";
      _showFloatingNotification(message);

      _showSnackBar(message, Colors.orange);
    } catch (e) {
      print('Error ending class session: $e');
    }
  }

  void toggleVideoSound() {
    setState(() {
      isVideoMuted = !isVideoMuted;
    });

    if (_vlcViewController != null) {
      _vlcViewController!.setVolume(isVideoMuted ? 0 : 100);
    }

    _showSnackBar(
        isVideoMuted ? "Video muted" : "Video unmuted",
        isVideoMuted ? Colors.orange : Colors.green
    );
  }

  // Show attendance dialog
  void _showAttendanceDialog() {
    // Calculate attendance statistics
    int totalStudents = studentAttendance.length;
    int presentStudents = studentAttendance.where((s) => s['status'] == 'present').length;
    int absentStudents = totalStudents - presentStudents;
    double attendancePercentage = totalStudents > 0 ? (presentStudents / totalStudents) * 100 : 0;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? Color(0xFF1F1F1F) : Color(0xFF1a6b99),
          title: Column(
            children: [
              Text(
                'Student Attendance',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildAttendanceStatItem('Total', totalStudents.toString(), Colors.blue),
                    _buildAttendanceStatItem('Present', presentStudents.toString(), Colors.green),
                    _buildAttendanceStatItem('Absent', absentStudents.toString(), Colors.red),
                    _buildAttendanceStatItem('Rate', '${attendancePercentage.toStringAsFixed(1)}%', Colors.orange),
                  ],
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            height: 400,
            child: studentAttendance.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.white54),
                  SizedBox(height: 16),
                  Text(
                    'No attendance data available',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start a class session to record attendance',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            )
                : Column(
              children: [
                // Filter buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildFilterButton('All', null),
                    _buildFilterButton('Present', 'present'),
                    _buildFilterButton('Absent', 'absent'),
                  ],
                ),
                SizedBox(height: 12),
                // Student list
                Expanded(
                  child: ListView.builder(
                    itemCount: _getFilteredStudents().length,
                    itemBuilder: (context, index) {
                      final student = _getFilteredStudents()[index];
                      final isPresent = student['status'] == 'present';
                      final recognitionCount = student['recognition_count'] ?? 0;
                      final classesAttended = student['classes_attended'] ?? 0;

                      return Card(
                        color: Colors.white.withOpacity(isPresent ? 0.15 : 0.08),
                        margin: EdgeInsets.symmetric(vertical: 2),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPresent ? Colors.green : Colors.red,
                            child: Icon(
                              isPresent ? Icons.check : Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            student['student_name'],
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Roll No: ${student['student_id']}',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                'Classes Attended: $classesAttended/$totalClasses',
                                style: TextStyle(
                                  color: classesAttended > 0 ? Colors.lightBlueAccent : Colors.white60,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (recognitionCount > 0)
                                Text(
                                  'Today Detected: $recognitionCount/5 times',
                                  style: TextStyle(color: Colors.white60, fontSize: 10),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isPresent ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isPresent ? 'Present' : 'Absent',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (classesAttended > 0) ...[
                                SizedBox(height: 4),
                                Text(
                                  '${((classesAttended / totalClasses) * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (studentAttendance.isNotEmpty)
              TextButton.icon(
                onPressed: () => _refreshAttendance(),
                icon: Icon(Icons.refresh, color: Colors.white, size: 18),
                label: Text('Refresh', style: TextStyle(color: Colors.white)),
              ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close, color: Colors.white, size: 18),
              label: Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // Build filter button
  Widget _buildFilterButton(String label, String? filter) {
    bool isSelected = _attendanceFilter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          _attendanceFilter = filter;
        });
        Navigator.of(context).pop(); // Close dialog
        _showAttendanceDialog(); // Reopen with filter applied
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // Get filtered students based on current filter
  List<Map<String, dynamic>> _getFilteredStudents() {
    if (_attendanceFilter == null) {
      return studentAttendance;
    }
    return studentAttendance.where((student) => student['status'] == _attendanceFilter).toList();
  }

  // Build attendance stat item
  Widget _buildAttendanceStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // Refresh attendance data
  void _refreshAttendance() {
    Navigator.of(context).pop(); // Close dialog
    fetchStudentAttendance(); // Fetch fresh data
  }

  Widget buildGradientDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonFormField<T>(
        value: value,
        hint: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              "Select $label",
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, color: Colors.white),
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        dropdownColor: isDarkMode ? Color(0xFF2F2F2F) : Color(0xFF2090cc),
        items: items
            .map((item) => DropdownMenuItem<T>(
          value: item,
          child: Text(
            item.toString(),
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ))
            .toList(),
        onChanged: onChanged,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget buildCCTVFrame() {
    final isFeedAvailable =
        selectedProgram == "Computer Engineering" && selectedBatch == "2022";

    // Initialize video controller when valid selection is made
    if (isFeedAvailable && _vlcViewController == null) {
      _initializeVideoController();
    } else if (!isFeedAvailable && _vlcViewController != null) {
      _vlcViewController?.dispose();
      _vlcViewController = null;
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isRecognitionRunning ? _pulseAnimation.value : 1.0,
          child: Container(
            width: double.infinity,
            height: 220,
            margin: EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.05)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isRecognitionRunning ? Colors.green : Colors.white.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isRecognitionRunning
                      ? Colors.green.withOpacity(0.3)
                      : Colors.black.withOpacity(0.2),
                  blurRadius: isRecognitionRunning ? 20 : 10,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: isFeedAvailable && _vlcViewController != null
                  ? Stack(
                children: [
                  VlcPlayer(
                    controller: _vlcViewController!,
                    aspectRatio: 16 / 9,
                    placeholder: Container(
                      color: Colors.black87,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Loading Camera Feed...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isRecognitionRunning) ...[
                    // Timer display in top-left corner
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              _timerDisplay,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Live indicator in top-right corner
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Mute/Unmute button in bottom-left corner
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: GestureDetector(
                        onTap: toggleVideoSound,
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            isVideoMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              )
                  : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_off,
                      size: 48,
                      color: Colors.white70,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "NO CCTV FEED AVAILABLE",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Select Computer Engineering - 2022 for live feed",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildControlButtons() {
    return Column(
      children: [
        // Start Class Button (only show when not running)
        if (!isRecognitionRunning)
          Container(
            width: double.infinity,
            height: 60,
            margin: EdgeInsets.symmetric(vertical: 8),
            child: ElevatedButton.icon(
              icon: isLoading
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2,
                ),
              )
                  : Icon(Icons.play_circle_fill, size: 28),
              label: Text(
                isLoading ? "Starting..." : "Start Class Session",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: Colors.green.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: isLoading ? null : startClassSession,
            ),
          ),

        // View Attendance Button (show when program, batch, subject are selected)
        if (selectedProgram != null && selectedBatch != null && selectedSubject != null)
          Container(
            width: double.infinity,
            height: 50,
            margin: EdgeInsets.symmetric(vertical: 4),
            child: ElevatedButton.icon(
              icon: isLoadingAttendance
                  ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2,
                ),
              )
                  : Icon(Icons.people, size: 24),
              label: Text(
                isLoadingAttendance ? "Loading..." : "View Attendance",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                elevation: 6,
                shadowColor: Colors.blue.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              onPressed: isLoadingAttendance ? null : fetchStudentAttendance,
            ),
          ),
      ],
    );
  }

  Widget buildStatsCard() {
    // Calculate attendance statistics
    int totalStudents = studentAttendance.length;
    int presentStudents = studentAttendance.where((s) => s['status'] == 'present').length;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      margin: EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withOpacity(0.08)
            : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.school, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                "Class Statistics",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem("Total Classes", totalClasses.toString(), Icons.class_),
              _buildStatItem("Status", isRecognitionRunning ? "Active" : "Inactive",
                  isRecognitionRunning ? Icons.circle : Icons.circle_outlined),
              if (isRecognitionRunning)
                _buildStatItem("Time Left", _timerDisplay, Icons.timer)
              else if (totalStudents > 0)
                _buildStatItem("Present", "$presentStudents/$totalStudents", Icons.people),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // Floating notification widget
  Widget buildFloatingNotification() {
    return SlideTransition(
      position: _notificationAnimation,
      child: Container(
        margin: EdgeInsets.all(16),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade700,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.info, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "Class session has ended",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(Icons.check_circle, color: Colors.white, size: 24),
          ],
        ),
      ),
    );
  }

  Widget buildDashboard() {
    final isVideoAllowed =
        selectedProgram == "Computer Engineering" && selectedBatch == "2022";

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Color(0xFF121212) : Color(0xFF2090cc),
      ),
      child: Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Class Management",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Configure your class settings below",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(height: 24),

                  buildGradientDropdown<String>(
                    label: "Program",
                    value: selectedProgram,
                    items: programs,
                    icon: Icons.school,
                    onChanged: (val) {
                      setState(() {
                        selectedProgram = val;
                        selectedBatch = null;
                        selectedSubject = null;
                        batches = [];
                        subjects = [];
                      });
                      if (val != null) fetchBatches(val);
                    },
                  ),

                  if (selectedProgram != null)
                    buildGradientDropdown<String>(
                      label: "Batch",
                      value: selectedBatch,
                      items: batches,
                      icon: Icons.group,
                      onChanged: (val) {
                        setState(() {
                          selectedBatch = val;
                          selectedSubject = null;
                          subjects = [];
                        });
                        if (val != null) fetchSubjects(selectedProgram!, val);
                      },
                    ),

                  if (selectedBatch != null)
                    buildGradientDropdown<String>(
                      label: "Subject",
                      value: selectedSubject,
                      items: subjects,
                      icon: Icons.book,
                      onChanged: (val) => setState(() {
                        selectedSubject = val;
                      }),
                    ),

                  if (selectedSubject != null)
                    buildGradientDropdown<String>(
                      label: "Class Duration",
                      value: selectedDuration,
                      items: durations,
                      icon: Icons.schedule,
                      onChanged: (val) => setState(() {
                        selectedDuration = val;
                      }),
                    ),

                  SizedBox(height: 16),

                  Text(
                    "Live Camera Feed",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  buildCCTVFrame(),

                  if (isVideoAllowed) ...[
                    buildControlButtons(),
                    buildStatsCard(),
                  ] else if (selectedProgram != null && selectedBatch != null) ...[
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      margin: EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.orange.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.white),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "No Camera Feed Available for this selection",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
          // Floating notification overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: buildFloatingNotification(),
          ),
        ],
      ),
    );
  }

  Widget buildComingSoonPage(String title, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Color(0xFF121212) : Color(0xFF2090cc),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Coming Soon",
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      buildDashboard(),
      TeacherNotifications(),
      TeacherEvents(), // ← replace this line
    ];


    return MaterialApp(
      theme: isDarkMode
          ? ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Color(0xFF121212),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF1F1F1F),
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1F1F1F),
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: Color(0xFF1F1F1F),
        ),
      )
          : ThemeData.light().copyWith(
        scaffoldBackgroundColor: Color(0xFF2090cc),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF1a6b99),
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1a6b99),
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: Color(0xFF1a6b99),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: isDarkMode ? Color(0xFF121212) : Color(0xFF2090cc),
        appBar: AppBar(
          title: Row(
            children: [
              Icon(Icons.school, color: Colors.white),
              SizedBox(width: 8),
              Text(
                "Vedasync Teacher",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          backgroundColor: isDarkMode ? Color(0xFF1F1F1F) : Color(0xFF1a6b99),
          elevation: 0,
        ),
        drawer: Drawer(
          child: Container(
            decoration: BoxDecoration(
              color: isDarkMode ? Color(0xFF1F1F1F) : Color(0xFF1a6b99),
            ),
            child: ListView(
              children: [
                UserAccountsDrawerHeader(
                  decoration: BoxDecoration(
                    color: isDarkMode ? Color(0xFF000000) : Color(0xFF145680),
                  ),
                  accountName: Text(
                    teacherName ?? 'Loading...',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  accountEmail: Text(
                    faculty != null ? 'Faculty: $faculty' : '',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  currentAccountPicture: GestureDetector(
                    onTap: pickProfileImage,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: CircleAvatar(
                        backgroundImage: _profileImage != null
                            ? FileImage(_profileImage!)
                            : null,
                        child: _profileImage == null
                            ? const Icon(Icons.person, size: 40, color: Colors.white)
                            : null,
                        backgroundColor: isDarkMode ? Color(0xFF424242) : Color(0xFF2090cc),
                      ),
                    ),
                  ),
                ),
                SwitchListTile(
                  title: Row(
                    children: [
                      Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode, color: Colors.white),
                      SizedBox(width: 12),
                      Text(
                        "Dark Mode",
                        style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
                      ),
                    ],
                  ),
                  value: isDarkMode,
                  activeColor: Colors.white,
                  onChanged: (val) => setState(() => isDarkMode = val),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    "Logout",
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.red,
                    ),
                  ),
                  onTap: () async {
                    try {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacementNamed('/');
                      }
                    } catch (e) {
                      print('Error signing out: $e');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        body: pages[_currentIndex],
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDarkMode ? Color(0xFF1F1F1F) : Color(0xFF1a6b99),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white60,
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: "Home",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.notifications),
                label: "Notifications",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.event),
                label: "Events",
              ),
            ],
          ),
        ),
      ),
    );
  }
}