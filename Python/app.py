import os
import cv2
import dlib
import numpy as np
import pickle
import time
import random
import firebase_admin
from firebase_admin import credentials, firestore
from flask import Flask, request, jsonify
from datetime import datetime
import threading
import math

# Initialize Flask app
app = Flask(__name__)

# Initialize Firebase Admin SDK
cred = credentials.Certificate(r"/Applications/VedaSyncProject/Python/vedasync-96ced-firebase-adminsdk-fbsvc-6e335843e9.json")  # Update path to Firebase Admin SDK JSON
firebase_admin.initialize_app(cred)
db = firestore.client()

# Variables to track class session
class_in_session = False
recognized_students = []
current_recognition_thread = None
current_session_data = {}  # Store current session information
recognition_stop_event = threading.Event()  # Event to signal thread to stop

# Root route to handle requests to "/"
@app.route('/')
def home():
    return "Welcome to the Flask server! Use the /start_class endpoint to start the class and trigger face recognition."

# Handle the /favicon.ico request (optional, to avoid 404)
@app.route('/favicon.ico')
def favicon():
    return '', 204  # Empty response with status code 204 (No Content)

# Function to parse the class duration (e.g., "2 minutes" -> 2)
def parse_class_duration(duration_str):
    """
    Parse the class duration string (e.g., "2 minutes") into an integer number of minutes.
    """
    try:
        # Split the string by space and take the first part as an integer (number of minutes)
        return int(duration_str.split()[0])
    except ValueError:
        return None  # Return None if parsing fails (invalid duration format)

# Health check endpoint
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy", "message": "Flask server is running"}), 200

# Endpoint to start the class and trigger face recognition
@app.route('/start_class', methods=['POST'])
def start_class():
    global class_in_session, recognized_students, current_recognition_thread, current_session_data, recognition_stop_event

    try:
        # Get the class session data from the Flutter app
        data = request.json
        if not data:
            return jsonify({"status": "error", "message": "No data provided"}), 400

        class_duration = data.get("classDuration")
        created_at = data.get("createdAt")
        selected_batch = data.get("selectedBatch")
        selected_program = data.get("selectedProgram")
        selected_subject = data.get("selectedSubject")
        teacher_name = data.get("teacherName")
        timestamp = data.get("timestamp")

        # Validate required fields
        required_fields = [class_duration, selected_batch, selected_program, selected_subject, teacher_name]
        if not all(required_fields):
            return jsonify({"status": "error", "message": "Missing required fields"}), 400

        # Ensure classDuration is provided and is valid
        class_duration_minutes = parse_class_duration(class_duration)
        if class_duration_minutes is None:
            return jsonify({"status": "error", "message": "Invalid class duration format!"}), 400

        # Check if a class is already in session
        if class_in_session:
            return jsonify({"status": "error", "message": "A class is already in session"}), 409

        # Generate session ID
        session_doc_id = f"{selected_program}_{selected_batch}_{selected_subject}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        # Store current session data
        current_session_data = {
            'session_id': session_doc_id,
            'teacher': teacher_name,
            'classDuration': class_duration,
            'createdAt': created_at,
            'selectedBatch': selected_batch,
            'selectedProgram': selected_program,
            'selectedSubject': selected_subject,
            'timestamp': timestamp,
            'start_time': datetime.now(),
            'class_duration_minutes': class_duration_minutes
        }

        # Log the class session start to Firestore
        class_ref = db.collection('class_sessions').document(session_doc_id)
        class_ref.set({
            'teacher': teacher_name,
            'classDuration': class_duration,
            'createdAt': created_at,
            'selectedBatch': selected_batch,
            'selectedProgram': selected_program,
            'selectedSubject': selected_subject,
            'timestamp': timestamp,
            'status': 'Started',
            'session_id': session_doc_id,
            'start_time': firestore.SERVER_TIMESTAMP,
        })

        # Mark that class has started and reset stop event
        class_in_session = True
        recognition_stop_event.clear()
        recognized_students = []
        
        print(f"Class started by {teacher_name} at {timestamp}. Duration: {class_duration}")
        
        # Start face recognition in a separate thread
        #rtsp_url = r'rtsp://admin:L29F8CC9@192.168.1.106:554/cam/realmonitor?channel=1&subtype=1'  # Adjust your CCTV URL
        #rtsp_url = r'rtsp://admin:L29F8CC9@172.16.23.94:554/cam/realmonitor?channel=1&subtype=1'
        rtsp_url = r'rtsp://admin:L29F8CC9@10.142.212.173:554/cam/realmonitor?channel=1&subtype=1'
        model_paths = {
            'prototxt': r'/Applications/VedaSyncProject/Models/deploy.prototxt',
            'caffemodel': r'/Applications/VedaSyncProject/Models/res10_300x300_ssd_iter_140000.caffemodel',
            'shape_predictor': r'/Applications/VedaSyncProject/Models/shape_predictor_68_face_landmarks.dat',
            'face_recog': r'/Applications/VedaSyncProject/Models/dlib_face_recognition_resnet_model_v1.dat'
        }
        embeddings_path = r"/Applications/VedaSyncProject/Python/embeddings.pkl"
        
        # Start face recognition in a background thread
        current_recognition_thread = threading.Thread(
            target=recognize_faces_from_cctv,
            args=(rtsp_url, model_paths, embeddings_path, class_duration_minutes, 
                  selected_batch, selected_program, selected_subject, session_doc_id)
        )
        current_recognition_thread.daemon = True
        current_recognition_thread.start()
        
        return jsonify({
            "status": "success", 
            "message": f"Class started successfully! Face recognition is running for {class_duration_minutes} minutes.",
            "session_id": session_doc_id
        }), 200

    except Exception as e:
        print(f"Error in start_class: {str(e)}")
        return jsonify({"status": "error", "message": f"Internal server error: {str(e)}"}), 500

