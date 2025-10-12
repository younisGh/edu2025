import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

kotlin {
    jvmToolchain(17)
}

android {
    namespace = "com.ahlulbait.edu2025"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ahlulbait.edu2025"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Limit packaged resources (languages) to reduce APK size
        resourceConfigurations += listOf("ar", "en")
        // Resolve placeholder used in AndroidManifest.xml: android:name="${applicationName}"
        // Without this, the merged manifest may keep an unresolved placeholder and Play Console will reject the AAB.
        manifestPlaceholders += mapOf(
            "applicationName" to "io.flutter.app.FlutterApplication"
        )
    }

    signingConfigs {
        create("release") {
            // Load keystore from android/key.properties if it exists
            val keystoreProperties = Properties()
            // In Flutter, the Gradle rootProject is the 'android' directory, so key.properties is at root
            val keystoreFile = rootProject.file("key.properties")
            println("[Signing] Looking for key.properties at: ${keystoreFile.absolutePath}")
            if (keystoreFile.exists()) {
                keystoreFile.inputStream().use { keystoreProperties.load(it) }
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                println("[Signing] storeFile from properties: '${storeFilePath}'")
                if (!storeFilePath.isNullOrBlank()) {
                    val resolvedStoreFile = file(storeFilePath)
                    println("[Signing] Resolved keystore path: ${resolvedStoreFile.absolutePath}, exists=${resolvedStoreFile.exists()}")
                    storeFile = resolvedStoreFile
                    storePassword = keystoreProperties.getProperty("storePassword")
                    keyAlias = keystoreProperties.getProperty("keyAlias")
                    keyPassword = keystoreProperties.getProperty("keyPassword")
                }
            } else {
                println("[Signing] key.properties not found. Expected at: ${keystoreFile.absolutePath}")
            }
        }
    }

    buildTypes {
        release {
            // Shrink Java/Kotlin bytecode and remove unused Android resources
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            // Enforce release signing; fail fast if keystore is missing
            val releaseConfig = signingConfigs.getByName("release")
            println("[Signing] releaseConfig.storeFile at check time: ${releaseConfig.storeFile}")
            signingConfig = releaseConfig
            if (releaseConfig.storeFile == null) {
                throw GradleException("Release keystore is not configured. Please create android/key.properties with storeFile, storePassword, keyAlias, keyPassword.")
            }
        }
    }
}

flutter {
    source = "../.."
}


