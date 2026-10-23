# Flutter's own rules are added automatically by the Flutter Gradle plugin.

# Ads SDK
-keep class com.google.android.gms.ads.** { *; }

# Strip Android log calls from release (nothing sensitive may reach logcat).
-assumenosideeffects class android.util.Log {
    public static *** v(...);
    public static *** d(...);
    public static *** i(...);
    public static *** w(...);
}

# Flutter references Play Core split-install classes that we don't ship.
-dontwarn com.google.android.play.core.**

# Room (used by WorkManager, which the ads SDK starts at process start) creates its
# generated database class by name and constructor. R8 full mode strips that constructor,
# and flattening packages breaks the name lookup: the app then dies on launch with
# "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.** extends androidx.work.ListenableWorker { <init>(...); }

# Xray-core (gomobile bindings are called over JNI by name).
-keep class libv2ray.** { *; }
-keep class go.** { *; }
