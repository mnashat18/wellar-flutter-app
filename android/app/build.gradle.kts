import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")

}

// Release signing is loaded from android/key.properties. The file is
// .gitignore'd and must be provided by whoever cuts the release build.
// See android/key.properties.example for the expected keys.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun hasReleaseSigningConfig(): Boolean {
    return keystoreProperties.getProperty("storeFile")?.isNotBlank() == true &&
        keystoreProperties.getProperty("storePassword")?.isNotBlank() == true &&
        keystoreProperties.getProperty("keyAlias")?.isNotBlank() == true &&
        keystoreProperties.getProperty("keyPassword")?.isNotBlank() == true
}

android {
    namespace = "com.example.waller_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.waller_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigningConfig()) {
                val storePath = keystoreProperties.getProperty("storeFile")!!
                storeFile = rootProject.file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigningConfig()) {
                signingConfigs.getByName("release")
            } else {
                // Fall back to debug so `flutter run --release` still works locally.
                // A real store artefact (assembleRelease / bundleRelease) must fail
                // if no release signing is configured — see the check below.
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Fail fast if someone tries to produce a real release artifact without a
// configured keystore. Debug local runs (assembleDebug, `flutter run --release`
// against a connected device without a bundle task) are unaffected.
gradle.taskGraph.whenReady {
    val storeTaskRequested = allTasks.any { task ->
        val name = task.name
        name == "bundleRelease" ||
            name == "assembleRelease" ||
            name.endsWith("bundleRelease") ||
            name.endsWith("assembleRelease")
    }
    if (storeTaskRequested && !hasReleaseSigningConfig()) {
        throw GradleException(
            "Release signing is not configured. Create android/key.properties " +
                "with storeFile, storePassword, keyAlias, and keyPassword " +
                "(see android/key.properties.example). Do NOT commit this file " +
                "or the keystore."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("com.google.firebase:firebase-auth:24.0.1")
}

configurations.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "com.google.firebase" && requested.name == "firebase-auth") {
            useVersion("24.0.1")
        }
    }
}

