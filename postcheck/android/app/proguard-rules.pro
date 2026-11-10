# The ML Kit Flutter plugin references every optional script through compileOnly
# dependencies. PostCheck only requests Japanese and Latin. Do not bundle the
# unsupported Chinese, Korean, or Devanagari models to satisfy unused branches.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# MediaPipe's protobuf-lite messages look up their fields by their original
# names. Renaming/removing these fields breaks ObjectDetector initialization in
# release builds even when the model is bundled. Keep the generated messages.
# https://github.com/protocolbuffers/protobuf/blob/main/java/lite.md
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }

# Flogger discovers its caller from the stack. Inlining/renaming its methods
# makes MediaPipe Graph's static initializer fail in minified releases.
-keep class com.google.common.flogger.** { *; }

# MediaPipe JNI entry points (upstream framework/proguard.pgcfg).
-keep public interface com.google.mediapipe.framework.* { public *; }
-keep public class com.google.mediapipe.framework.Packet {
    public static *** create(***);
    public long getNativeHandle();
    public void release();
}
-keep public class com.google.mediapipe.framework.PacketCreator {
    *** releaseWithSyncToken(...);
}
-keep public class com.google.mediapipe.framework.MediaPipeException {
    <init>(int, byte[]);
}
-keep class com.google.mediapipe.framework.ProtoUtil$SerializedMessage { *; }
