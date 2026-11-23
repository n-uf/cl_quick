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
#                                  Refuses to run while there is no `origin` remote for n-uf/cl_quick, gh isn't signed in,
#                                  the repo isn't visible or the tag is already on origin. A failed package undoes the
#                                  release commit and tag; a failed publish keeps the push and prints the retry command.
#   scripts/release.sh --check-signing   the code signing plan (identity, notary profile, what it would sign), nothing else
#
# Signing is the same as cl_audit's: ad hoc (build.sh), unless CL_SIGN_ID names a Developer ID identity; with
# CL_NOTARY_PROFILE too, the zip's app and the disk image are notarized and stapled before anything is pushed
# (scripts/signing.sh, docs/signing.md). Both unset: the build and the release notes are as they always were, with
# Open Anyway the first time. --local does the same signing and notarizing as --push, only without the push.
# Test overrides: CALENDAR_VERSION_TODAY=YYYY-MM-DD, CALENDAR_VERSION_CURRENT=YY.M.R (the second only with --dry-run)
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/signing.sh

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
    --check-signing) check_signing; exit 0 ;;
    *) echo "unknown option $a" >&2; exit 1 ;;
  esac
done
if [ $local_only = 1 ] && { [ $push = 1 ] || [ $nobump = 1 ] || [ $dry = 1 ]; }; then
  echo "--local stands alone: it only builds the zip and the disk image" >&2; exit 1
fi

