// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XiaobaoCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "XiaobaoCore", targets: ["XiaobaoCore"])],
    targets: [
        .target(name: "XiaobaoCore", path: "Sources/Core", exclude: ["Localization/README.md", "Atmosphere/README.md", "CityWeather/README.md", "GPA/README.md", "LessonActivity/README.md", "Personalization/README.md", "Planner/README.md", "SchoolPortalData/README.md", "SchoolAssignments/README.md", "SchoolTimetable/README.md", "Tasks/README.md"]),
        .testTarget(name: "XiaobaoCoreTests", dependencies: ["XiaobaoCore"], path: "Tests/Core")
    ]
)
