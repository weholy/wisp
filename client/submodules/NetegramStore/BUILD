objc_library(
    name = "NetegramStore",
    enable_modules = True,
    module_name = "NetegramStore",
    # Only .m here: every header this module has is public and lives under PublicHeaders.
    # A glob that matches nothing is a load-phase error in Bazel, not an empty list.
    srcs = glob([
        "Sources/**/*.m",
    ]),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    sdk_frameworks = [
        "Foundation",
    ],
    visibility = [
        "//visibility:public",
    ],
)
