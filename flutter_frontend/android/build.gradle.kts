plugins {
    id("com.dynatrace.instrumentation") version "8.333.1.1006"
}
extra["dynatrace.instrumentationFlavor"] = "flutter"
dynatrace {
    configurations {
        create("defaultConfig") {
            autoStart{
                applicationId("40a4f0a1-14a1-4555-b434-fa95b0935988")
                beaconUrl("https://bf40364blh.bf-sprint.dynatracelabs.com/mbeacon")
            }
            agentBehavior.startupLoadBalancing(true)
            agentBehavior.startupWithGrailEnabled(true)
        }
    }
}
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}