# Enhanced endpoint to stop the current class and generate attendance
@app.route('/stop_class', methods=['POST'])
def stop_class():
    global class_in_session, current_session_data, recognition_stop_event
    
    try:
        # Get the stop request data from the Flutter app
        data = request.json
        if not data:
            return jsonify({"status": "error", "message": "No data provided"}), 400

        # Extract data from request
        teacher_name = data.get("teacherName")
        selected_batch = data.get("selectedBatch")
        selected_program = data.get("selectedProgram")
        selected_subject = data.get("selectedSubject")
        end_time = data.get("endTime")
        session_id = data.get("sessionId")
        
        print(f"[INFO] Stop class request received from {teacher_name} at {end_time}")
        
        # Check if a class is currently in session
        if not class_in_session:
            return jsonify({"status": "warning", "message": "No active class session found"}), 200

        # Signal the recognition thread to stop
        recognition_stop_event.set()
        class_in_session = False
        
        # Wait for the recognition thread to finish (with timeout)
        if current_recognition_thread and current_recognition_thread.is_alive():
            current_recognition_thread.join(timeout=5.0)  # Wait up to 5 seconds
        
        # Update session status in Firestore
        if session_id:
            try:
                session_ref = db.collection('class_sessions').document(session_id)
                session_ref.update({
                    'status': 'Stopped Manually',
                    'end_time': firestore.SERVER_TIMESTAMP,
                    'stopped_by': teacher_name,
                    'actual_end_time': end_time
                })
                print(f"[INFO] Updated session {session_id} status to 'Stopped Manually'")
            except Exception as e:
                print(f"[ERROR] Failed to update session status: {e}")

        # Force attendance generation if we have current session data
        if current_session_data:
            print("[INFO] Generating final attendance based on current recognition data...")
            
            # Get the recognized students data from the current session
            try:
                # Fetch all students for the class
                students_ref = db.collection('student_programs').document(selected_program) \
                                                        .collection('batches').document(selected_batch) \
                                                        .collection('students')
                
                student_docs = students_ref.stream()
                students = {doc.id: doc.to_dict() for doc in student_docs}
                
                # Generate attendance based on whatever recognition data we have
                generate_final_attendance(
                    selected_batch, 
                    selected_program, 
                    selected_subject,
                    students,
                    session_id or current_session_data.get('session_id')
                )
                
            except Exception as e:
                print(f"[ERROR] Failed to generate final attendance: {e}")
        
        # Clear current session data
        current_session_data = {}
        
        print(f"[INFO] Class session stopped successfully by {teacher_name}")
        
        return jsonify({
            "status": "success", 
            "message": "Class stopped successfully and attendance has been generated",
            "session_id": session_id
        }), 200
        
    except Exception as e:
        print(f"[ERROR] Error in stop_class: {str(e)}")
        return jsonify({"status": "error", "message": f"Error stopping class: {str(e)}"}), 500

