import com.android.build.gradle.BaseExtension

// Root Android build file — CI copies this over the file `flutter create`
// generates in android/build.gradle.kts.
//
// Force every Android module (app + plugins like share_plus) to compile against
// SDK 36. share_plus and its transitive androidx deps (window, activity,
// fragment, lifecycle...) require compileSdk >= 34; jni/shared_preferences
// newer builds need up to 36. Only compilation is affected — minSdk stays 24
// (Android 7+), so supported devices are unchanged.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory
rootProject.layout.buildDirectory = newBuildDir.get()

subprojects {
    afterEvaluate {
        val androidExt = extensions.findByType(BaseExtension::class.java)
        if (androidExt != null) {
            androidExt.compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
