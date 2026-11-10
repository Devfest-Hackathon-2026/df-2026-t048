Run scripts/setup_screen_detector.sh to download the on-device EfficientDet-Lite0 model.

whiteboard_experiment.tflite (committed, EXPERIMENT - not for distribution)
  Custom EfficientDet-Lite0 trained with ml/object_detection on 200 Open Images
  photos (CC BY 2.0; run runs/oi_v1/exp_200, 20 epochs, int8). Labels: whiteboard.
  SHA-256 fe195f55942cbfe098dd8b084e526ede7c371e76493f996ec45be9294dc16c13
  Pretrained backbone: EfficientDet-Lite0, Apache-2.0.
  Training images (200 train + 50 validation): ml/object_detection/credits/whiteboard_exp200.csv

Modification notice: whiteboard_experiment.tflite and docs_experiment.tflite
are modified (fine-tuned) versions of EfficientDet-Lite0 (Apache-2.0); the
notice is shown on the app licence page. efficientdet_lite0.tflite is unmodified.

efficientdet_lite0.tflite (stock COCO model) allow-list:
  laptop, cell phone, tv -> "screen-device"; wine glass -> "wine_glass";
  book -> "book".

docs_experiment.tflite (committed, EXPERIMENT)
  Custom EfficientDet-Lite0 picture frame / poster model (run
  runs/docs_whole_v1, whole-model fine-tuning, 50 epochs, int8).
  Labels: picture_frame, poster. Open Images photos (CC BY 2.0; annotations
  CC BY 4.0). Training images (923 train + 200 validation):
  ml/object_detection/credits/frame_poster_docs_whole_v1.csv
  SHA-256 ea7e832c8aa543f3c704a744ddb067a6107fb1fd8a92f97de8336f287036cef9
