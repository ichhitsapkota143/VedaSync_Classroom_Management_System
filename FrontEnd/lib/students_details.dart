import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> addStudentsToFirebase() async {
  final List<Map<String, String>> students = [
    {"rollNo": "220302", "name": "Anamol Dahal"},
    {"rollNo": "220304", "name": "Bibika Shrestha"},
    {"rollNo": "220305", "name": "Bijay BK"},
    {"rollNo": "220306", "name": "Devendra Pandey"},
    {"rollNo": "220307", "name": "Dipal Kumar Shrestha"},
    {"rollNo": "220308", "name": "Diwakar Prasad Singh"},
    {"rollNo": "220309", "name": "Gopal Sahu Rouniyar"},
    {"rollNo": "220310", "name": "Ichhit Sapkota"},
    {"rollNo": "220311", "name": "Iswar Kumar Mahato"},
    {"rollNo": "220312", "name": "Manish Joshi"},
    {"rollNo": "220313", "name": "Meghna Sedhai"},
    {"rollNo": "220315", "name": "Om Joshi"},
    {"rollNo": "220316", "name": "Pradip Bhandari"},
    {"rollNo": "220317", "name": "Pramod Panta"},
    {"rollNo": "220319", "name": "Rabina Thapa Magar"},
    {"rollNo": "220320", "name": "Ravi Shankar Adhikari"},
    {"rollNo": "220321", "name": "Rohan Pudasaini"},
    {"rollNo": "220322", "name": "Sachchidandanda Pandey"},
    {"rollNo": "220323", "name": "Saishree Chand"},
    {"rollNo": "220324", "name": "Sandip Kepchaki"},
    {"rollNo": "220326", "name": "Sneha Mishra"},
    {"rollNo": "220327", "name": "Supriya Sapkota"},
    {"rollNo": "220328", "name": "Susan Mahato"},
    {"rollNo": "220330", "name": "Swornima K.C."},
    {"rollNo": "220331", "name": "Utsav Shrestha"},
    {"rollNo": "220333", "name": "Ajit Barhi"},
    {"rollNo": "220334", "name": "Anuja Sharma Nepal"},
    {"rollNo": "220335", "name": "Puja Shah"},
    {"rollNo": "220344", "name": "Abishek Mishra [PU Scholar]"},
    {"rollNo": "220345", "name": "Garima Rokaha [PU Scholar]"},
    {"rollNo": "220346", "name": "Harish Saud [PU Scholar]"},
    {"rollNo": "220347", "name": "Pankaj Kumar Yadav [PU Scholar]"},
    {"rollNo": "220348", "name": "Puja Bist [PU Scholar]"}
  ];

  final collectionRef = FirebaseFirestore.instance
      .collection('student_programs')
      .doc('Computer Engineering')
      .collection('batches')
      .doc('2022')
      .collection('students');

  for (var student in students) {
    await collectionRef.doc(student['name']).set({
      'rollNo': student['rollNo'],
      'name': student['name'],
    });
  }

  print('Students added successfully!');
}
