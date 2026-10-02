import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Assinatura de release: credenciais em android/key.properties, fora do git (ver app/README.md).
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "br.com.itscs.tradutor"
    // permission_handler_android 14.1 exige compilar contra a API 37. Só a API de compilação muda:
    // targetSdk (comportamento em execução) e minSdk (aparelhos suportados) seguem os padrões do Flutter.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.itscs.tradutor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Sem key.properties, assina com a chave de debug apenas para testes locais
            // (`flutter run --release`, APK de validação). O AAB para a Play Store exige a chave de release.
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }
}

// Impede gerar o pacote da Play Store (AAB) assinado com a chave de debug.
tasks.matching { it.name == "bundleRelease" }.configureEach {
    doFirst {
        if (!hasReleaseKey) {
            throw GradleException("android/key.properties ausente: o AAB de release precisa da chave de upload (ver app/README.md).")
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
