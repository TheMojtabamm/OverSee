import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Some plugins (file_picker, share_plus, ...) still compile against an older SDK
// than androidx.* now requires. Force every Android module to compile against 36;
// minSdk/targetSdk (device support, runtime behaviour) are not touched.
subprojects {
    afterEvaluate {
        extensions.findByType(BaseExtension::class.java)?.compileSdkVersion(36)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
