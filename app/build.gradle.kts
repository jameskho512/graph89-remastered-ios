import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing key: keystore.properties in the project root (not in git) with
// storeFile, storePassword, keyAlias and keyPassword. Release builds fail without it.
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.isFile) f.inputStream().use { load(it) }
}
val hasUploadKey = keystoreProps.getProperty("storeFile") != null

android {
    namespace = "com.example.calc89"
    compileSdk = 36
    ndkVersion = "25.1.8937393"

    defaultConfig {
        applicationId = "app.graph89remaster"  // permanent: an update installs only over the same id
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "2.0.0"
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
            debugSymbolLevel = "FULL"  // native crash reports in Play Console show function names
        }
        // GPL: the About screen links to the source code. Set sourceUrl in gradle.properties.
        buildConfigField("String", "SOURCE_URL", "\"" + (project.findProperty("sourceUrl") as String? ?: "") + "\"")
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasUploadKey) signingConfig = signingConfigs.getByName("upload")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    externalNativeBuild {
        ndkBuild {
            path = file("src/main/jni/Android.mk")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true  // skin render tests read the app's assets
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        jniLibs {
            useLegacyPackaging = false  // uncompressed, page-aligned libs
        }
    }
}

// An unsigned release APK does not install: stop a release build without the signing key.
gradle.taskGraph.whenReady {
    // clean has release tasks too (the native build's clean): those need no key
    val releaseBuild = allTasks.any { it.project == project && it.name.contains("Release") && !it.name.contains("Clean", ignoreCase = true) }
    if (!hasUploadKey && releaseBuild) {
        throw GradleException("Release build without a signing key: create keystore.properties (see the top of app/build.gradle.kts).")
    }
    if ((project.findProperty("sourceUrl") as String?).isNullOrBlank() && releaseBuild) {
        throw GradleException("Release build without sourceUrl in gradle.properties: the GPL requires a link to the source code.")
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    debugImplementation("androidx.compose.ui:ui-tooling")
    // skin render tests: Android's real graphics on the JVM (./gradlew testDebugUnitTest --tests *SkinRenderTest*)
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation(composeBom)
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
