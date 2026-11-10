# The ML Kit Flutter plugin references every optional script through compileOnly
# dependencies. PostCheck only requests Japanese and Latin. Do not bundle the
# unsupported Chinese, Korean, or Devanagari models to satisfy unused branches.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
