import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

class StudentCalendar extends StatefulWidget {
  const StudentCalendar({super.key});

  @override
  State<StudentCalendar> createState() => _StudentCalendarState();
}

class _StudentCalendarState extends State<StudentCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  bool _isDarkMode = false;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  final Color primaryColor = const Color(0xFF3593D1);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  Map<String, dynamic>? _studentProfile;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStudentProfile();
  }

  Future<void> _loadStudentProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Use the same query as StudentDashboard - fetch from 'usernames' collection
      final QuerySnapshot snapshot = await _firestore
          .collection('usernames')
          .where('email', isEqualTo: user.email)
          .get();

      if (snapshot.docs.isEmpty) {
        throw Exception('Student profile not found. Please make sure your account is properly set up.');
      }

      final studentData = snapshot.docs.first.data() as Map<String, dynamic>;

      // Validate required fields
      if (studentData['batch'] == null || studentData['program'] == null) {
        throw Exception('Student batch or program not set in profile. Please contact administrator.');
      }

      setState(() {
        _studentProfile = {
          'name': studentData['name'] ?? 'Student',
          'batch': studentData['batch'],
          'program': studentData['program'],
          'email': studentData['email'],
        };
      });

      // Debug: Print student profile data
      print('Student Profile loaded:');
      print('Name: ${_studentProfile!['name']}');
      print('Batch: "${_studentProfile!['batch']}"');
      print('Program: "${_studentProfile!['program']}"');
      print('Email: ${_studentProfile!['email']}');

      await _loadEvents();
    } catch (error) {
      print('Error loading student profile: $error');
      setState(() {
        _errorMessage = 'Error loading profile: ${_getUserFriendlyError(error)}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadEvents() async {
    if (_studentProfile == null) return;

    try {
      final String studentBatch = _studentProfile!['batch'] ?? '';
      final String studentProgram = _studentProfile!['program'] ?? '';

      if (studentBatch.isEmpty || studentProgram.isEmpty) {
        throw Exception('Student batch or program not set in profile');
      }

      print('Loading events for batch: $studentBatch, program: $studentProgram');

      // Get all events first and then filter manually
      QuerySnapshot snapshot = await _firestore.collection('events').get();

      print('Total events in database: ${snapshot.docs.length}');

      // Debug: Print first few events to see their structure
      for (int i = 0; i < snapshot.docs.length && i < 3; i++) {
        final data = snapshot.docs[i].data() as Map<String, dynamic>;
        print('Event $i: batch="${data['batch']}", program="${data['program']}"');
      }

      // Filter events by batch and program with flexible matching
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final eventBatch = data['batch'] ?? '';
        final eventProgram = data['program'] ?? '';

        // Try exact match first
        bool batchMatch = eventBatch == studentBatch;
        bool programMatch = eventProgram == studentProgram;

        // If exact match fails, try flexible matching
        if (!batchMatch) {
          // Try matching "Batch 2022" with "2022" or vice versa
          batchMatch = eventBatch.toLowerCase().contains(studentBatch.toLowerCase()) ||
              studentBatch.toLowerCase().contains(eventBatch.toLowerCase()) ||
              eventBatch.replaceAll('batch ', '').toLowerCase() == studentBatch.toLowerCase() ||
              studentBatch.replaceAll('batch ', '').toLowerCase() == eventBatch.toLowerCase();
        }

        if (!programMatch) {
          // Try case-insensitive program matching
          programMatch = eventProgram.toLowerCase() == studentProgram.toLowerCase();
        }

        print('Event batch: "$eventBatch", student batch: "$studentBatch", match: $batchMatch');
        print('Event program: "$eventProgram", student program: "$studentProgram", match: $programMatch');

        return batchMatch && programMatch;
      }).toList();

      _updateEventsFromDocs(filteredDocs);

      print('Loaded ${filteredDocs.length} matching events');

      if (filteredDocs.isEmpty) {
        print('No matching events found. Student batch: "$studentBatch", Student program: "$studentProgram"');
        // Show available batches and programs for debugging
        final uniqueBatches = snapshot.docs.map((doc) => (doc.data() as Map<String, dynamic>)['batch']).toSet();
        final uniquePrograms = snapshot.docs.map((doc) => (doc.data() as Map<String, dynamic>)['program']).toSet();
        print('Available batches: $uniqueBatches');
        print('Available programs: $uniquePrograms');
      }

    } catch (error) {
      print('Error loading events: $error');
      setState(() {
        _errorMessage = 'Error loading events: ${_getUserFriendlyError(error)}';
      });
    }
  }

  Future<void> _refreshEvents() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      await _loadEvents();
      _showSuccessSnackbar('Events refreshed!');
    } catch (error) {
      _showErrorSnackbar('Error refreshing events: ${_getUserFriendlyError(error)}');
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _updateEventsFromDocs(List<QueryDocumentSnapshot> docs) {
    final Map<DateTime, List<Map<String, dynamic>>> events = {};

    for (var doc in docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;

        // Handle different date formats
        DateTime eventDate;
        final dateField = data['date'];

        if (dateField is Timestamp) {
          eventDate = dateField.toDate();
        } else if (dateField is String) {
          try {
            eventDate = DateTime.parse(dateField);
          } catch (e) {
            // Try different date formats
            try {
              eventDate = DateFormat('yyyy-MM-dd').parse(dateField);
            } catch (e2) {
              try {
                eventDate = DateFormat('dd/MM/yyyy').parse(dateField);
              } catch (e3) {
                print('Could not parse date: $dateField');
                continue; // Skip this event if date can't be parsed
              }
            }
          }
        } else {
          print('Unknown date format for event: ${doc.id}');
          continue; // Skip this event
        }

        final normalizedDate = DateTime(eventDate.year, eventDate.month, eventDate.day);

        if (events[normalizedDate] == null) {
          events[normalizedDate] = [];
        }

        events[normalizedDate]!.add({
          'id': doc.id,
          'title': data['title'] ?? data['eventTitle'] ?? 'Event',
          'description': data['description'] ?? data['eventDescription'] ?? '',
          'time': data['time'] ?? data['eventTime'] ?? '',
          'date': dateField,
          'batch': data['batch'] ?? '',
          'program': data['program'] ?? '',
          'teacherName': data['teacherName'] ?? data['createdBy'] ?? '',
          'createdAt': data['createdAt'],
        });
      } catch (e) {
        print('Error processing event ${doc.id}: $e');
        continue;
      }
    }

    if (mounted) {
      setState(() {
        _events = events;
        _errorMessage = null;
      });
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    List<Map<String, dynamic>> dayEvents = _events[normalizedDay] ?? [];

    // Sort by time
    dayEvents.sort((a, b) {
      final timeA = a['time'] ?? '';
      final timeB = b['time'] ?? '';
      if (timeA.isEmpty && timeB.isEmpty) return 0;
      if (timeA.isEmpty) return 1;
      if (timeB.isEmpty) return -1;
      return timeA.compareTo(timeB);
    });

    return dayEvents;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _isDarkMode ? _darkTheme() : _lightTheme(),
      child: Scaffold(
        backgroundColor: _isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
        appBar: AppBar(
          title: const Text('My Events Calendar'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
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
              onPressed: _isRefreshing ? null : _refreshEvents,
              tooltip: 'Refresh Events',
            ),
            IconButton(
              icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () {
                setState(() {
                  _isDarkMode = !_isDarkMode;
                });
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshEvents,
          color: primaryColor,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your events...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isDarkMode ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadStudentProfile,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_studentProfile != null) _buildStudentInfo(),
        _buildCalendar(),
        const SizedBox(height: 8.0),
        Expanded(child: _buildEventsList()),
      ],
    );
  }

  Widget _buildStudentInfo() {
    final batch = _studentProfile!['batch'] ?? 'Unknown';
    final program = _studentProfile!['program'] ?? 'Unknown';
    final name = _studentProfile!['name'] ?? 'Student';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: primaryColor,
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.group, size: 14, color: primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      '$batch - $program',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isDarkMode ? Colors.white70 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${_getTotalEventsCount()} Events',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  int _getTotalEventsCount() {
    return _events.values.fold(0, (total, dayEvents) => total + dayEvents.length);
  }

  Widget _buildCalendar() {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);

    return TableCalendar<Map<String, dynamic>>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      calendarFormat: _calendarFormat,
      eventLoader: _getEventsForDay,
      startingDayOfWeek: StartingDayOfWeek.sunday,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        if (!isSameDay(_selectedDay, selectedDay)) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        }
      },
      onFormatChanged: (format) {
        if (_calendarFormat != format) {
          setState(() => _calendarFormat = format);
        }
      },
      onPageChanged: (focusedDay) => _focusedDay = focusedDay,
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: primaryColor.withOpacity(0.3),
          shape: BoxShape.circle,
          border: Border.all(color: primaryColor, width: 2),
        ),
        todayTextStyle: TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
        selectedDecoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
        selectedTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        defaultTextStyle: TextStyle(color: _isDarkMode ? Colors.white : Colors.black87),
        outsideTextStyle: TextStyle(color: _isDarkMode ? Colors.white30 : Colors.grey),
        markerDecoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
        markerSize: 6.0,
        markerMargin: const EdgeInsets.symmetric(horizontal: 0.3),
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: true,
        titleCentered: true,
        formatButtonDecoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(12.0)),
        formatButtonTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildEventsList() {
    final selectedEvents = _getEventsForDay(_selectedDay ?? DateTime.now());

    if (selectedEvents.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.3,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_busy,
                  size: 64,
                  color: _isDarkMode ? Colors.white30 : Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No events for this day',
                  style: TextStyle(
                    color: _isDarkMode ? Colors.white70 : Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                if (_studentProfile != null)
                  Text(
                    'Events for ${_studentProfile!['batch']} - ${_studentProfile!['program']}',
                    style: TextStyle(
                      color: _isDarkMode ? Colors.white60 : Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _refreshEvents,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Events'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: selectedEvents.length,
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      itemBuilder: (context, index) => _buildEventCard(selectedEvents[index]),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    Color? cardColor;
    final now = DateTime.now();

    // Handle different date formats for event date
    DateTime? eventDate;
    final dateField = event['date'];

    if (dateField is Timestamp) {
      eventDate = dateField.toDate();
    } else if (dateField is String) {
      try {
        eventDate = DateTime.parse(dateField);
      } catch (e) {
        try {
          eventDate = DateFormat('yyyy-MM-dd').parse(dateField);
        } catch (e2) {
          try {
            eventDate = DateFormat('dd/MM/yyyy').parse(dateField);
          } catch (e3) {
            // Unable to parse date
          }
        }
      }
    }

    final isToday = eventDate != null ? isSameDay(eventDate, now) : false;
    final eventTime = event['time'] ?? '';

    // Highlight upcoming events
    if (isToday && eventTime.isNotEmpty) {
      final currentHour = now.hour;
      final timeRegex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
      final timeMatch = timeRegex.firstMatch(eventTime);

      if (timeMatch != null) {
        int eventHour = int.parse(timeMatch.group(1)!);
        final amPm = timeMatch.group(3)!.toUpperCase();

        if (amPm == 'PM' && eventHour != 12) eventHour += 12;
        if (amPm == 'AM' && eventHour == 12) eventHour = 0;

        final timeDifference = eventHour - currentHour;
        if (timeDifference <= 2 && timeDifference >= 0) {
          cardColor = Colors.orange.withOpacity(0.1);
        }
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      elevation: 2,
      color: cardColor ?? (_isDarkMode ? Colors.grey[800] : Colors.white),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: primaryColor.withOpacity(0.2),
          child: Text(
            (event['title'] ?? 'E').substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          event['title'] ?? 'No Title',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event['time'] != null && event['time'].isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    event['time'],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ],
            if (event['teacherName'] != null && event['teacherName'].isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    'by ${event['teacherName']}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isDarkMode ? Colors.white60 : Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        children: [
          if (event['description'] != null && event['description'].isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  event['description'],
                  style: TextStyle(
                    color: _isDarkMode ? Colors.white70 : Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ThemeData _lightTheme() => ThemeData(
    brightness: Brightness.light,
    primaryColor: primaryColor,
    colorScheme: ColorScheme.light(
      primary: primaryColor,
      secondary: primaryColor.withOpacity(0.7),
    ),
  );

  ThemeData _darkTheme() => ThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    colorScheme: ColorScheme.dark(
      primary: primaryColor,
      secondary: primaryColor.withOpacity(0.7),
    ),
  );

  String _getUserFriendlyError(dynamic error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You don\'t have permission to access this data';
        case 'not-found':
          return 'Your profile was not found. Please contact administrator';
        case 'invalid-argument':
          return 'Invalid data in your profile';
        case 'unavailable':
          return 'Network connection unavailable';
        default:
          return 'An error occurred (${error.code})';
      }
    }
    return error.toString();
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccessSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}