plugins {
    id("java")
    id("application")
}

application {
    mainClass = "jp.co.yumemi.koma.UseLibrary"
}

repositories {
    val r2Url = project.findProperty("r2_maven_url")
    if (r2Url != null) {
        maven {
            name = "R2"
            url = uri(r2Url)
        }
    }
}

dependencies {
    if (project.hasProperty("r2_maven_url")) {
        implementation(group = "jp.co.yumemi.koma", name = "lib", version = "1.3")
    }
}
