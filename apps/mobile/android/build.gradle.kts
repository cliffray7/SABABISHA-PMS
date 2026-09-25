allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force all plugin subprojects to compile against SDK 36 so that
// flutter_plugin_android_lifecycle (which requires 36+) is satisfied.
subprojects {
    afterEvaluate {
        if (extensions.findByName("android") != null) {
            extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileSdkVersion(36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
