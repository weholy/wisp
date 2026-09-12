load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatMessageBackground",
    module_name = "ChatMessageBackground",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/NetegramStore:NetegramStore",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
    	"//submodules/Display:Display",
    	"//submodules/TelegramPresentationData:TelegramPresentationData",
    	"//submodules/WallpaperBackgroundNode:WallpaperBackgroundNode",
    	"//submodules/TelegramUI/Components/GlassBackgroundComponent",
    	"//submodules/ComponentFlow:ComponentFlow",
    ],
    visibility = [
        "//visibility:public",
    ],
)