def calculate_attendance_percentage(recognized_count, total_snapshots):
    """
    Calculate attendance percentage based on recognition count
    Returns True if student meets 60% threshold
    """
    if total_snapshots == 0:
        return False, 0.0
    
    percentage = (recognized_count / total_snapshots) * 100
    meets_threshold = percentage >= 60.0
    
    return meets_threshold, percentage

def get_student_total_classes_present(student_name, selected_batch, selected_program, selected_subject):
    """
    Get the total number of classes a student has been present for this subject
    """
    try:
        # Query attendance collection for this student's attendance record
        attendance_ref = db.collection('attendance')
        query = attendance_ref.where('student_name', '==', student_name) \
                             .where('selectedBatch', '==', selected_batch) \
                             .where('selectedProgram', '==', selected_program) \
                             .where('selectedSubject', '==', selected_subject) \
                             .where('status', '==', True)  # Only count present classes
        
        attendance_docs = query.stream()
        total_present = len(list(attendance_docs))
        
        return total_present
        
    except Exception as e:
        print(f"[ERROR] Error getting student total classes: {e}")
        return 0

def recognize_faces_from_cctv(rtsp_url, model_paths, embeddings_path, class_duration, 
                             selected_batch, selected_program, selected_subject, session_id, threshold=0.6):
    global class_in_session, recognized_students, recognition_stop_event
    recognized_students = []

    try:
        # Fetch all students from Firestore based on selected program and batch
        students_ref = db.collection('student_programs').document(selected_program) \
                                                    .collection('batches').document(selected_batch) \
                                                    .collection('students')
        
        # Get all student documents from Firestore
        student_docs = students_ref.stream()
        students = {doc.id: doc.to_dict() for doc in student_docs}

        # Print the list of student names
        print("[INFO] Students in this class:")
        for student_name, student_data in students.items():
            print(f"Student Name: {student_name}, Roll Number: {student_data.get('rollNo')}")
        
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
            print(f"[ERROR] Cannot open CCTV stream: {rtsp_url}")
            return

        frame_id = 0
        start_time = time.time()
        class_duration_seconds = class_duration * 60
        
        # Define snapshot intervals (take snapshots every 20% of class duration)
        snapshot_interval = class_duration_seconds / 6
        next_snapshot_time = start_time + snapshot_interval
        
        snapshots_taken = 0
        recognized_in_snapshots = {}  # Track student recognitions per snapshot

        print(f"[INFO] Starting face recognition for {class_duration} minutes")

        # Modified loop to check for stop event
        while class_in_session and not recognition_stop_event.is_set() and time.time() - start_time < class_duration_seconds:
            ret, frame = cap.read()
            if not ret or frame is None or frame.size == 0:
                time.sleep(0.1)
                continue

            current_time = time.time()
            
            # Check if it's time for a snapshot
            if current_time >= next_snapshot_time and snapshots_taken < 5:
                (h, w) = frame.shape[:2]

                try:
                    blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 1.0, (300, 300), (104.0, 177.0, 123.0))
                    net.setInput(blob)
                    detections = net.forward()
                    
                    print(f"[INFO] Taking snapshot {snapshots_taken + 1}/5")
                    
                    for i in range(detections.shape[2]):
                        confidence = detections[0, 0, i, 2]
                        if confidence < 0.5:
                            continue

                        box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
                        (x1, y1, x2, y2) = box.astype("int")
                        
                        # Ensure coordinates are within frame bounds
                        x1, y1 = max(0, x1), max(0, y1)
                        x2, y2 = min(w, x2), min(h, y2)
                        
                        rect = dlib.rectangle(x1, y1, x2, y2)
                        shape = sp(frame, rect)
                        face_desc = np.array(reco.compute_face_descriptor(frame, shape))

                        distances = np.linalg.norm(known_encodings - face_desc, axis=1)
                        min_idx = np.argmin(distances)
                        min_dist = distances[min_idx]

                        if min_dist < threshold:
                            student_name = known_names[min_idx]
                            first_name = student_name.split()[0]  # First name only for recognition
                            recognized_in_snapshots[first_name] = recognized_in_snapshots.get(first_name, 0) + 1
                            print(f"[RECOGNIZED] {student_name} in snapshot {snapshots_taken + 1}")

                except Exception as e:
                    print(f"[ERROR] Error processing frame: {e}")
                    continue

                snapshots_taken += 1
                next_snapshot_time += snapshot_interval

            # Check for stop event more frequently
            if recognition_stop_event.is_set():
                print("[INFO] Recognition stopped by external request")
                break

            # Small delay to prevent excessive CPU usage
            time.sleep(0.1)

        cap.release()
        
        # Determine why the loop ended
        if recognition_stop_event.is_set():
            print(f"[INFO] Face recognition stopped manually. Snapshots taken: {snapshots_taken}")
        else:
            print(f"[INFO] Face recognition completed normally. Snapshots taken: {snapshots_taken}")
        
        print(f"[INFO] Recognition results: {recognized_in_snapshots}")

        # Mark attendance based on recognition results with 60% threshold
        mark_all_students_attendance(selected_batch, selected_program, selected_subject, 
                                   recognized_in_snapshots, students, session_id, snapshots_taken)

    except Exception as e:
        print(f"[ERROR] Error in face recognition: {e}")
    finally:
        class_in_session = False

