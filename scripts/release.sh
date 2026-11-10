#!/bin/bash
# Calendar-version release for cl_quick: YY.M.R (see README ▸ Versioning), modelled on cl_audit's scripts/release.sh.
# YY.M is the release DATE's year and month, never "last month + 1"; R counts releases within that month and starts
# again at 0 when the month changes, skipping burned numbers and existing tags. The one exception is the very first
# release of the month in VERSION itself: while v<VERSION> isn't tagged yet, VERSION is the number to release (this is
# how 26.11.0 goes out, as it was set before any release).
#
#   scripts/release.sh --dry-run   print the next version
#   scripts/release.sh             bump VERSION, date the CHANGELOG's Unreleased notes,
#                                  commit "release X" and tag vX (nothing is built or pushed)
#   scripts/release.sh --nobump    the same without changing VERSION
#   scripts/release.sh --local     only build dist/cl_quick.zip and dist/cl_quick.dmg from the current tree, to check
#                                  the packaging: no version change, no commit, no tag, no push, any branch
#   scripts/release.sh --push      the release above, then build dist/cl_quick.zip and dist/cl_quick.dmg, push main and
#                                  the tag, and publish the GitHub Release on n-uf/cl_quick with both files.
#                                  Refuses to run while there is no `origin` remote for n-uf/cl_quick.
#
# Signing is the same as cl_audit's: ad hoc (build.sh), no Developer ID and no notarization, so the README and the
# release notes tell people to use Open Anyway the first time. Nothing here names a certificate or a keychain profile.
# Test overrides: CALENDAR_VERSION_TODAY=YYYY-MM-DD, CALENDAR_VERSION_CURRENT=YY.M.R
set -euo pipefail
cd "$(dirname "$0")/.."

repo="n-uf/cl_quick"
name="cl_quick"

# Numbers never to use again (for example a tag that was pushed and then deleted). None yet.
BURNED=" "

dry=0 nobump=0 push=0 local_only=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --nobump) nobump=1 ;;
    --push) push=1 ;;
    --local) local_only=1 ;;
    *) echo "unknown option $a" >&2; exit 1 ;;
  esac
done
if [ $local_only = 1 ] && { [ $push = 1 ] || [ $nobump = 1 ] || [ $dry = 1 ]; }; then
  echo "--local stands alone: it only builds the zip and the disk image" >&2; exit 1
fi

# Builds dist/cl_quick.zip and dist/cl_quick.dmg from build/cl_quick.app, as cl_audit does, and checks that the app on
# the image is the zip's app (same code directory hash) and still passes its signature check.
package() {
  local ver stage zip_cd dmg_cd
  ver="$(tr -d '[:space:]' < VERSION)"
  ./build.sh --no-install >/dev/null
  mkdir -p dist && rm -f "dist/$name.zip" "dist/$name.dmg"
  # The file names never change, so https://github.com/$repo/releases/latest/download/$name.zip is always the newest.
  ditto -c -k --keepParent "build/$name.app" "dist/$name.zip"

  # The same app as a disk image: the app and an Applications shortcut to drag it onto.
  stage="$(mktemp -d)"
  # whatever fails from here on, no image stays mounted and no temp folder stays behind
  trap 'hdiutil detach -quiet -force "$stage/mnt" 2>/dev/null || true; rm -rf "$stage"' RETURN
  ditto "build/$name.app" "$stage/$name.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -quiet -volname "$name $ver" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "dist/$name.dmg"
  hdiutil verify -quiet "dist/$name.dmg"
  mkdir "$stage/mnt"
  hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$stage/mnt" "dist/$name.dmg"
  zip_cd="$(codesign -dvvv "build/$name.app" 2>&1 | grep '^CDHash=' || true)"
  dmg_cd="$(codesign -dvvv "$stage/mnt/$name.app" 2>&1 | grep '^CDHash=' || true)"
  codesign --verify --deep --strict "$stage/mnt/$name.app" || { echo "the disk image's app fails its signature check" >&2; return 1; }
  hdiutil detach -quiet "$stage/mnt" || hdiutil detach -quiet -force "$stage/mnt"
  [ -n "$zip_cd" ] && [ "$zip_cd" = "$dmg_cd" ] || { echo "the disk image's app differs from the zip's ($zip_cd vs $dmg_cd)" >&2; return 1; }
  echo "packaged $name $ver: dist/$name.zip $(du -h "dist/$name.zip" | cut -f1), dist/$name.dmg $(du -h "dist/$name.dmg" | cut -f1)"
}

if [ $local_only = 1 ]; then
  package
  exit 0
fi

