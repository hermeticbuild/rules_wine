#!/usr/bin/env bash
# Inspect the compiler products declared as this test's runfiles.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo >&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
set -euo pipefail
bin=$(rlocation "$1")
scratch=$TEST_TMPDIR
if [[ $2 == strip ]]; then
  grep -q 'bazel-out/cfg/' "$bin/messages.rc"
elif grep -q 'bazel-out/cfg/' "$bin/messages.rc"; then
  exit 1
fi
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
resources "$bin/makevars/messages.res" > "$scratch/makevars.txt"
resources "$bin/run/messages.res" > "$scratch/run.txt"
cmp "$scratch/messages.txt" "$scratch/inline.txt"
cmp "$scratch/messages.txt" "$scratch/makevars.txt"
cmp "$scratch/messages.txt" "$scratch/run.txt"
grep -q 'MSG_TOOLS_HELLO' "$bin/makevars/messages.h"
# One message block, ID 1001, UTF-16 table entry, complete message and terminator.
grep -qx '11:1:01000000e9030000e90300001000000034000100480065006c006c006f002000660072006f006d002000570069006e006500200074006f006f006c0073002e000a000000' "$scratch/messages.txt"
resources "$bin/nested/resources.res" > "$scratch/resources.txt"
grep -qx "10:43:$(hex "$bin/generated/assets/payload.txt")" "$scratch/resources.txt"
# STRINGTABLE block 3 contains string ID 42 (Wine tools: café) at index 10.
grep -qx '6:3:00000000000000000000000000000000000000001000570069006e006500200074006f006f006c0073003a002000630061006600e90000000000000000000000' "$scratch/resources.txt"
resources "$bin/run/unicode.res" > "$scratch/unicode.txt"
grep -qx '6:3:00000000000000000000000000000000000000001000570069006e006500200074006f006f006c0073003a002000630061006600e90000000000000000000000' "$scratch/unicode.txt"
# A single -D argument preserves quotes and spaces.
resources "$bin/run/quoted.res" > "$scratch/quoted.txt"
grep -qx '6:3:00000000000000000000000000000000000000001200570069006e006500200074006f006f006c0073003a002000710075006f0074006500640000000000000000000000' "$scratch/quoted.txt"
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
cmp "$bin/makevars/interfaces.tlb" "$bin/run/interfaces.tlb"
typelib=$(hex "$bin/makevars/interfaces.tlb")
[[ $typelib == 4d534654* ]]
[[ $typelib == *8330d07c84786d4d8d79b69a94c3f94b* ]]
[[ $typelib == *7374646f6c65322e746c62* ]]
