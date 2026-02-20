#!/usr/bin/env bash
# Firestore transport patch — grpcio is now available on the tablet,
# so this patch is a no-op. Kept for compatibility with update.sh.
# If grpcio breaks again, re-add transport="rest" logic here
# (requires google-cloud-firestore version that supports it).

set -euo pipefail

VECTORSTORE="${1:-$HOME/conduit/server/vectorstore.py}"

if [ ! -f "$VECTORSTORE" ]; then
    echo "WARN: vectorstore.py not found at $VECTORSTORE — skipping patch"
    exit 0
fi

# Undo the old REST patch if it's still present (library doesn't support it)
if grep -q 'transport="rest"' "$VECTORSTORE"; then
    sed -i 's/_db = AsyncClient(project=project, transport="rest")/_db = AsyncClient(project=project)/' "$VECTORSTORE"
    echo "Firestore REST patch REMOVED (grpcio available, transport param unsupported)"
else
    echo "Firestore patch: no changes needed (using gRPC transport)"
fi
