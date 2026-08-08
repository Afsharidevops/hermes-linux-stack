#!/usr/bin/env bash
set -Eeuo pipefail

BUNDLE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
[[ -n "$TARGET" ]] || { echo "Usage: $0 /path/to/hermes-linux-stack" >&2; exit 2; }
[[ -f "$TARGET/docker-compose.yml" ]] || { echo "Target does not look like hermes-linux-stack: $TARGET" >&2; exit 1; }

backup="$TARGET/.omniroute-migration-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup"
for f in docker-compose.yml .env.example install.sh manage.sh README.md SECURITY.md ROADMAP.md templates/hermes-config.yaml.template smart-router/README.md smart-router/src/smart_router/config.py scripts/apply-to-upstream.sh scripts/sync-openwebui-config.py scripts/verify-openwebui-backend.py tests/smoke.sh .github/workflows/validate.yml; do
  [[ -e "$TARGET/$f" ]] && { mkdir -p "$backup/$(dirname "$f")"; cp -a "$TARGET/$f" "$backup/$f"; }
done

for f in docker-compose.yml .env.example install.sh manage.sh README.md SECURITY.md ROADMAP.md MIGRATION.md CHANGELOG.md RELEASE_NOTES.md SOURCE_SCOPE.md VERSION templates/hermes-config.yaml.template smart-router/README.md smart-router/src/smart_router/config.py scripts/apply-to-upstream.sh scripts/sync-openwebui-config.py scripts/verify-openwebui-backend.py tests/smoke.sh .github/workflows/validate.yml; do
  mkdir -p "$TARGET/$(dirname "$f")"
  cp -a "$BUNDLE/$f" "$TARGET/$f"
done
mkdir -p "$TARGET/data/omniroute"
touch "$TARGET/data/omniroute/.gitkeep"
rm -f "$TARGET/data/9router/.gitkeep" 2>/dev/null || true
# This helper directly edited the legacy router SQLite schema and is not compatible
# with OmniRoute's storage/API model. The replacement installer does not use it.
rm -f "$TARGET/scripts/bootstrap-openwebui.mjs" 2>/dev/null || true
chmod +x "$TARGET/install.sh" "$TARGET/manage.sh" "$TARGET/scripts/apply-to-upstream.sh" "$TARGET/tests/smoke.sh"

echo "Applied OmniRoute migration overlay. Backup: $backup"
echo "Legacy data/9router was not deleted. Read $TARGET/MIGRATION.md, then run $TARGET/install.sh --no-start."
