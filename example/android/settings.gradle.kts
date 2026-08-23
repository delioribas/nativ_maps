pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// ⚠️ AGP fijado en 8.x a propósito.
//
// Flutter 3.47 genera el proyecto con AGP 9.1.0, y `maplibre_gl` 0.27.0 aún no
// es compatible: su `build.gradle` deja de aplicar el plugin de Kotlin cuando
// detecta AGP 9 —porque en AGP 9 aplicarlo rompe el build de la app— y luego
// usa la extensión `kotlin {}`, que en AGP 9 no está registrada. El resultado
// es `Could not find method kotlin()` al compilar.
//
// Mientras `maplibre_gl` no lo resuelva, **toda app que use este paquete tiene
// que quedarse en AGP 8.x**. Está documentado en el README, en «Limitaciones
// conocidas», porque es lo primero con lo que se topa quien instala el
// paquete en un proyecto nuevo.
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