# Builds dist/cl_quick.zip and dist/cl_quick.dmg from the app build.sh makes, as cl_audit does, and checks that the app on
# the image is the zip's app (same code directory hash) and still passes its signature check. The app is copied out of
# build/ into a temp folder the moment it is built, and everything after (the signature checks, the zip, the notarization
# and stapling, the image) works on that copy: a notarization can take up to 90 minutes, and another ./build.sh in that
# time empties build/. With CL_SIGN_ID the app is checked to be the Developer ID's, with the hardened runtime, by one team
# throughout; with CL_NOTARY_PROFILE too the zip's app and the image are notarized and stapled (the zip and the image
# both carry the stapled app) and Gatekeeper's verdict on both is checked. Nothing is pushed here: a failure returns 1
# and the caller undoes its release commit.
package() {
  local ver zip_cd dmg_cd sig team app
  ver="$(tr -d '[:space:]' < VERSION)"
  # the signing set-up, found out before the long build (--check-signing shows it)
  signing_preflight || return 1
  stage="$(mktemp -d)"
  # whatever fails from here on (an EXIT trap also runs when set -e aborts), no image stays mounted and no temp folder
  # stays behind. $stage is global so the trap can still see it.
  trap 'hdiutil detach -quiet -force "$stage/mnt" 2>/dev/null || true; rm -rf "$stage"' EXIT
  # One release build at a time on this Mac: the lock is held from the build until the app is copied out of build/, so the
  # zip and the disk image always hold the app this build made (never another release's).
  /usr/bin/lockf -k /private/tmp/cl_quick-build.lock bash -c './build.sh --no-install >/dev/null && ditto "build/$2.app" "$1/$2.app"' _ "$stage" "$name"
  app="$stage/$name.app"
  mkdir -p dist && rm -f "dist/$name.zip" "dist/$name.dmg"
  if [ -n "$sign_id" ]; then
    # a Developer ID build: the signature is the Developer ID's, with the hardened runtime (what notarization needs)
    sig="$(codesign -dvv "$app" 2>&1 || true)"
    grep -q '^Authority=Developer ID Application' <<<"$sig" && grep -qE '^CodeDirectory .*flags=0x[0-9a-f]*\(.*runtime' <<<"$sig" \
      || { echo "the app isn't signed with a Developer ID and the hardened runtime" >&2; return 1; }
    # and the whole app by this identity's team
    team="$(sign_team || true)"
    [ -n "$team" ] || { echo "couldn't read the team ID from CL_SIGN_ID's identity" >&2; return 1; }
    codesign --verify --deep --strict -R="anchor apple generic and certificate leaf[subject.OU] = \"$team\"" "$app" \
      || { echo "the app isn't signed by team $team throughout" >&2; return 1; }
  fi
  # The file names never change, so https://github.com/$repo/releases/latest/download/$name.zip is always the newest.
  ditto -c -k --keepParent "$app" "dist/$name.zip"
  if [ -n "$notary_profile" ]; then
    # Apple notarizes the app (the zip is what goes to it); its ticket is stapled into the app, and the zip made again
    # from the stapled app, so the download opens without a network check too
    notarize "dist/$name.zip" || return 1
    staple "$app" || { echo "the app's notarization ticket couldn't be stapled" >&2; return 1; }
    rm -f "dist/$name.zip"
    ditto -c -k --keepParent "$app" "dist/$name.zip"
  fi

  # The same app as a disk image: the app and an Applications shortcut to drag it onto (the stapled app, when notarized).
  ln -s /Applications "$stage/Applications"
  hdiutil create -quiet -volname "$name $ver" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "dist/$name.dmg"
  if [ -n "$sign_id" ]; then
    # the image signed too (made from the stapled app), then notarized and stapled itself
    codesign --force --sign "$sign_id" --timestamp "dist/$name.dmg"
    if [ -n "$notary_profile" ]; then
      notarize "dist/$name.dmg" || return 1
      staple "dist/$name.dmg" || { echo "the disk image's notarization ticket couldn't be stapled" >&2; return 1; }
    fi
  fi
  hdiutil verify -quiet "dist/$name.dmg"
  if [ -n "$notary_profile" ]; then
    # what a downloader's Mac will say: Gatekeeper accepts both, and each carries its ticket
    spctl -a -vv -t exec "$app" || { echo "Gatekeeper rejects the app" >&2; return 1; }
    xcrun stapler validate -q "$app" || { echo "the app's notarization ticket doesn't validate" >&2; return 1; }
    spctl -a -vv -t open --context context:primary-signature "dist/$name.dmg" || { echo "Gatekeeper rejects the disk image" >&2; return 1; }
    xcrun stapler validate -q "dist/$name.dmg" || { echo "the disk image's notarization ticket doesn't validate" >&2; return 1; }
  fi
  mkdir "$stage/mnt"
  hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$stage/mnt" "dist/$name.dmg"
  zip_cd="$(codesign -dvvv "$app" 2>&1 | grep '^CDHash=' || true)"
  dmg_cd="$(codesign -dvvv "$stage/mnt/$name.app" 2>&1 | grep '^CDHash=' || true)"
  codesign --verify --deep --strict "$stage/mnt/$name.app" || { echo "the disk image's app fails its signature check" >&2; return 1; }
  if [ -n "$notary_profile" ]; then
    xcrun stapler validate -q "$stage/mnt/$name.app" || { echo "the disk image's app has no valid notarization ticket" >&2; return 1; }
  fi
  hdiutil detach -quiet "$stage/mnt" || hdiutil detach -quiet -force "$stage/mnt"
  [ -n "$zip_cd" ] && [ "$zip_cd" = "$dmg_cd" ] || { echo "the disk image's app differs from the zip's ($zip_cd vs $dmg_cd)" >&2; return 1; }
  echo "packaged $name $ver: dist/$name.zip $(du -h "dist/$name.zip" | cut -f1), dist/$name.dmg $(du -h "dist/$name.dmg" | cut -f1)"
}

if [ $local_only = 1 ]; then
  package
  exit 0
fi

if [ -n "${CALENDAR_VERSION_CURRENT:-}" ] && [ $dry = 0 ]; then
  echo "CALENDAR_VERSION_CURRENT is a test override and works only with --dry-run" >&2; exit 1
