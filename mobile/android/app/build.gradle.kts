import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase / FCM
    id("com.google.gms.google-services")
    // Crash raporlama (Firebase Crashlytics)
    id("com.google.firebase.crashlytics")
}

// Release imzalama anahtarı: android/key.properties (repo'ya girmez).
// Dosya yoksa debug anahtarına düşülür ki `flutter run` çalışmaya devam etsin.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreVar = keystorePropertiesFile.exists()
if (keystoreVar) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.glow_saha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Play Store paket kimliği. (namespace kod tarafında com.example kalabilir;
        // mağazada görünen kimlik applicationId'dir ve com.example ile başlayamaz.)
        applicationId = "com.glowsaha.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreVar) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties varsa gerçek upload anahtarıyla, yoksa debug ile imzala.
            signingConfig = if (keystoreVar)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // İnternetsiz/pilot yapılarda Crashlytics eşleme (mapping) dosyasının
            // Firebase'e yüklenmesini kapatır; aksi halde build son adımda ağ hatası verir.
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = false
            }
        }
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
