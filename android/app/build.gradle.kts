plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    // ✅ FIXED: Converted Groovy string syntax to correct Kotlin DSL syntax with double quotes and parentheses
    implementation("com.google.mlkit:face-detection:16.1.7")
}

android {
    namespace = "com.example.face_attendance_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.face_attendance_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    aaptOptions {
        noCompress += "tflite"
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}