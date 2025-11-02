#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/.git/hooks/pre-commit"

cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
"$ROOT/scripts/normalize_xpr.sh" >/dev/null 2>&1 || true
git add "$ROOT/xpr" 2>/dev/null || true
EOF

chmod +x "$HOOK"
echo "[OK] Installed git pre-commit hook to normalize xpr file."