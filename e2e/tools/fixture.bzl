"""Generated compiler inputs: no source build or compiler in this consumer."""

def _impl(ctx):
    ctx.actions.write(ctx.outputs.header, "#define IDS_HELLO 42\n#define IDR_PAYLOAD 43\n")
    ctx.actions.write(ctx.outputs.asset, "Explicit generated resource input.\n")
    ctx.actions.write(ctx.outputs.idl, """import "unknwn.idl";
[
    object,
    uuid(3b972cc4-ef6a-4d70-9a48-7829556e980c),
    pointer_default(unique)
]
interface IExample : IUnknown
{
    HRESULT Ping([out, retval] long *value);
};
""")
    return [DefaultInfo(files = depset([ctx.outputs.header, ctx.outputs.asset, ctx.outputs.idl]))]

generated_inputs = rule(
    implementation = _impl,
    outputs = {"header": "%{name}/resource_ids.h", "asset": "%{name}/payload.txt", "idl": "%{name}/example.idl"},
)