current="${CALENDAR_VERSION_CURRENT:-$(tr -d '[:space:]' < VERSION)}"
if [[ ! $current =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "VERSION \"$current\" is not a three-part number such as 26.11.0" >&2; exit 1
fi
cy=$((10#${BASH_REMATCH[1]})) cm=$((10#${BASH_REMATCH[2]})) cr=$((10#${BASH_REMATCH[3]}))

today="${CALENDAR_VERSION_TODAY:-$(date +%F)}"
if [[ ! $today =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then echo "date \"$today\" is not YYYY-MM-DD" >&2; exit 1; fi
ty=$((10#${today:2:2})) tm=$((10#${today:5:2}))

if [ $nobump = 1 ]; then
  next="$current"
else
  if [ $cy = $ty ] && [ $cm = $tm ]; then
    # VERSION itself is the next release while it has never been tagged; otherwise count on from it.
    if git rev-parse -q --verify "refs/tags/v$current" >/dev/null; then r=$((cr + 1)); else r=$cr; fi
  else
    r=0
  fi
  while [[ $BURNED == *" $ty.$tm.$r "* ]] || git rev-parse -q --verify "refs/tags/v$ty.$tm.$r" >/dev/null; do r=$((r + 1)); done
  next="$ty.$tm.$r"
fi

if [ $dry = 1 ]; then echo "$next"; exit 0; fi

# Pushing needs the GitHub repo. Refuse before anything changes.
if [ $push = 1 ]; then
  if ! origin_url="$(git remote get-url origin 2>/dev/null)"; then
    echo "--push needs an origin remote and there is none yet: pushing and publishing wait for the GitHub repo $repo. Nothing was changed." >&2
    exit 1
  fi
  case "$origin_url" in
    *"github.com/$repo"|*"github.com/$repo.git"|*"github.com:$repo"|*"github.com:$repo.git") ;;
    *) echo "origin is $origin_url, not $repo; refusing to push or publish. Nothing was changed." >&2; exit 1 ;;
  esac
  command -v gh >/dev/null || { echo "--push needs the gh command (GitHub CLI), signed in" >&2; exit 1; }
fi

# Release only a clean main with notes waiting.
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "release from main" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/v$next" >/dev/null; then echo "v$next is already tagged" >&2; exit 1; fi
notes="$(awk '/^## Unreleased/{f=1; next} /^## /{f=0} f' CHANGELOG.md | sed '/^[[:space:]]*$/d')"
if [ -z "$notes" ] || [ "$notes" = "Nothing pending." ]; then
  echo "CHANGELOG.md has no Unreleased notes; add them first" >&2; exit 1
fi

# Unreleased notes become this release's section; Unreleased starts empty again.
awk -v v="$next" -v d="$today" '
  /^## Unreleased/ { print; print ""; print "Nothing pending."; print ""; print "## " v " — " d; next }
  { print }' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
printf '%s\n' "$next" > VERSION

git add VERSION CHANGELOG.md
git commit -q -m "release $next"
git tag -a "v$next" -m "$name $next"
echo "released $next (commit and tag v$next)"

if [ $push = 1 ]; then
  # Build and check both files before anything leaves the Mac.
  package
  zip_sha="$(shasum -a 256 "dist/$name.zip" | awk '{print $1}')"
  dmg_sha="$(shasum -a 256 "dist/$name.dmg" | awk '{print $1}')"

  git push -q origin main
  git push -q origin "v$next"
  echo "pushed main and v$next"

  section="$(awk -v h="## $next " 'index($0, h) == 1 {f=1; next} /^## /{f=0} f' CHANGELOG.md)"
  # The Claude Code version on this Mac, which this release was checked with.
  cc="$(claude --version 2>/dev/null | awk '{print $1}')"
  checked="Checked with Claude Code ${cc:-?}. A newer Claude Code can change how it answers or reports the week; if something stops working, update cl_quick."
  echo "$checked"
  gh release create "v$next" "dist/$name.zip" "dist/$name.dmg" --repo "$repo" --title "$name $next" --notes "$section

---

$checked

**Download:** \`$name.dmg\` below (Apple silicon, macOS 13 or later). Open it and drag $name onto Applications. Or \`$name.zip\`: unzip it and move **$name** to Applications. Either way, $name isn't signed with an Apple Developer ID yet, so the first time macOS says it can't verify the app: open System Settings ▸ Privacy & Security and click **Open Anyway** (once). Or build it from source, see the README.

SHA-256: \`$name.zip\` $zip_sha · \`$name.dmg\` $dmg_sha"
  echo "published the GitHub Release v$next with $name.zip and $name.dmg"
fi
