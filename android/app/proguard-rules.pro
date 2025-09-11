# ProGuard/R8 rules for Flutter app
# Keep Flutter and plugin entry points
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Firebase / Google Play services models and annotations
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.gson.annotations.** { *; }
-keepattributes *Annotation*

# Keep Kotlin coroutines and metadata used by reflection
-keep class kotlinx.coroutines.** { *; }
-keepclassmembers class kotlinx.** { *; }
-keep class kotlin.Metadata { *; }

# Keep models that might be accessed via reflection (adjust as needed)
# -keep class com.example.educational_platform.** { *; }

# Keep enum synthetic methods used by reflection
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Do not warn about these packages (common with R8 + Flutter)
-dontwarn io.flutter.embedding.**
-dontwarn kotlinx.coroutines.**
-dontwarn org.jetbrains.annotations.**
