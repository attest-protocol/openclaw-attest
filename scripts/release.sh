#!/usr/bin/env bash
#
# scripts/release.sh — Automate the openclaw release flow
#
# Usage:
#   scripts/release.sh [--dry-run] <patch|minor|major|X.Y.Z>
#
# Steps:
#   1. Validate preconditions (clean tree, on main, required tools present)
#   2. Compute new version
#   3. Promote CHANGELOG.md [Unreleased] to a versioned entry
#   4. Bump package.json
#   5. Commit, tag, and push
#   6. Create GitHub Release — triggers publish.yml → npm publish
set -euo pipefail

cd "$(dirname "$0")/.." || { echo "error: cannot change to repo root" >&2; exit 1; }

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
  echo "Usage: $(basename "$0") [--dry-run] <patch|minor|major|X.Y.Z>" >&2
  echo >&2
  echo "  patch|minor|major  Bump the current version by that increment" >&2
  echo "  X.Y.Z              Use this exact version" >&2
  echo "  --dry-run          Print every step; make no changes" >&2
  exit 1
}

# ── Arguments ─────────────────────────────────────────────────────────────────

DRY_RUN=false
BUMP=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -*)        usage ;;
    *)
      [[ -n "$BUMP" ]] && usage
      BUMP="$arg"
      ;;
  esac
done

[[ -z "$BUMP" ]] && usage

# ── Helpers ───────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }

# run <cmd> [args...] — execute normally, or just print in dry-run mode
run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run]" "$@"
  else
    "$@"
  fi
}

# ── Preconditions ─────────────────────────────────────────────────────────────

for tool in gh git node npm; do
  command -v "$tool" &>/dev/null || die "'$tool' not found in PATH"
done

gh auth status &>/dev/null || die "gh is not authenticated — run 'gh auth login' first"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] || die "must be on main branch (currently on '$BRANCH')"

git diff --quiet          || die "unstaged changes present — commit or stash first"
git diff --cached --quiet || die "staged changes present — commit or stash first"

run git pull --ff-only

# ── Compute new version ───────────────────────────────────────────────────────

CURRENT_VERSION=$(node -p "require('./package.json').version")

[[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "package.json version '$CURRENT_VERSION' is not a clean X.Y.Z semver (prerelease versions are not supported)"

IFS='.' read -r VER_MAJOR VER_MINOR VER_PATCH <<< "$CURRENT_VERSION"

case "$BUMP" in
  patch)
    NEW_VERSION="${VER_MAJOR}.${VER_MINOR}.$((VER_PATCH + 1))"
    ;;
  minor)
    NEW_VERSION="${VER_MAJOR}.$((VER_MINOR + 1)).0"
    ;;
  major)
    NEW_VERSION="$((VER_MAJOR + 1)).0.0"
    ;;
  *)
    [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || die "invalid argument '$BUMP' — must be patch/minor/major or X.Y.Z"
    NEW_VERSION="$BUMP"
    ;;
esac

TAG="v${NEW_VERSION}"
RELEASE_DATE=$(date -u +%Y-%m-%d)

echo "current: ${CURRENT_VERSION}"
echo "    new: ${NEW_VERSION}  (${TAG})"
[[ "$DRY_RUN" == true ]] && echo "(dry-run — no changes will be made)"
echo

if git rev-parse "$TAG" &>/dev/null; then
  die "tag '$TAG' already exists"
fi

# ── Update CHANGELOG.md ───────────────────────────────────────────────────────

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] CHANGELOG.md: '## [Unreleased]' → '## [${NEW_VERSION}] - ${RELEASE_DATE}'"
else
  export NEW_VERSION RELEASE_DATE
  node << 'JSEOF'
const fs = require('fs');
const src = fs.readFileSync('CHANGELOG.md', 'utf8');
const { NEW_VERSION, RELEASE_DATE } = process.env;
const out = src.replace(
  /^## \[Unreleased\]/m,
  `## [Unreleased]\n\n## [${NEW_VERSION}] - ${RELEASE_DATE}`,
);
if (out === src) {
  process.stderr.write('error: CHANGELOG.md has no "## [Unreleased]" section\n');
  process.exit(1);
}
fs.writeFileSync('CHANGELOG.md', out);
JSEOF
fi

# ── Bump package.json ─────────────────────────────────────────────────────────

run npm version "$NEW_VERSION" --no-git-tag-version

# ── Commit, tag, push ─────────────────────────────────────────────────────────

run git add CHANGELOG.md package.json
run git commit -m "chore(release): ${TAG}"
run git tag "$TAG"
run git push origin main "$TAG"

# ── Create GitHub Release ─────────────────────────────────────────────────────

# If this step fails, the tag is already pushed. Retry with:
#   gh release create "$TAG" --title "$TAG" --generate-notes
run gh release create "$TAG" \
  --title "$TAG" \
  --generate-notes

echo
echo "Done. ${TAG} is live — publish.yml will handle npm publishing."
