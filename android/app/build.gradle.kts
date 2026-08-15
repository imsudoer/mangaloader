plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "bshv.mangaloader.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "bshv.mangaloader.app"
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyProps = keystorePropertiesFile
            if (keyProps.exists()) {
                val keyFileStr = keystoreProperties.getProperty("storeFile") ?: "mangaloader-release.jks"
                val keyFile = file(keyFileStr)
                if (keyFile.exists()) {
                    storeFile = keyFile
                    storePassword = keystoreProperties.getProperty("storePassword")
                    keyAlias = keystoreProperties.getProperty("keyAlias")
                    keyPassword = keystoreProperties.getProperty("keyPassword")
                    enableV1Signing = true
                    enableV2Signing = true
                    enableV3Signing = true
                    enableV4Signing = true
                }
            } else {
                val defaultKey = file("mangaloader-release.jks")
                if (defaultKey.exists()) {
                    storeFile = defaultKey
                    storePassword = "mangaloader2026"
                    keyAlias = "mangaloader"
                    keyPassword = "mangaloader2026"
                    enableV1Signing = true
                    enableV2Signing = true
                    enableV3Signing = true
                    enableV4Signing = true
                }
            }
        }
    }

    buildTypes {
        release {
            val hasPropsKey = keystorePropertiesFile.exists() && file(keystoreProperties.getProperty("storeFile") ?: "mangaloader-release.jks").exists()
            val hasDefaultKey = file("mangaloader-release.jks").exists()
            if (hasPropsKey || hasDefaultKey) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

