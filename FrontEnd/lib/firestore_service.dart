import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Adds user to 'usernames' collection and assigns them to a group.
  Future<void> createUser({
    required String username,
    required String email,
    required String role,
    required String fullName,
    String? batch,
    String? program,
    String? faculty,
  }) async {
    final userDoc = _firestore.collection('usernames').doc(username);

    Map<String, dynamic> userData = {
      'username': username,
      'email': email,
      'role': role,
      'fullName': fullName,
    };

    if (role.toLowerCase() == 'student') {
      userData['batch'] = batch;
      userData['program'] = program;
      await _assignStudentToGroup(username: username, batch: batch!, program: program!);
    } else if (role.toLowerCase() == 'teacher') {
      userData['faculty'] = faculty;
    }

    await userDoc.set(userData);
  }

  /// Creates or updates a group document with student list
  Future<void> _assignStudentToGroup({
    required String username,
    required String batch,
    required String program,
  }) async {
    final groupId = '${program}_$batch';
    final groupDoc = _firestore.collection('groups').doc(groupId);

    final docSnapshot = await groupDoc.get();
    if (docSnapshot.exists) {
      await groupDoc.update({
        'students': FieldValue.arrayUnion([username]),
      });
    } else {
      await groupDoc.set({
        'program': program,
        'batch': batch,
        'students': [username],
        'schedule': [],
        'notices': [],
        'resources': [],
      });
    }
  }

  /// Gets group ID for a student based on username
  Future<String?> getGroupIdForStudent(String username) async {
    final userSnap = await _firestore.collection('usernames').doc(username).get();
    if (!userSnap.exists) return null;
    final batch = userSnap['batch'];
    final program = userSnap['program'];
    return '${program}_$batch';
  }

  /// Fetches group schedule, notices, or resources
  Future<Map<String, dynamic>?> getGroupContent(String groupId) async {
    final groupSnap = await _firestore.collection('groups').doc(groupId).get();
    if (!groupSnap.exists) return null;
    return groupSnap.data();
  }
}
