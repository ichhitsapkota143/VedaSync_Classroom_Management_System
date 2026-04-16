import os
import cv2
import dlib
import numpy as np
import pickle
import time
import random
import firebase_admin
from firebase_admin import credentials, firestore
from flask import Flask, jsonify

# Initialize Flask app
app = Flask(__name__)

# Initialize Firebase Admin SDK
cred = credentials.Certificate("Python/vedasync-96ced-firebase-adminsdk-fbsvc-6e335843e9.json")  # Update path to Firebase Admin SDK JSON
firebase_admin.initialize_app(cred)
db = firestore.client()

# Variable to track class session
class_in_session = False
recognized_students = []

# Root route to handle requests to "/"
@app.route('/')
def home():
    return "Welcome to the Flask server! Use the /start_class endpoint to start the class and trigger face recognition."

# Handle the /favicon.ico request (optional, to avoid 404)
@app.route('/favicon.ico')
def favicon():
    return '', 204  # Empty response with status code 204 (No Content)

# Testing Route: Start class and trigger face recognition
@app.route('/test_class', methods=['GET'])
def test_class():
    global class_in_session, recognized_students

    # Hardcoded test data (from your provided example)
    class_duration = "1 minutes"
    created_at = "2025-07-25T19:18:56.990999"
    selected_batch = "2022"
    selected_program = "Computer Engineering"
    selected_subject = "Project I"
    teacher_name = "Saksham Sapkota"
    timestamp = "2025-07-25T19:18:57 UTC+5:45"

    # Log the class session start to Firestore (simulate class start)
    class_ref = db.collection('class_sessions').document('current_class')
    class_ref.set({
        'teacher': teacher_name,
        'classDuration': class_duration,
        'createdAt': created_at,
        'selectedBatch': selected_batch,
        'selectedProgram': selected_program,
        'selectedSubject': selected_subject,
        'timestamp': timestamp,
        'status': 'Started',
    })

    # Mark that class has started
    class_in_session = True
    print(f"Class started by {teacher_name} at {timestamp}. Duration: {class_duration} minutes.")

    # Trigger face recognition
    rtsp_url = "rtsp://admin:password@192.168.1.106:554/cam/realmonitor?channel=1&subtype=1"  # Adjust your CCTV URL
    model_paths = {
        'prototxt': '/path/to/deploy.prototxt',
        'caffemodel': '/path/to/res10_300x300_ssd_iter_140000.caffemodel',
        'shape_predictor': '/path/to/shape_predictor_68_face_landmarks.dat',
        'face_recog': '/path/to/dlib_face_recognition_resnet_model_v1.dat'
    }
    embeddings_path = "/path/to/embeddings.pkl"
    
    # Call the function to start face recognition
    recognize_faces_from_cctv(rtsp_url, model_paths, embeddings_path, class_duration)
    
    return jsonify({"status": "success", "message": "Class started and face recognition triggered!"}), 200