def generate_final_attendance(selected_batch, selected_program, selected_subject, students, session_id):
    """
    Generate final attendance when class is stopped manually
    This uses any recognition data available at the time of stopping
    """
    try:
        print("[INFO] Generating final attendance for manually stopped class...")
        
        # For manually stopped classes, we assume 0 snapshots were completed
        total_snapshots = 0
        
        for student_name, student_data in students.items():
            roll_no = student_data.get('rollNo', 'N/A')
            
            # For manually stopped classes, mark as absent by default
            is_present = False
            recognition_count = 0
            attendance_percentage = 0.0
            
            # Get total classes present for this student
            total_classes_present = get_student_total_classes_present(
                student_name, selected_batch, selected_program, selected_subject
            )
            
            # Save attendance to Firestore
            attendance_ref = db.collection('attendance')
            attendance_doc = {
                'student_name': student_name,
                'roll_no': roll_no,
                'status': is_present,  # Boolean: False for manually stopped classes
                'selectedBatch': selected_batch,
                'selectedProgram': selected_program,
                'selectedSubject': selected_subject,
                'session_id': session_id,
                'recognition_count': recognition_count,
                'total_snapshots': total_snapshots,
                'attendance_percentage': attendance_percentage,
                'total_classes_present': total_classes_present,  # Current total (won't increment)
                'timestamp': firestore.SERVER_TIMESTAMP,
                'manually_stopped': True,  # Flag to indicate manual stop
                'note': 'Class ended manually - default absent'
            }
            
            attendance_ref.add(attendance_doc)
            
            status_text = "Present" if is_present else "Absent (Manual Stop)"
            print(f"[ATTENDANCE] {student_name} ({roll_no}): {status_text} - Total Classes Present: {total_classes_present}")

        # Update session status
        if session_id:
            session_ref = db.collection('class_sessions').document(session_id)
            session_ref.update({
                'status': 'Completed (Manual Stop)',
                'end_time': firestore.SERVER_TIMESTAMP,
                'total_students': len(students),
                'present_students': 0,  # No one marked present for manual stops
                'manually_stopped': True,
                'attendance_generated': True,
                'total_snapshots': total_snapshots
            })
        
        print("[INFO] Final attendance generation completed")
        
    except Exception as e:
        print(f"[ERROR] Error generating final attendance: {e}")