fi
current="${CALENDAR_VERSION_CURRENT:-$(tr -d '[:space:]' < VERSION)}"
if [[ ! $current =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "VERSION \"$current\" is not a three-part number such as 26.11.0" >&2; exit 1
fi
cy=$((10#${BASH_REMATCH[1]})) cm=$((10#${BASH_REMATCH[2]})) cr=$((10#${BASH_REMATCH[3]}))

today="${CALENDAR_VERSION_TODAY:-$(date +%F)}"
if [[ ! $today =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then echo "date \"$today\" is not YYYY-MM-DD" >&2; exit 1; fi
ty=$((10#${today:2:2})) tm=$((10#${today:5:2}))

if [ $((cy * 100 + cm)) -gt $((ty * 100 + tm)) ]; then
  echo "VERSION $current is from a later month than $today; versions never go backwards" >&2; exit 1
fi

if [ $nobump = 1 ]; then
  if [ $cy != $ty ] || [ $cm != $tm ]; then
    echo "--nobump keeps VERSION $current, but a release is numbered by the month it is made in ($ty.$tm.x); drop --nobump" >&2; exit 1
  fi
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
  gh auth status >/dev/null 2>&1 || { echo "gh is not signed in (gh auth status fails); run gh auth login. Nothing was changed." >&2; exit 1; }
  gh repo view "$repo" >/dev/null 2>&1 || { echo "gh can't see the GitHub repo $repo (not created yet, or no access). Nothing was changed." >&2; exit 1; }
  # 0: the tag is already on origin; 2: it isn't; anything else: origin couldn't be asked.
  rc=0; git ls-remote --exit-code --tags origin "refs/tags/v$next" >/dev/null 2>&1 || rc=$?
  case $rc in
    0) echo "v$next already exists on origin; refusing to release it again. Nothing was changed." >&2; exit 1 ;;
    2) ;;
    *) echo "couldn't ask origin about the tag v$next (git ls-remote failed). Nothing was changed." >&2; exit 1 ;;
  esac
  # the signing set-up, found out now too, before the release commit (scripts/release.sh --check-signing shows it)
  signing_preflight || { echo "Nothing was changed." >&2; exit 1; }
fi

# Release only a clean main with notes waiting.
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "release from main" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/v$next" >/dev/null; then echo "v$next is already tagged" >&2; exit 1; fi
# a push needs main to be ahead of origin's: found out now, not at the push after the long notarization
if [ $push = 1 ]; then
  git fetch -q origin main || { echo "couldn't fetch origin's main. Nothing was changed." >&2; exit 1; }
  git merge-base --is-ancestor origin/main HEAD \
    || { echo "origin/main has commits this main doesn't: pull (rebase) first. Nothing was changed." >&2; exit 1; }
fi
notes="$(awk '/^## Unreleased/{f=1; next} /^## /{f=0} f' CHANGELOG.md | sed '/^[[:space:]]*$/d')"
if [ -z "$notes" ] || [ "$notes" = "Nothing pending." ]; then
  echo "CHANGELOG.md has no Unreleased notes; add them first" >&2; exit 1
fi

# Unreleased notes become this release's section; Unreleased starts empty again.
awk -v v="$next" -v d="$today" '
  /^## Unreleased/ { print; print ""; print "Nothing pending."; print ""; print "## " v " — " d; next }
  { print }' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
printf '%s\n' "$next" > VERSION

before="$(git rev-parse HEAD)"          # (main before the release commit: the way back)
git add VERSION CHANGELOG.md
git commit -q -m "release $next"
released="$(git rev-parse HEAD)"
git tag -a "v$next" -m "$name $next"
echo "released $next (commit and tag v$next)"

if [ $push = 1 ]; then
  # Build and check both files before anything leaves the Mac. It runs as its own process (--local) so that set -e
  # and its cleanup trap stay in force inside it. Whatever stops this run before the files are ready (a failed build, zip,
  # notarization or disk image, or Ctrl-C during the notarization's long wait) takes back exactly what it made, a release
  # commit and its tag, so the next run doesn't skip a number: the tag is deleted and main reset to where it was (--keep
  # rolls back nothing else), but only while main is still the release commit. If something else has been committed on top
  # since, main is left alone and the one command that takes out the release commit only is printed. Once both files are
  # ready the release stays: a failed push or publish prints how to finish by hand.
  pushed=0 packaged=0
  undo_release() {
    if [ "$(git rev-parse HEAD)" = "$released" ] && git tag -d "v$next" >/dev/null 2>&1 && git reset -q --keep "$before"; then
      echo "the release commit and the tag v$next are undone, nothing was pushed" >&2
    else
      echo "nothing was pushed; the release commit ${released:0:12} and the tag v$next are local only. Take them back, before any fix:" >&2
      if [ "$(git rev-parse HEAD)" = "$released" ]; then
        echo "git tag -d v$next && git reset --keep $before" >&2
      else
        echo "git tag -d v$next && git rebase --onto $before $released" >&2
        echo "(main has commits on top of the release commit since: that takes out the release commit only)" >&2
      fi
    fi
  }
  on_exit() {
    local rc=$?
    trap - EXIT
    if [ "$rc" != 0 ] && [ "$pushed" = 0 ]; then
      if [ "$packaged" = 0 ]; then
        undo_release
      else
        echo "the files are ready in dist/ but main and v$next are not pushed. Push them, then publish the release:" >&2
        echo "git push --atomic origin main v$next" >&2
        echo "then publish the GitHub Release v$next on $repo with dist/$name.zip and dist/$name.dmg (gh release create)" >&2
      fi
    fi
    exit $rc
  }
  trap on_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  ./scripts/release.sh --local
  packaged=1
  zip_sha="$(shasum -a 256 "dist/$name.zip" | awk '{print $1}')"
  dmg_sha="$(shasum -a 256 "dist/$name.dmg" | awk '{print $1}')"

  # One atomic push: main and the tag both arrive or neither does.
  git push --atomic -q origin main "v$next"
  pushed=1
  echo "pushed main and v$next"

  section="$(awk -v h="## $next " 'index($0, h) == 1 {f=1; next} /^## /{f=0} f' CHANGELOG.md)"
  # The Claude Code version on this Mac, which this release was checked with.
  cc="$(claude --version 2>/dev/null | awk '{print $1}')"
  checked="Checked with Claude Code ${cc:-?}. A newer Claude Code can change how it answers or reports the week; if something stops working, update cl_quick."
  echo "$checked"
  # The notes go to a file so a failed publish can be retried with the very same text.
  notes_file="dist/release-notes-v$next.md"
  # a notarized app opens like any other; an ad hoc one needs Open Anyway once
  if [ -n "$notary_profile" ]; then
    first_open="$name is signed with a Developer ID and notarized by Apple, so it opens like any other app."
  else
    first_open="the first time, macOS says it can't verify the app: open System Settings ▸ Privacy & Security and click **Open Anyway** (once)."
  fi
  printf '%s\n' "$section

---

$checked

**Download:** \`$name.dmg\` below (Apple silicon, macOS 13 or later). Open it and drag $name onto Applications. Or \`$name.zip\`: unzip it and move **$name** to Applications. Either way, $first_open Or build it from source, see the README.

SHA-256: \`$name.zip\` $zip_sha · \`$name.dmg\` $dmg_sha" > "$notes_file"
  if ! gh release create "v$next" "dist/$name.zip" "dist/$name.dmg" --repo "$repo" --title "$name $next" --notes-file "$notes_file"; then
    # main and the tag are already on GitHub: keep them, and retry only the release.
    echo "publishing the GitHub Release failed; main and v$next stay pushed. Retry with:" >&2
    echo "  gh release create v$next dist/$name.zip dist/$name.dmg --repo $repo --title \"$name $next\" --notes-file $notes_file" >&2
    exit 1
  fi
  echo "published the GitHub Release v$next with $name.zip and $name.dmg"
fi
