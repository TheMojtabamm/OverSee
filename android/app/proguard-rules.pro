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

# Rename and flatten everything we own into one package.
-repackageclasses ''
-allowaccessmodification