def mark_all_students_attendance(selected_batch, selected_program, selected_subject, 
                               recognized_in_snapshots, all_students, session_id, total_snapshots):
    """Mark attendance for all students in the class using 60% threshold"""
    try:
        print("[INFO] Marking attendance for all students with 60% threshold...")
        
        present_count = 0
        
        for student_name, student_data in all_students.items():
            roll_no = student_data.get('rollNo', 'N/A')
            
            # Check if student was recognized and calculate attendance percentage
            recognition_count = recognized_in_snapshots.get(student_name.split()[0], 0)  # Use first name for recognition
            is_present, attendance_percentage = calculate_attendance_percentage(recognition_count, total_snapshots)
            
            if is_present:
                present_count += 1
            
            # Get total classes present for this student (before this class)
            current_total_present = get_student_total_classes_present(
                student_name, selected_batch, selected_program, selected_subject
            )
            
            # If student is present in this class, increment the total
            new_total_present = current_total_present + (1 if is_present else 0)
            
            # Save attendance to Firestore
            attendance_ref = db.collection('attendance')
            attendance_doc = {
                'student_name': student_name,  # Store full name (first + last)
                'roll_no': roll_no,
                'status': is_present,  # Boolean: True for present, False for absent
                'selectedBatch': selected_batch,
                'selectedProgram': selected_program,
                'selectedSubject': selected_subject,
                'session_id': session_id,
                'recognition_count': recognition_count,
                'total_snapshots': total_snapshots,
                'attendance_percentage': round(attendance_percentage, 2),
                'total_classes_present': new_total_present,  # Updated total
                'timestamp': firestore.SERVER_TIMESTAMP,
                'manually_stopped': recognition_stop_event.is_set(),  # Track if manually stopped
            }
            
            attendance_ref.add(attendance_doc)
            
            status_text = "Present" if is_present else "Absent"
            print(f"[ATTENDANCE] {student_name} ({roll_no}): {status_text} ({attendance_percentage:.1f}% - {recognition_count}/{total_snapshots}) - Total Classes Present: {new_total_present}")

        # Update session status
        session_ref = db.collection('class_sessions').document(session_id)
        session_ref.update({
            'status': 'Completed',
            'end_time': firestore.SERVER_TIMESTAMP,
            'total_students': len(all_students),
            'present_students': present_count,
            'recognition_results': recognized_in_snapshots,
            'total_snapshots': total_snapshots,
            'attendance_generated': True
        })
        
        print(f"[INFO] Attendance marking completed successfully. {present_count}/{len(all_students)} students present (60% threshold)")
        
    except Exception as e:
        print(f"[ERROR] Error marking attendance: {e}")

# New endpoint to get current session status
@app.route('/session_status', methods=['GET'])
def get_session_status():
    global class_in_session, current_session_data
    
    try:
        if class_in_session and current_session_data:
            # Calculate elapsed time
            start_time = current_session_data.get('start_time')
            if start_time:
                elapsed_minutes = (datetime.now() - start_time).total_seconds() / 60
                remaining_minutes = max(0, current_session_data.get('class_duration_minutes', 0) - elapsed_minutes)
            else:
                elapsed_minutes = 0
                remaining_minutes = 0
            
            return jsonify({
                "status": "success",
                "class_in_session": True,
                "session_data": {
                    "session_id": current_session_data.get('session_id'),
                    "teacher": current_session_data.get('teacher'),
                    "subject": current_session_data.get('selectedSubject'),
                    "batch": current_session_data.get('selectedBatch'),
                    "program": current_session_data.get('selectedProgram'),
                    "elapsed_minutes": round(elapsed_minutes, 1),
                    "remaining_minutes": round(remaining_minutes, 1)
                }
            }), 200
        else:
            return jsonify({
                "status": "success",
                "class_in_session": False,
                "message": "No active session"
            }), 200
            
    except Exception as e:
        return jsonify({"status": "error", "message": f"Error getting session status: {str(e)}"}), 500

if __name__ == "__main__":
    print("Starting Flask server on port 5050...")
    app.run(host="0.0.0.0", port=5050, debug=True)  # Enable debug mode for development