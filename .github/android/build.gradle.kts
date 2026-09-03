// Root Android build file — CI copies this over the file `flutter create`
// generates in android/build.gradle.kts.
//
// Flutter 3.47.2 uses android.newDsl=false (legacy AGP path). Plugin modules
// (share_plus and its transitive androidx deps, jni, shared_preferences) take
// their compileSdk from `flutter.compileSdkVersion`. We force a literal 36 on
// every android subproject so the build succeeds regardless of that value.
// This only affects compilation — minSdk stays 24 (Android 7+).

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory
rootProject.layout.buildDirectory = newBuildDir.get()

// Force all app/plugin android modules to compile against SDK 36.
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt is com.android.build.gradle.BaseExtension) {
                androidExt.compileSdkVersion = 36
                androidExt.minSdkVersion = 24
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
