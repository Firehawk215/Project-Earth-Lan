plugins {
    id("org.jetbrains.kotlin.jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnit()
    testLogging {
        events("passed", "failed", "skipped")
        showStandardStreams = true
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}

// Selbsttest gegen den C#-Kern (Vermittler laeuft ausserhalb): gradle :core:selfTest -PselfTestArgs="kk 39890"
tasks.register<JavaExec>("selfTest") {
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("de.projectearth.support.core.SelfTest")
    args = ((project.findProperty("selfTestArgs") as String?) ?: "unit").split(" ")
}
