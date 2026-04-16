import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> pushSubjectsToFirestore() async {
  final firestore = FirebaseFirestore.instance;

  final Map<String, Map<String, dynamic>> programs =
    {
      'Computer Engineering': {
        '2020': {
          'semester': 'VIII',
          'year': 'IV',
          'courses': [
            {'code': 'INT 492', 'subject': 'Internship', 'credits': 3},
            {'code': 'PRJ 452', 'subject': 'Project II', 'credits': 3},
            {'code': 'Elective III', 'subject': 'Elective III', 'credits': 3},
          ],
        },
        '2021': {
          'semester': 'VII',
          'year': 'IV',
          'courses': [
            {'code': 'MGT 327', 'subject': 'Entrepreneurship', 'credits': 2},
            {'code': 'CMP 426', 'subject': 'Network & Cyber Security', 'credits': 3},
            {'code': 'CMP 422', 'subject': 'Cloud Computing', 'credits': 3},
            {'code': 'CMP 360', 'subject': 'Data Science', 'credits': 3},
            {'code': 'Elective II', 'subject': 'Elective II', 'credits': 3},
          ],
        },
        '2022': {
          'semester': 'VI',
          'year': 'III',
          'courses': [
            {'code': 'CMP 362', 'subject': 'Image Processing', 'credits': 3},
            {'code': 'CMP 364', 'subject': 'Machine Learning', 'credits': 3},
            {'code': 'CMP 344', 'subject': 'Computer Networks', 'credits': 3},
            {'code': 'CMP 338', 'subject': 'Simulation & Modeling', 'credits': 3},
            {'code': 'PRJ 360', 'subject': 'Project I', 'credits': 2},
          ],
        },
        '2023': {
          'semester': 'IV',
          'year': 'II',
          'courses': [
            {'code': 'CMP 228', 'subject': 'Java Programming', 'credits': 3},
            {'code': 'CMP 254', 'subject': 'Theory of Computation', 'credits': 3},
            {'code': 'CMP 262', 'subject': 'Computer Architecture', 'credits': 3},
            {'code': 'CMP 270', 'subject': 'Research Fundamentals', 'credits': 2},
          ],
        },
        '2024': {
          'semester': 'II',
          'year': 'I',
          'courses': [
            {'code': 'MTH 150', 'subject': 'Algebra & Geometry', 'credits': 3},
            {'code': 'PHY 110', 'subject': 'Applied Physics', 'credits': 3},
            {'code': 'CMP 162', 'subject': 'OOP in C++', 'credits': 3},
            {'code': 'CMP 160', 'subject': 'Data Structures', 'credits': 3},
          ],
        },
      },

      'Information Technology': {
        '2020': {
          'semester': 'VIII',
          'year': 'IV',
          'courses': [
            {'code': 'INT 402', 'subject': 'IT Capstone Project', 'credits': 3},
            {'code': 'PRJ 402', 'subject': 'Industry Internship', 'credits': 3},
            {'code': 'Elective III', 'subject': 'Cloud Security', 'credits': 3},
          ],
        },
        '2021': {
          'semester': 'VII',
          'year': 'IV',
          'courses': [
            {'code': 'ITM 401', 'subject': 'IT Management', 'credits': 2},
            {'code': 'ITC 405', 'subject': 'Mobile App Development', 'credits': 3},
            {'code': 'ITN 407', 'subject': 'Cybersecurity', 'credits': 3},
            {'code': 'ITE 408', 'subject': 'E-Governance', 'credits': 3},
            {'code': 'Elective II', 'subject': 'AI for IT', 'credits': 3},
          ],
        },
        '2022': {
          'semester': 'VI',
          'year': 'III',
          'courses': [
            {'code': 'ITS 315', 'subject': 'Data Mining', 'credits': 3},
            {'code': 'ITS 318', 'subject': 'Web Technologies', 'credits': 3},
            {'code': 'ITS 319', 'subject': 'IT Security', 'credits': 3},
            {'code': 'ITS 320', 'subject': 'Networking', 'credits': 3},
            {'code': 'PRJ 300', 'subject': 'Minor Project', 'credits': 2},
          ],
        },
        '2023': {
          'semester': 'IV',
          'year': 'II',
          'courses': [
            {'code': 'ITP 220', 'subject': 'Python Programming', 'credits': 3},
            {'code': 'ITS 210', 'subject': 'System Analysis & Design', 'credits': 3},
            {'code': 'ITD 230', 'subject': 'Database Management Systems', 'credits': 3},
          ],
        },
        '2024': {
          'semester': 'II',
          'year': 'I',
          'courses': [
            {'code': 'MTH 102', 'subject': 'Mathematics I', 'credits': 3},
            {'code': 'ITF 101', 'subject': 'Introduction to IT', 'credits': 3},
            {'code': 'ITS 103', 'subject': 'Digital Logic', 'credits': 3},
          ],
        },
      },

      'Electronics & Communication': {
        '2020': {
          'semester': 'VIII',
          'year': 'IV',
          'courses': [
            {'code': 'ECP 480', 'subject': 'Project II', 'credits': 3},
            {'code': 'ECR 470', 'subject': 'Industrial Training', 'credits': 3},
            {'code': 'Elective III', 'subject': 'IoT Systems', 'credits': 3},
          ],
        },
        '2021': {
          'semester': 'VII',
          'year': 'IV',
          'courses': [
            {'code': 'ECE 410', 'subject': 'Advanced Communication', 'credits': 3},
            {'code': 'ECE 411', 'subject': 'Radar Systems', 'credits': 3},
            {'code': 'ECE 412', 'subject': 'Digital Signal Processing', 'credits': 3},
            {'code': 'Elective II', 'subject': 'Microwave Engineering', 'credits': 3},
          ],
        },
        '2022': {
          'semester': 'VI',
          'year': 'III',
          'courses': [
            {'code': 'ECE 301', 'subject': 'Embedded Systems', 'credits': 3},
            {'code': 'ECE 305', 'subject': 'Microprocessors', 'credits': 3},
            {'code': 'ECE 308', 'subject': 'Analog Circuits', 'credits': 3},
            {'code': 'PRJ 310', 'subject': 'Mini Project', 'credits': 2},
          ],
        },
        '2023': {
          'semester': 'IV',
          'year': 'II',
          'courses': [
            {'code': 'ECE 210', 'subject': 'Signals and Systems', 'credits': 3},
            {'code': 'ECE 215', 'subject': 'Electronics I', 'credits': 3},
            {'code': 'ECE 218', 'subject': 'Network Theory', 'credits': 3},
          ],
        },
        '2024': {
          'semester': 'II',
          'year': 'I',
          'courses': [
            {'code': 'PHY 110', 'subject': 'Applied Physics', 'credits': 3},
            {'code': 'MTH 150', 'subject': 'Engineering Mathematics I', 'credits': 3},
            {'code': 'ECE 102', 'subject': 'Basic Electronics', 'credits': 3},
          ],
        },
      },

      'Civil Engineering': {
        '2020': {
          'semester': 'VIII',
          'year': 'IV',
          'courses': [
            {'code': 'CVL 492', 'subject': 'Final Project', 'credits': 3},
            {'code': 'CVL 498', 'subject': 'Internship', 'credits': 3},
            {'code': 'Elective III', 'subject': 'Urban Transport Design', 'credits': 3},
          ],
        },
        '2021': {
          'semester': 'VII',
          'year': 'IV',
          'courses': [
            {'code': 'CVL 432', 'subject': 'Construction Planning', 'credits': 3},
            {'code': 'CVL 436', 'subject': 'Design of Structures II', 'credits': 3},
            {'code': 'CVL 440', 'subject': 'Water Resources Engineering', 'credits': 3},
          ],
        },
        '2022': {
          'semester': 'VI',
          'year': 'III',
          'courses': [
            {'code': 'CVL 320', 'subject': 'Soil Mechanics', 'credits': 3},
            {'code': 'CVL 330', 'subject': 'Hydraulics', 'credits': 3},
            {'code': 'CVL 340', 'subject': 'Transportation Engineering', 'credits': 3},
          ],
        },
        '2023': {
          'semester': 'IV',
          'year': 'II',
          'courses': [
            {'code': 'CVL 210', 'subject': 'Engineering Mechanics', 'credits': 3},
            {'code': 'CVL 220', 'subject': 'Surveying', 'credits': 3},
            {'code': 'CVL 230', 'subject': 'Building Materials', 'credits': 3},
          ],
        },
        '2024': {
          'semester': 'II',
          'year': 'I',
          'courses': [
            {'code': 'PHY 110', 'subject': 'Engineering Physics', 'credits': 3},
            {'code': 'MTH 150', 'subject': 'Engineering Mathematics I', 'credits': 3},
            {'code': 'CHM 110', 'subject': 'Applied Chemistry', 'credits': 3},
          ],
        },
      },

      'Business Administration': {
        '2020': {
          'semester': 'VIII',
          'year': 'IV',
          'courses': [
            {'code': 'BUS 490', 'subject': 'Strategic Management', 'credits': 3},
            {'code': 'BUS 495', 'subject': 'Internship Report', 'credits': 3},
            {'code': 'Elective III', 'subject': 'Business Ethics', 'credits': 3},
          ],
        },
        '2021': {
          'semester': 'VII',
          'year': 'IV',
          'courses': [
            {'code': 'MKT 410', 'subject': 'International Marketing', 'credits': 3},
            {'code': 'HRM 402', 'subject': 'Human Resource Development', 'credits': 3},
            {'code': 'FIN 404', 'subject': 'Investment Analysis', 'credits': 3},
          ],
        },
        '2022': {
          'semester': 'VI',
          'year': 'III',
          'courses': [
            {'code': 'MGT 330', 'subject': 'Operations Management', 'credits': 3},
            {'code': 'ACC 320', 'subject': 'Cost & Management Accounting', 'credits': 3},
            {'code': 'MKT 325', 'subject': 'Digital Marketing', 'credits': 3},
          ],
        },
        '2023': {
          'semester': 'IV',
          'year': 'II',
          'courses': [
            {'code': 'MKT 210', 'subject': 'Principles of Marketing', 'credits': 3},
            {'code': 'FIN 220', 'subject': 'Financial Accounting', 'credits': 3},
            {'code': 'HRM 230', 'subject': 'Organizational Behavior', 'credits': 3},
          ],
        },
        '2024': {
          'semester': 'II',
          'year': 'I',
          'courses': [
            {'code': 'MGT 101', 'subject': 'Introduction to Management', 'credits': 3},
            {'code': 'ENG 102', 'subject': 'Business Communication', 'credits': 3},
            {'code': 'ECO 103', 'subject': 'Microeconomics', 'credits': 3},
          ],
        },
      },

      'Architecture': {
        '2020': {
          'semester': 'VIII',
          'year': 'IV',
          'courses': [
            {'code': 'ARC 480', 'subject': 'Thesis Design Project', 'credits': 6},
            {'code': 'ARC 482', 'subject': 'Professional Practice', 'credits': 3},
            {'code': 'Elective III', 'subject': 'Urban Design', 'credits': 3},
          ],
        },
        '2021': {
          'semester': 'VII',
          'year': 'IV',
          'courses': [
            {'code': 'ARC 460', 'subject': 'Advanced Building Tech', 'credits': 3},
            {'code': 'ARC 465', 'subject': 'Landscape Architecture', 'credits': 3},
            {'code': 'ARC 470', 'subject': 'Building Services II', 'credits': 3},
          ],
        },
        '2022': {
          'semester': 'VI',
          'year': 'III',
          'courses': [
            {'code': 'ARC 340', 'subject': 'Building Services I', 'credits': 3},
            {'code': 'ARC 345', 'subject': 'Architectural Design Studio III', 'credits': 6},
            {'code': 'ARC 350', 'subject': 'History of Architecture', 'credits': 3},
          ],
        },
        '2023': {
          'semester': 'IV',
          'year': 'II',
          'courses': [
            {'code': 'ARC 210', 'subject': 'Architectural Drawing II', 'credits': 3},
            {'code': 'ARC 215', 'subject': 'Design Studio II', 'credits': 6},
            {'code': 'ARC 220', 'subject': 'Construction Materials', 'credits': 3},
          ],
        },
        '2024': {
          'semester': 'II',
          'year': 'I',
          'courses': [
            {'code': 'ARC 101', 'subject': 'Architectural Drawing I', 'credits': 3},
            {'code': 'ARC 105', 'subject': 'Design Fundamentals', 'credits': 6},
            {'code': 'ENG 110', 'subject': 'Technical Communication', 'credits': 3},
          ],
        },
      }
    };

  for (var programEntry in programs.entries) {
    final programName = programEntry.key;
    final batches = programEntry.value;

    // Create program document
    final programRef = firestore.collection('programs').doc(programName);
    await programRef.set({'programName': programName});

    for (var batchYear in batches.keys) {
      final batchData = batches[batchYear]!;

      await programRef.collection('batches').doc(batchYear).set({
        'semester': batchData['semester'],
        'year': batchData['year'],
        'courses': List<Map<String, dynamic>>.from(batchData['courses'])
      });
    }
  }

  print("\u2705 Programs and subjects pushed successfully to Firestore.");
}






