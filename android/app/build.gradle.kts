plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.oversea.oversea"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.oversea.oversea"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // Android 7+
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Native lock core (libovs.so). The secrets reach C++ as masked hex from the
        // environment (CI: LOCK_Pn_M / GATE_KEY_M / LOCK_MASK from tool/mask_secrets.dart);
        // for local builds the plain LOCK_P1..P4 / GATE_KEY are accepted and left unmasked.
        // They are NOT passed to Dart in release builds, so the Dart snapshot holds none.
        fun secret(masked: String, plain: String) =
            System.getenv(masked)?.takeIf { it.isNotBlank() } ?: System.getenv(plain) ?: ""
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DOVS_P1=${secret("LOCK_P1_M", "LOCK_P1")}",
                    "-DOVS_P2=${secret("LOCK_P2_M", "LOCK_P2")}",
                    "-DOVS_P3=${secret("LOCK_P3_M", "LOCK_P3")}",
                    "-DOVS_P4=${secret("LOCK_P4_M", "LOCK_P4")}",
                    "-DOVS_GATE=${secret("GATE_KEY_M", "GATE_KEY")}",
                    "-DOVS_MASK=${System.getenv("LOCK_MASK") ?: ""}",
                )
            }
        }

        // AdMob application id. Defaults to Google's public TEST id; CI sets
        // ADMOB_APP_ID from a secret for real builds.
        manifestPlaceholders["admobAppId"] =
            System.getenv("ADMOB_APP_ID")?.takeIf { it.isNotBlank() }
                ?: "ca-app-pub-3940256099942544~3347511713"
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // Final signing is done by CI with apksigner (stable key from
            // secrets). The debug config only keeps `flutter run --release` working.
            signingConfig = signingConfigs.getByName("debug")

            // Shrink + obfuscate Java/Kotlin and drop unused resources.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Xray-core for Android, built from source by tool/build_xray_aar.sh.
    implementation(files("libs/libv2ray.aar"))
}

flutter {
    source = "../.."
}
