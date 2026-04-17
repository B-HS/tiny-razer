#!/usr/bin/env bash
set -euo pipefail

# Guards against Swift 6.1-only syntax that breaks CI running on Swift 6.0.
# Trailing commas in function parameter lists are a Swift 6.1 feature —
# Xcode 16.2 / Swift 6.0 (the macos-15 GitHub runner default) rejects them.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Scanning Sources/ and Tests/ for Swift 6.1-only trailing commas"

FOUND=0
while IFS= read -r file; do
    # Match: `,\n<whitespace>)` — a trailing comma immediately before a
    # closing paren on a new line. This catches the offending pattern in
    # function declarations, calls, and initializers alike.
    if python3 -c "
import re, sys
with open('$file') as fh:
    src = fh.read()
if re.search(r',\s*\n\s*\)', src):
    print('$file')
    sys.exit(1)
"; then
        continue
    else
        FOUND=1
    fi
done < <(find Sources Tests -name "*.swift" -print)

if [ "$FOUND" = "1" ]; then
    echo ""
    echo "✗ Trailing commas detected in parameter lists — incompatible with Swift 6.0."
    echo "  Remove the trailing comma before the closing ')'."
    echo "  Auto-fix: find Sources Tests -name '*.swift' -exec python3 -c \\"
    echo "     \"import re,sys;p=sys.argv[1];"
    echo "      s=open(p).read();"
    echo "      f=re.sub(r',(\\\\s*\\\\n\\\\s*\\\\))', r'\\\\1', s);"
    echo "      open(p,'w').write(f) if f!=s else None\" {} \\;"
    exit 1
fi

echo "✓ No Swift 6.1-only syntax found."
