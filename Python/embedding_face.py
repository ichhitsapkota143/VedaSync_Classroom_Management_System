import cv2
import dlib
import numpy as np
import os
import pickle

# === Load models ===
detector = dlib.get_frontal_face_detector()
sp = dlib.shape_predictor(r"/Applications/VedaSyncProject/Python/Models/shape_predictor_68_face_landmarks.dat")
reco = dlib.face_recognition_model_v1(r"/Applications/VedaSyncProject/Python/Models/dlib_face_recognition_resnet_model_v1.dat")

# === Set dataset path ===
dataset_path = "/Applications/VedaSyncProject/Python/TrainingData"
embeddings = []
names = []

# === Walk through dataset ===
for person_name in os.listdir(dataset_path):
    person_folder = os.path.join(dataset_path, person_name)
    if not os.path.isdir(person_folder):
        continue

    print(f"[INFO] Processing: {person_name}")

    for img_name in os.listdir(person_folder):
        img_path = os.path.join(person_folder, img_name)
        img = cv2.imread(img_path)

        if img is None:
            print(f"[WARN] Cannot read image: {img_path}")
            continue

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        faces = detector(gray, 1)

        if len(faces) == 0:
            print(f"[WARN] No face found in: {img_path}")
            continue

        # Use the first detected face
        face_rect = faces[0]
        shape = sp(img, face_rect)
        face_desc = np.array(reco.compute_face_descriptor(img, shape))

        embeddings.append(face_desc)
        names.append(person_name)

        print(f"[INFO] Saved embedding for: {person_name} ({img_name})")

# === Save embeddings ===
output_path = "/Applications/VedaSyncProject/Python/embeddings.pkl"
data = {"names": names, "encodings": embeddings}

with open(output_path, "wb") as f:
    pickle.dump(data, f)

print(f"[INFO] Saved {len(embeddings)} face embeddings to {output_path}")
