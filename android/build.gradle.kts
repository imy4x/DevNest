import org.gradle.api.tasks.Delete
import org.gradle.kotlin.dsl.*

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// إعادة توجيه مجلد البناء إلى مسار خارجي
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// مهمة تنظيف
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// buildscript بصيغة Kotlin DSL
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.3")
    }
}
