# Reproducible environment for training EfficientDet-Lite with TFLite Model Maker
# and checking TFLite Task Library ObjectDetector compatibility.
# Build: docker build --platform linux/amd64 -t postcheck-objdet:0.4.3 ml/object_detection
FROM --platform=linux/amd64 python:3.9-slim-bookworm

# libsndfile1: tflite_model_maker imports its audio module (librosa) on import.
# libusb-1.0-0: required by tflite_support's Coral delegate loader.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libsndfile1 libusb-1.0-0 libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONDONTWRITEBYTECODE=1 TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONWARNINGS=ignore::FutureWarning
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
 && python -c "from tflite_model_maker import object_detector; from tflite_support.task import vision; print('imports ok')"

WORKDIR /work
