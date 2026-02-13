#!/usr/bin/env bash
# Switch Firestore AsyncClient to REST transport (avoids grpcio native build on Android).
# Applied by setup.sh and update.sh after cloning/pulling the conduit repo.

set -euo pipefail

VECTORSTORE="${1:-$HOME/conduit/server/vectorstore.py}"

if [ ! -f "$VECTORSTORE" ]; then
    echo "WARN: vectorstore.py not found at $VECTORSTORE — skipping patch"
    exit 0
fi

if grep -q 'transport="rest"' "$VECTORSTORE"; then
    echo "Firestore REST patch already applied"
    exit 0
fi

sed -i 's/_db = AsyncClient(project=project)/_db = AsyncClient(project=project, transport="rest")/' "$VECTORSTORE"
echo "Firestore REST patch applied to $VECTORSTORE"
