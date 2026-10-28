#!/usr/bin/env bash
# Inspect compiler products; tools in this script are test-driver dependencies only.
set -euo pipefail
bin=${1:?usage: verify_tools.sh bazel-bin}
scratch=${2:?usage: verify_tools.sh bazel-bin scratch}
hex() { od -An -tx1 -v "$1" | tr -d ' \n\r'; }
resources() {
  od -An -tu1 -v "$1" | awk '
    function u16(p) { return bytes[p] + bytes[p+1]*256 }
    function u32(p) { return u16(p) + u16(p+2)*65536 }
    { for (i=1;i<=NF;i++) bytes[n++]=$i }
    END {
      for (p=0;p<n;) {
        size=u32(p); header=u32(p+4)
        if (header<32 || p+header+size>n || u16(p+8)!=65535 || u16(p+12)!=65535) exit 1
        if (size) {
          printf "%d:%d:", u16(p+10), u16(p+14)
          for (i=p+header;i<p+header+size;i++) printf "%02x",bytes[i]
          printf "\n"
        }
        p=int((p+header+size+3)/4)*4
      }
      if (p!=n) exit 1
    }'
}
grep -q 'MSG_TOOLS_HELLO' "$bin/messages.h"
grep -q 'MSG_TOOLS_HELLO' "$bin/renamed_messages.h"
grep -q 'MESSAGETABLE' "$bin/messages.rc"
if grep -q '\.bin"' "$bin/messages.rc"; then exit 1; fi
resources "$bin/messages.res" > "$scratch/messages.txt"
cmp "$bin/messages.res" "$bin/unicode_messages.res"
resources "$bin/inline_messages.res" > "$scratch/inline.txt"
cmp "$scratch/messages.txt" "$scratch/inline.txt"
# One message block, ID 1001, UTF-16 table entry, complete message and terminator.
grep -qx '11:1:01000000e9030000e90300001000000034000100480065006c006c006f002000660072006f006d002000570069006e006500200074006f006f006c0073002e000a000000' "$scratch/messages.txt"
resources "$bin/nested/resources.res" > "$scratch/resources.txt"
grep -qx "10:43:$(hex "$bin/generated/assets/payload.txt")" "$scratch/resources.txt"
# STRINGTABLE block 3 contains string ID 42 (Wine tools: café) at index 10.
grep -qx '6:3:00000000000000000000000000000000000000001000570069006e006500200074006f006f006c0073003a002000630061006600e90000000000000000000000' "$scratch/resources.txt"
grep -q 'IExampleVtbl' "$bin/example.h"
grep -q 'HRESULT.*Ping' "$bin/example.h"
grep -q '#include "example.h"' "$bin/example_p.c"
grep -q '#include "interfaces.h"' "$bin/interfaces_p.c"
grep -q '#include "tool_rpc.h"' "$bin/rpc_c.c"
grep -q '#include "tool_rpc.h"' "$bin/rpc_s.c"
grep -q 'LIBID_ToolTests' "$bin/interfaces_i.c"
grep -q 'NdrClientCall2' "$bin/rpc_c.c"
grep -q 'NdrServerCall2' "$bin/rpc_s.c"
typelib=$(hex "$bin/interfaces.tlb")
[[ $typelib == 4d534654* ]]
[[ $typelib == *8330d07c84786d4d8d79b69a94c3f94b* ]]
[[ $typelib == *7374646f6c65322e746c62* ]]
