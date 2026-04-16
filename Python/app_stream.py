from flask import Flask, Response
import cv2
import dlib
import numpy as np
import os
import pickle
import time

app = Flask(__name__)

model_paths = {
    'prototxt': r"/Applications/VedaSyncProject/Python/Models/deploy.prototxt",
    'caffemodel': r"/Applications/VedaSyncProject/Python/Models/res10_300x300_ssd_iter_140000.caffemodel",
    'shape_predictor': r"/Applications/VedaSyncProject/Python/Models/shape_predictor_68_face_landmarks.dat",
    'face_recog': r"/Applications/VedaSyncProject/Python/Models/dlib_face_recognition_resnet_model_v1.dat"
}
embeddings_path = "/Applications/VedaSyncProject/Python/embeddings.pkl"
rtsp_url = r'rtsp://admin:L29F8CC9@192.168.1.106:554/cam/realmonitor?channel=1&subtype=0'

# Load models
net = cv2.dnn.readNetFromCaffe(model_paths['prototxt'], model_paths['caffemodel'])
sp = dlib.shape_predictor(model_paths['shape_predictor'])
reco = dlib.face_recognition_model_v1(model_paths['face_recog'])

with open(embeddings_path, "rb") as f:
    data = pickle.load(f)
known_names = data['names']
known_encodings = np.array(data['encodings'])

def generate_frames():
    cap = cv2.VideoCapture(rtsp_url)
    if not cap.isOpened():
        raise Exception("Failed to open CCTV stream")

    frame_id = 0
    start_time = time.time()

    while True:
        success, frame = cap.read()
        if not success:
            continue

        (h, w) = frame.shape[:2]
        blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 1.0, (300, 300), (104.0, 177.0, 123.0))
        net.setInput(blob)
        detections = net.forward()

        for i in range(detections.shape[2]):
            confidence = detections[0, 0, i, 2]
            if confidence < 0.5:
                continue

            box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
            (x1, y1, x2, y2) = box.astype("int")
            rect = dlib.rectangle(max(0, x1), max(0, y1), min(w, x2), min(h, y2))
            shape = sp(frame, rect)
            face_desc = np.array(reco.compute_face_descriptor(frame, shape))

            distances = np.linalg.norm(known_encodings - face_desc, axis=1)
            min_idx = np.argmin(distances)
            min_dist = distances[min_idx]

            if min_dist < 0.6:
                label = f"{known_names[min_idx]} {min_dist:.2f}"
                color = (0, 255, 0)
            else:
                label = f"Unknown {min_dist:.2f}"
                color = (0, 0, 255)

            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            cv2.putText(frame, label, (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

        fps = frame_id / (time.time() - start_time + 1e-5)
        cv2.putText(frame, f"FPS: {fps:.2f}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)

        _, buffer = cv2.imencode('.jpg', frame)
        frame = buffer.tobytes()

        yield (b'--frame\r\n'
               b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')

        frame_id += 1

@app.route('/video_feed')
def video_feed():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5050)
