import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Dados da chave de assinatura.
//
// Ficam fora do repositório de propósito: `key.properties` e o arquivo .jks
// contêm senha e a chave privada do app. Quem tiver esses dois arquivos pode
// publicar atualizações se passando por você.
//
// Quando eles não existem — outra pessoa clonando o projeto, ou CI — o build
// de release cai na chave de debug e continua funcionando para instalar e
// testar. Só não serve para a Play Store.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

android {
    namespace = "com.routely.routely"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // ATENÇÃO: o applicationId é PERMANENTE depois da primeira publicação
        // na Play Store — não dá para trocar sem criar um app novo, perdendo
        // avaliações e instalações.
        //
        // Não precisa ser um domínio seu: o Google não verifica isso, é só
        // convenção de nome. Só precisa ser único na loja.
        applicationId = "com.routely.routely"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
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
            // O R8 falha o build ao encontrar referências a classes do ML Kit
            // que não incluímos (reconhecedores de outros alfabetos). As
            // regras em proguard-rules.pro silenciam isso.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Instala e roda normalmente; a Play Store é que recusa.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
