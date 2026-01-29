import org.gradle.api.file.Directory
import org.gradle.api.tasks.compile.JavaCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter 默认生成：把 build 输出到项目根目录的 build/
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

subprojects {
    // --- Workaround for Android Gradle Plugin 8+ namespace requirement ---
    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                val current = getNamespace.invoke(androidExt) as? String
                if (current.isNullOrBlank()) {
                    val ns = project.group.toString().takeIf { it.isNotBlank() }
                        ?: "third.party.${project.name.replace('-', '_')}"
                    setNamespace.invoke(androidExt, ns)
                }
            } catch (_: Throwable) {
                // Ignore if the Android extension doesn't expose namespace (older AGP).
            }
        }
    }

    // --- Fix: unify JVM toolchain/targets across Java & Kotlin (release build) ---
    // 1) Force all JavaCompile tasks (including plugins) to target Java 21
    tasks.withType(JavaCompile::class.java).configureEach {
        sourceCompatibility = "21"
        targetCompatibility = "21"
    }

    // 2) Force Kotlin to use JDK 21 toolchain WITHOUT touching kotlinOptions/compilerOptions DSL
    fun applyKotlinToolchain21() {
        val kotlinExt = extensions.findByName("kotlin")
        if (kotlinExt != null) {
            try {
                val m = kotlinExt.javaClass.methods.firstOrNull {
                    it.name == "jvmToolchain" && it.parameterCount == 1 &&
                        (it.parameterTypes[0] == Int::class.javaPrimitiveType || it.parameterTypes[0] == Int::class.java)
                }
                m?.invoke(kotlinExt, 21)
            } catch (_: Throwable) {
                // Ignore: not supported by this Kotlin plugin version
            }
        }
    }

    // Kotlin Android plugin ids (new + legacy)
    plugins.withId("org.jetbrains.kotlin.android") { applyKotlinToolchain21() }
    plugins.withId("kotlin-android") { applyKotlinToolchain21() }

    // Kotlin JVM plugin ids (new + legacy)
    plugins.withId("org.jetbrains.kotlin.jvm") { applyKotlinToolchain21() }
    plugins.withId("kotlin") { applyKotlinToolchain21() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
