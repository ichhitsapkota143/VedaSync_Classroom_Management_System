import cv2
import dlib
import numpy as np
import os
import pickle
import time

# Suppress FFmpeg decoding warnings
os.environ["OPENCV_FFMPEG_DEBUG"] = "0"

def recognize_faces_from_cctv(rtsp_url, output_dir, model_paths, embeddings_path, threshold=0.6):
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

    while True:
        ret, frame = cap.read()
        if not ret or frame is None or frame.size == 0 or np.count_nonzero(frame) == 0:
            print("[WARN] Skipping empty, black, or invalid frame.")
            continue

        (h, w) = frame.shape[:2]

        try:
            blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300,300)), 1.0, (300,300), (104.0,177.0,123.0))
            net.setInput(blob)
            detections = net.forward()
        except Exception as e:
            print(f"[ERROR] Failed to process frame: {e}")
            continue

        for i in range(detections.shape[2]):
            confidence = detections[0,0,i,2]
            if confidence < 0.5:
                continue

            box = detections[0,0,i,3:7] * np.array([w,h,w,h])
            (x1,y1,x2,y2) = box.astype("int")
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
            else:
                label = f"Unknown {min_dist:.3f}"
                color = (0, 0, 255)

            cv2.rectangle(frame, (x1,y1), (x2,y2), color, 2)
            cv2.putText(frame, label, (x1,y1-10), cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)

        elapsed = time.time() - start_time
        fps = frame_id / elapsed if elapsed > 0 else 0
        cv2.putText(frame, f"FPS: {fps:.2f}", (10,30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0,255,0), 2)

        cv2.imshow("CCTV Face Recognition", frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            print("[INFO] Stopped by user.")
            break

        frame_id += 1

    cap.release()
    cv2.destroyAllWindows()
    print("[INFO] Process completed.")

# === USAGE ===
if __name__ == "__main__":
    model_paths = {
        'prototxt': r"/Applications/VedaSyncProject/Python/Models/deploy.prototxt",
        'caffemodel': r"/Applications/VedaSyncProject/Python/Models/res10_300x300_ssd_iter_140000.caffemodel",
        'shape_predictor': r"/Applications/VedaSyncProject/Python/Models/shape_predictor_68_face_landmarks.dat",
        'face_recog': r"/Applications/VedaSyncProject/Python/Models/dlib_face_recognition_resnet_model_v1.dat"
    }
    embeddings_path = "/Applications/VedaSyncProject/Python/embeddings.pkl"
    #rtsp_url = r'rtsp://admin:L29F8CC9@10.142.212.173:554/cam/realmonitor?channel=1&subtype=1'
    #rtsp_url = r'rtsp://admin:L29F8CC9@192.168.1.106:554/cam/realmonitor?channel=1&subtype=1'
    rtsp_url = r'rtsp://admin:L29F8CC9@172.16.23.94:554/cam/realmonitor?channel=1&subtype=1'
    recognize_faces_from_cctv(rtsp_url, None, model_paths, embeddings_path)