def recognize_faces_from_cctv(rtsp_url, model_paths, embeddings_path, class_duration, threshold=0.6):
    global class_in_session, recognized_students
    recognized_students = []
    
    # Load models
    print("[INFO] Loading models...")
    net = cv2.dnn.readNetFromCaffe(model_paths['prototxt'], model_paths['caffemodel'])
    sp = dlib.shape_predictor(model_paths['shape_predictor'])
    reco = dlib.face_recognition_model_v1(model_paths['face_recog'])

    with open(embeddings_path, "rb") as f:
        data = pickle.load(f)
    known_names = data['names']
    known_encodings = np.array(data['encodings'])

    # Open CCTV stream
    cap = cv2.VideoCapture(rtsp_url)
    if not cap.isOpened():
        raise Exception(f"[ERROR] Cannot open CCTV stream: {rtsp_url}")

    print("[INFO] CCTV stream opened. Press 'q' to quit.")
    
    frame_id = 0
    start_time = time.time()
    total_frames = int(class_duration) * 60 * 30  # Assuming 30 FPS, adjust accordingly

    snapshot_times = [
        int(total_frames * 0.05),   # Start snapshot
        int(total_frames * 0.5),    # Mid snapshot
        int(total_frames * 0.75),   # Near end snapshot
        int(total_frames * 0.95)    # End snapshot
    ]
    
    # Add two random snapshots within the class duration
    snapshot_times.extend(random.sample(range(int(total_frames * 0.1), int(total_frames * 0.9)), 2))

    snapshots_taken = 0

    while True:
        ret, frame = cap.read()
        if not ret or frame is None or frame.size == 0 or np.count_nonzero(frame) == 0:
            print("[WARN] Skipping empty, black, or invalid frame.")
            continue

        (h, w) = frame.shape[:2]

        try:
            blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 1.0, (300, 300), (104.0, 177.0, 123.0))
            net.setInput(blob)
            detections = net.forward()
        except Exception as e:
            print(f"[ERROR] Failed to process frame: {e}")
            continue

        for i in range(detections.shape[2]):
            confidence = detections[0, 0, i, 2]
            if confidence < 0.5:
                continue

            box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
            (x1, y1, x2, y2) = box.astype("int")
            x1, y1 = max(0, x1), max(0, y1)
            x2, y2 = min(w, x2), min(h, y2)

            rect = dlib.rectangle(x1, y1, x2, y2)
            shape = sp(frame, rect)
            face_desc = np.array(reco.compute_face_descriptor(frame, shape))

            distances = np.linalg.norm(known_encodings - face_desc, axis=1)
            min_idx = np.argmin(distances)
            min_dist = distances[min_idx]

            if min_dist < threshold:
                label = f"{known_names[min_idx]} {min_dist:.3f}"
                color = (0, 255, 0)

                first_name = known_names[min_idx].split()[0]  # Get first name

                # Add the recognized student to the list
                recognized_students.append(first_name)

                # Mark attendance
                mark_attendance_in_firestore(first_name, True)
            else:
                label = f"Unknown {min_dist:.3f}"
                color = (0, 0, 255)

            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            cv2.putText(frame, label, (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)

        elapsed = time.time() - start_time
        fps = frame_id / elapsed if elapsed > 0 else 0
        cv2.putText(frame, f"FPS: {fps:.2f}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)

        cv2.imshow("CCTV Face Recognition", frame)

        frame_id += 1

        # Check if we need to take a snapshot
        if frame_id in snapshot_times and snapshots_taken < 5:
            snapshots_taken += 1
            print(f"[INFO] Snapshot taken at {frame_id} frames.")
        
        if snapshots_taken >= 5:
            break

    cap.release()
    cv2.destroyAllWindows()
    print("[INFO] Process completed.")

    # Calculate attendance and update Firebase
    total_students = len(known_names)
    attendance_percentage = len(recognized_students) / total_students
    print(f"[INFO] Attendance Percentage: {attendance_percentage * 100}%")
    
    if attendance_percentage >= 0.6:  # 60% attendance threshold
        print("[INFO] Attendance threshold met. Marking students as present.")
        for student in recognized_students:
            mark_attendance_in_firestore(student, True)
    else:
        print("[INFO] Attendance threshold not met. Marking students as absent.")
        for student in recognized_students:
            mark_attendance_in_firestore(student, False)

def mark_attendance_in_firestore(first_name, attendance_status):
    # Search by full name in Firestore
    students_ref = db.collection('student_programs').document('Computer Engineering') \
                                .collection('batches').document('2022') \
                                .collection('students')

    query = students_ref.where("firstName", "==", first_name)
    docs = query.stream()
    for doc in docs:
        full_name = doc.id  # Firestore document ID is the full name
        student_ref = students_ref.document(full_name)
        student_ref.update({'attendance': attendance_status})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5050)  # Run the Flask server on the local IP address
