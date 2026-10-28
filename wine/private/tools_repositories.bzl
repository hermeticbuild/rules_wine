"""Generate native tools registrations independently of Wine runners."""

def _impl(ctx):
    ctx.file("BUILD.bazel", "\n".join([
        'load("@rules_wine//wine/private:tools_registrations.bzl", "register_tools")',
        'package(default_visibility = ["//visibility:public"])',
        "register_tools(distributions = " + repr(json.decode(ctx.attr.distributions)) + ")",
        "",
    ]))

tools_registration_repository = repository_rule(
    implementation = _impl,
    attrs = {"distributions": attr.string(mandatory = True)},
)
