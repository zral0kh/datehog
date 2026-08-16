#!/usr/bin/env bash
# Release pipeline for datehog. Invoked by `make deploy VERSION=vX.Y.Z`; not
# meant to be run by hand. See the Makefile header for the stage list.
set -euo pipefail
cd "$(dirname "$0")/.."

PACKAGES_FORK=${PACKAGES_FORK:-$HOME/.local/share/typst/packages/preview-packages}
UPSTREAM_SLUG=typst/packages
PKG=datehog

raw=${1:?usage: release.sh vX.Y.Z}
[[ "$raw" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || {
  echo "error: version must look like vX.Y.Z, got '$raw'" >&2
  exit 1
}
version=${BASH_REMATCH[1]}
tag="v$version"

# The version that matters for the "must be greater" check is the last one
# actually published on GitHub, not typst.toml -- the developer may have
# already bumped typst.toml ahead of running this.
repo_slug=$(gh repo view --json nameWithOwner -q .nameWithOwner)
published_tag=$(gh release list --repo "$repo_slug" --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)
published=${published_tag#v}
published=${published:-0.0.0}
if [[ "$(printf '%s\n%s\n' "$published" "$version" | sort -V | tail -1)" != "$version" || "$published" == "$version" ]]; then
  echo "error: $version must be greater than the last published version ($published)" >&2
  exit 1
fi

grep -qxF "## $tag" CHANGELOG.md || {
  echo "error: CHANGELOG.md has no '## $tag' section -- add one before deploying" >&2
  exit 1
}

echo "== running tests =="
./tests/run.sh --all

echo
echo "== syncing version -> $version =="
sed -i -E "s/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"\$/version = \"$version\"/" typst.toml
sed -i -E "s#(@preview/datehog:)[0-9]+\.[0-9]+\.[0-9]+#\1$version#" README.md src/lib.typ
if ! git diff --quiet -- typst.toml README.md src/lib.typ; then
  git add typst.toml README.md src/lib.typ
  git commit -m "Bump version to $version"
else
  echo "   already at $version, nothing to bump"
fi

echo
echo "== tagging and releasing on origin =="
git push origin HEAD
git tag "$tag"
git push origin "$tag"
# GitHub slugs a "## vX.Y.Z" header by lowercasing and dropping the dots.
anchor="v${version//./}"
notes="For changes in this version see [$tag in the changelog](https://github.com/$repo_slug/blob/$tag/CHANGELOG.md#$anchor)."
gh release create "$tag" --title "$tag" --notes "$notes"

echo
echo "== staging packages/preview/$PKG/$version =="
dest="$PACKAGES_FORK/packages/preview/$PKG/$version"
[[ -d "$PACKAGES_FORK" ]] || { echo "error: packages fork not found at $PACKAGES_FORK" >&2; exit 1; }
mkdir -p "$dest"
rsync -a --delete \
  --exclude .git --exclude tests --exclude scripts --exclude Makefile \
  --exclude requirements.txt --exclude .gitignore --exclude .venv \
  ./ "$dest/"

echo
echo "== pushing to packages fork =="
branch="$PKG-$version"
( cd "$PACKAGES_FORK" \
  && git switch -c "$branch" main \
  && git add "packages/preview/$PKG/$version" \
  && git commit -m "$PKG: add $version" \
  && git push -u origin "$branch" )

echo
echo "== open the PR against $UPSTREAM_SLUG =="
fork_owner=$(cd "$PACKAGES_FORK" && gh repo view --json owner -q .owner.login)
echo "https://github.com/$UPSTREAM_SLUG/compare/main...$fork_owner:packages:$branch?expand=1"
