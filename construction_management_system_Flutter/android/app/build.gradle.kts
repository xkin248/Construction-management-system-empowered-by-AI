import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services (reads android/app/google-services.json for FCM)
    id("com.google.gms.google-services")
}

// Load signing config from key.properties (local dev) or environment (CI / GitHub Secrets)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.construction_management_system"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (core library desugaring)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.construction_management_system"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String? ?: System.getenv("ANDROID_KEY_ALIAS") ?: ""
            keyPassword = keystoreProperties["keyPassword"] as String? ?: System.getenv("ANDROID_KEY_PASSWORD") ?: ""
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { rootProject.file(it) }
                ?: System.getenv("ANDROID_KEYSTORE_FILE")?.let { rootProject.file(it) }
            storePassword = keystoreProperties["storePassword"] as String? ?: System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: ""
        }
    }

    buildTypes {
        release {
            // Unified release signing — every build uses the same keystore so new
            // APKs can be installed as updates without uninstalling the old one.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by flutter_local_notifications (core library desugaring)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
