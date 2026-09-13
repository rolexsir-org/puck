// Puck -- Android app module.
//
// Kotlin DSL (the modern Flutter template). If your project was generated with
// the older Groovy template, the three blocks below map 1:1 onto
// android { defaultConfig { ... } } and buildTypes { ... } in build.gradle.

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.puck.app"

    // 35 is required for predictive-back and edge-to-edge on Android 15+.
    compileSdk = 35
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
        applicationId = "dev.puck.app"
        minSdk = 24          // Android 7.0+. Covers ~98% of active devices.
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // No resConfigs stripping needed: Puck ships no locale-specific
        // resources. Removing this line is safe.
    }

    buildTypes {
        release {
            // Debug signing so `flutter run --release` works out of the box.
            // Replace with a real keystore before shipping.
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true

            // Flutter's own rules plus ours; nothing exotic is reflected, so
            // full (non-code-item) shrinking is safe.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }

        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    // Split by ABI for a dramatically smaller download; Flutter's own engine
    // is by far the largest thing in the APK.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }

    packaging {
        resources {
            excludes += setOf("META-INF/*.kotlin_module")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by several plugins (battery_plus, device_calendar) for
    // java.time backporting on older runtimes.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
