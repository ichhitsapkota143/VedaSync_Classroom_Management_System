import 'package:cloud_firestore/cloud_firestore.dart';

class GroupUtils {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Fetch student info from usernames collection
  Future<Map<String, dynamic>?> getStudentInfo(String username) async {
    try {
      final snapshot = await _firestore.collection('usernames').doc(username).get();
      if (snapshot.exists) {
        return snapshot.data();
      }
    } catch (e) {
      print('Error fetching student info: $e');
    }
    return null;
  }

  // Get group document based on program and batch
  Future<DocumentSnapshot?> getGroupDoc(String program, String batch) async {
    final groupId = '${program}_$batch';
    try {
      final doc = await _firestore.collection('groups').doc(groupId).get();
      if (doc.exists) {
        return doc;
      }
    } catch (e) {
      print('Error fetching group doc: $e');
    }
    return null;
  }

  // Extract class schedule
  Future<List<dynamic>> getClassSchedule(String program, String batch) async {
    final doc = await getGroupDoc(program, batch);
    return doc?.get('classSchedule') ?? [];
  }

  // Extract notices
  Future<List<dynamic>> getNotices(String program, String batch) async {
    final doc = await getGroupDoc(program, batch);
    return doc?.get('notices') ?? [];
  }

  // Extract resources
  Future<List<dynamic>> getResources(String program, String batch) async {
    final doc = await getGroupDoc(program, batch);
    return doc?.get('resources') ?? [];
  }
}
