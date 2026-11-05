allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// The onnxruntime plugin (1.4.1) pins compileSdk 33, but the AndroidX
// libraries it brings in need 34+ (AAR metadata check fails the release
// build). Compile it against a current SDK; its minSdk/targetSdk are
// unchanged, so this does not change runtime behaviour.
subprojects {
    if (name == "onnxruntime") {
        afterEvaluate {
            extensions.getByName("android").withGroovyBuilder { "compileSdkVersion"(36) }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
