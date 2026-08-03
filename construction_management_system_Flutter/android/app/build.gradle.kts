import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties if it exists (local dev) or use environment variables (CI/CD)
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.buildsmart.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            // Use key.properties file (local) or CI environment variables
            keyAlias = keyProperties["keyAlias"] as String? ?: System.getenv("KEY_ALIAS") ?: "buildsmart"
            keyPassword = keyProperties["keyPassword"] as String? ?: System.getenv("KEY_PASSWORD") ?: ""
            storeFile = if (keyPropertiesFile.exists()) {
                file(keyProperties["storeFile"] as String)
            } else if (System.getenv("KEY_STORE_PATH") != null) {
                file(System.getenv("KEY_STORE_PATH")!!)
            } else {
                // Fallback to debug signing if no key available
                signingConfigs.getByName("debug").storeFile
            }
            storePassword = keyProperties["storePassword"] as String? ?: System.getenv("KEY_STORE_PASSWORD") ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.buildsmart.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
