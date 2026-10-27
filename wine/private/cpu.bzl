"""Supported Windows CPU constraint labels and their runtime identifiers."""

_CPUS = {
    Label("@platforms//cpu:x86_64"): "x86_64",
    Label("@platforms//cpu:aarch64"): "aarch64",
}

def guest_cpu(label):
    """Normalize one supported CPU constraint label."""
    if label not in _CPUS:
        fail("unsupported Windows guest CPU {}; expected @platforms//cpu:x86_64 or @platforms//cpu:aarch64".format(label))
    return _CPUS[label]

def check_guest(binary, runner):
    """Check an optional payload declaration against the selected runtime."""
    if binary.guest_cpu and binary.guest_cpu not in runner.supported_guest_cpus:
        identity = runner.runtime.identity if runner.runtime else "native Windows"
        fail("payload {} declares {}; runtime {} supports {}".format(binary.file, binary.guest_cpu, identity, runner.supported_guest_cpus))
