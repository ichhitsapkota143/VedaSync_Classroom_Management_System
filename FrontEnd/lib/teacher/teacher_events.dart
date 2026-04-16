import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'teacher_dashboard.dart';
import 'teacher_notifications.dart';

class TeacherEvents extends StatefulWidget {
  const TeacherEvents({super.key});

  @override
  State<TeacherEvents> createState() => _TeacherEventsState();
}

class _TeacherEventsState extends State<TeacherEvents> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  bool _isDarkMode = false;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  String _filterBatch = 'All';
  String _filterProgram = 'All';
  int _currentIndex = 2; // Events tab is at index 2

  final Color primaryColor = const Color(0xFF3593D1);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final List<String> batches = ['All', 'Batch 2020', 'Batch 2021', 'Batch 2022', 'Batch 2023', 'Batch 2024'];
  final List<String> programs = [
    'All',
    'Computer Engineering',
    'Information Technology',
    'Electronics & Communication',
    'Civil Engineering',
    'Business Administration',
    'Architecture',
  ];

  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _isLoading = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('events')
          .orderBy('createdAt', descending: false)
          .get();

      _updateEventsFromSnapshot(snapshot);
    } catch (error) {
      _showErrorSnackbar('Error fetching events: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshEvents() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('events')
          .orderBy('createdAt', descending: false)
          .get();

      _updateEventsFromSnapshot(snapshot);
      _showSuccessSnackbar('Events refreshed!');
    } catch (error) {
      _showErrorSnackbar('Error refreshing events: $error');
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _updateEventsFromSnapshot(QuerySnapshot snapshot) {
    final Map<DateTime, List<Map<String, dynamic>>> events = {};
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final dateStr = data['date'] as String;
      final eventDate = DateTime.parse(dateStr);
      final normalizedDate = DateTime(eventDate.year, eventDate.month, eventDate.day);

      if (events[normalizedDate] == null) {
        events[normalizedDate] = [];
      }
      events[normalizedDate]!.add({
        'id': doc.id,
        ...data,
      });
    }
    if (mounted) {
      setState(() {
        _events = events;
      });
    }
  }

  void _navigateToPage(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>  TeacherDashboard(),
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(-1.0, 0.0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              );
            },
          ),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const TeacherNotifications(),
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(-1.0, 0.0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              );
            },
          ),
        );
        break;
      case 2:
      // Already on Events page, no navigation needed
        break;
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    List<Map<String, dynamic>> dayEvents = _events[normalizedDay] ?? [];

    // Apply filters
    if (_filterBatch != 'All') {
      dayEvents = dayEvents.where((event) => event['batch'] == _filterBatch).toList();
    }
    if (_filterProgram != 'All') {
      dayEvents = dayEvents.where((event) => event['program'] == _filterProgram).toList();
    }

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
          title: const Text('Teacher Events Calendar'),
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
              icon: const Icon(Icons.filter_list),
              onPressed: _showFilterDialog,
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
          child: Column(
            children: [
              if (_filterBatch != 'All' || _filterProgram != 'All') _buildFilterChips(),
              _buildCalendar(),
              const SizedBox(height: 8.0),
              Expanded(child: _buildEventsList()),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            final selectedDate = _selectedDay ?? DateTime.now();
            final today = DateTime.now();
            final normalizedSelectedDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
            final normalizedToday = DateTime(today.year, today.month, today.day);

            if (normalizedSelectedDate.isBefore(normalizedToday)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cannot add events to past dates'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }

            _showAddEventDialog(selectedDate);
          },
          backgroundColor: primaryColor,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      )
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          if (_filterBatch != 'All')
            Chip(
              label: Text(_filterBatch),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: () {
                setState(() {
                  _filterBatch = 'All';
                });
              },
              backgroundColor: primaryColor.withOpacity(0.1),
            ),
          if (_filterProgram != 'All')
            Chip(
              label: Text(_filterProgram),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: () {
                setState(() {
                  _filterProgram = 'All';
                });
              },
              backgroundColor: primaryColor.withOpacity(0.1),
            ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String tempBatch = _filterBatch;
        String tempProgram = _filterProgram;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter Events'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDropdown('Batch', tempBatch, batches, (value) {
                    setDialogState(() => tempBatch = value!);
                  }),
                  const SizedBox(height: 16),
                  _buildDropdown('Program', tempProgram, programs, (value) {
                    setDialogState(() => tempProgram = value!);
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _filterBatch = 'All';
                      _filterProgram = 'All';
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Clear All'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _filterBatch = tempBatch;
                      _filterProgram = tempProgram;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
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
        disabledTextStyle: TextStyle(
          color: _isDarkMode ? Colors.white24 : Colors.grey[400],
        ),
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
      enabledDayPredicate: (day) {
        final normalizedDay = DateTime(day.year, day.month, day.day);
        return !normalizedDay.isBefore(normalizedToday);
      },
    );
  }

  Widget _buildEventsList() {
    final selectedEvents = _getEventsForDay(_selectedDay ?? DateTime.now());

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading events...'),
          ],
        ),
      );
    }

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
                if (_filterBatch != 'All' || _filterProgram != 'All') ...[
                  const SizedBox(height: 8),
                  Text(
                    'Try adjusting your filters',
                    style: TextStyle(
                      color: _isDarkMode ? Colors.white : Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                ],
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
    final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool isOwnEvent = event['teacherId'] == currentUid;

    Color? cardColor;
    final now = DateTime.now();
    final eventDate = DateTime.parse(event['date']);
    final isToday = isSameDay(eventDate, now);
    final eventTime = event['time'] ?? '';

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
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: primaryColor.withOpacity(0.2),
          child: Text(
            event['title']?.substring(0, 1).toUpperCase() ?? 'E',
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
            if (event['description'] != null && event['description'].isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                event['description'],
                style: TextStyle(
                  color: _isDarkMode ? Colors.white70 : Colors.grey[700],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (event['time'] != null && event['time'].isNotEmpty) ...[
                  Icon(Icons.access_time, size: 14, color: primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    event['time'],
                    style: TextStyle(
                      fontSize: 12,
                      color: _isDarkMode ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Icon(Icons.group, size: 14, color: primaryColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${event['batch']} - ${event['program']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isDarkMode ? Colors.white60 : Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (event['teacherName'] != null && !isOwnEvent) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    'by ${event['teacherName']}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isDarkMode ? Colors.white : Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwnEvent) ...[
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _showEditEventDialog(event),
                color: primaryColor,
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                onPressed: () => _showDeleteConfirmation(event['id'], event['title'] ?? 'Event'),
                color: Colors.red,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showEditEventDialog(Map<String, dynamic> event) {
    final titleController = TextEditingController(text: event['title'] ?? '');
    final descController = TextEditingController(text: event['description'] ?? '');
    final timeController = TextEditingController(text: event['time'] ?? '');
    String selectedBatch = event['batch'] ?? batches[1];
    String selectedProgram = event['program'] ?? programs[1];
    final selectedDate = DateTime.parse(event['date']);
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Text('Edit Event - ${DateFormat('MMM dd, yyyy').format(selectedDate)}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextField(titleController, 'Title', Icons.title),
                    _buildTextField(descController, 'Description', Icons.description),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        controller: timeController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Time',
                          prefixIcon: const Icon(Icons.access_time),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onTap: () async {
                          try {
                            TimeOfDay? pickedTime = await showTimePicker(
                              context: builderContext,
                              initialTime: TimeOfDay.now(),
                            );
                            if (pickedTime != null) {
                              final formattedTime = pickedTime.format(builderContext);
                              setDialogState(() {
                                timeController.text = formattedTime;
                              });
                            }
                          } catch (e) {
                            _showErrorSnackbar('Error selecting time: $e');
                          }
                        },
                      ),
                    ),
                    _buildDialogDropdown('Batch', selectedBatch, batches.sublist(1), (value) {
                      setDialogState(() => selectedBatch = value!);
                    }),
                    const SizedBox(height: 8),
                    _buildDialogDropdown('Program', selectedProgram, programs.sublist(1), (value) {
                      setDialogState(() => selectedProgram = value!);
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : () async {
                    if (titleController.text.trim().isEmpty) {
                      _showWarningSnackbar('Please enter a title');
                      return;
                    }

                    setDialogState(() => isSubmitting = true);

                    try {
                      await _updateEvent(
                        event['id'],
                        titleController.text.trim(),
                        descController.text.trim(),
                        timeController.text.trim(),
                        selectedBatch,
                        selectedProgram,
                      );

                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        _showSuccessSnackbar('Event updated successfully!');
                        await _loadEvents();
                      }
                    } catch (e) {
                      _showErrorSnackbar('Error updating event: ${_getUserFriendlyError(e)}');
                    } finally {
                      if (mounted) {
                        setDialogState(() => isSubmitting = false);
                      }
                    }
                  },
                  child: isSubmitting
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmation(String eventId, String eventTitle) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Are you sure you want to delete "$eventTitle"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await _deleteEvent(eventId);
                _showSuccessSnackbar('Event deleted successfully!');
                await _loadEvents();
              } catch (e) {
                _showErrorSnackbar('Error deleting event: ${_getUserFriendlyError(e)}');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddEventDialog(DateTime selectedDate) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final timeController = TextEditingController();
    String selectedBatch = batches[1]; // Skip 'All'
    String selectedProgram = programs[1]; // Skip 'All'
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Text('Add Event - ${DateFormat('MMM dd, yyyy').format(selectedDate)}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextField(titleController, 'Title', Icons.title),
                    _buildTextField(descController, 'Description', Icons.description),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        controller: timeController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Time',
                          prefixIcon: const Icon(Icons.access_time),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onTap: () async {
                          try {
                            TimeOfDay? pickedTime = await showTimePicker(
                              context: builderContext,
                              initialTime: TimeOfDay.now(),
                            );
                            if (pickedTime != null) {
                              final formattedTime = pickedTime.format(builderContext);
                              setDialogState(() {
                                timeController.text = formattedTime;
                              });
                            }
                          } catch (e) {
                            _showErrorSnackbar('Error selecting time: $e');
                          }
                        },
                      ),
                    ),
                    _buildDialogDropdown('Batch', selectedBatch, batches.sublist(1), (value) {
                      setDialogState(() => selectedBatch = value!);
                    }),
                    const SizedBox(height: 8),
                    _buildDialogDropdown('Program', selectedProgram, programs.sublist(1), (value) {
                      setDialogState(() => selectedProgram = value!);
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : () async {
                    if (titleController.text.trim().isEmpty) {
                      _showWarningSnackbar('Please enter a title');
                      return;
                    }

                    setDialogState(() => isSubmitting = true);

                    try {
                      await _saveEvent(
                        selectedDate,
                        titleController.text.trim(),
                        descController.text.trim(),
                        timeController.text.trim(),
                        selectedBatch,
                        selectedProgram,
                      );

                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        _showSuccessSnackbar('Event added successfully!');
                        await _loadEvents();
                      }
                    } catch (e) {
                      _showErrorSnackbar('Error adding event: ${_getUserFriendlyError(e)}');
                    } finally {
                      if (mounted) {
                        setDialogState(() => isSubmitting = false);
                      }
                    }
                  },
                  child: isSubmitting
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        maxLines: label == 'Description' ? 3 : 1,
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDialogDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
        isExpanded: true,
      ),
    );
  }

  Future<void> _saveEvent(DateTime date, String title, String desc, String time, String batch, String program) async {
    if (title.isEmpty) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    await _firestore.collection('events').add({
      'title': title,
      'description': desc,
      'time': time,
      'date': DateFormat('yyyy-MM-dd').format(date),
      'batch': batch,
      'program': program,
      'createdAt': FieldValue.serverTimestamp(),
      'teacherId': user.uid,
      'teacherName': user.displayName ?? 'Unknown Teacher',
    });
  }

  Future<void> _updateEvent(String eventId, String title, String desc, String time, String batch, String program) async {
    if (title.isEmpty) return;

    await _firestore.collection('events').doc(eventId).update({
      'title': title,
      'description': desc,
      'time': time,
      'batch': batch,
      'program': program,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteEvent(String eventId) async {
    await _firestore.collection('events').doc(eventId).delete();
  }

  String _getUserFriendlyError(dynamic error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You don\'t have permission to perform this action';
        case 'not-found':
          return 'The requested data was not found';
        case 'invalid-argument':
          return 'Invalid data provided';
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

  void _showWarningSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
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