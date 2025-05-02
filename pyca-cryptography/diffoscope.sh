#!/usr/bin/env bash
set -euo pipefail
# Helper script to run diffoscope on two files, and produce the diff as both
# JSON (versatile) and HTML (readable).
#
# Motivation: diffoscope is slow. Its default output is a text diff, which is
# often somewhat useless, because it is not very readable and cannot be
# converted to HTML. The JSON output format *can* be converted to HTML. This
# script first invokes diffoscope with JSON output format. It then converts that
# JSON output to HTML, which is very readable. The JSON->HTML conversion is
# quite fast.
#
# This way we do not waste time re-diffing files from scratch when we need the
# HTML version. The script also serves to document the apparently undocumented
# fact that `diffoscope --load-existing-diff diff.txt --html diff.html` does not
# work, but `diffoscope --load-existing-diff diff.json --html diff.html` does.

_diffoscope() {
  local file1="$1" file2="$2"
  local _f1 _f2 json_diff html_diff

  _f1=$(printf "%s" "$file1" | tr '/' '_')
  _f2=$(printf "%s" "$file2" | tr '/' '_')

  # file1="$(realpath "$file1")"
  # file2="$(realpath "$file2")"

  json_diff="${_f1}--vs--${_f2}.json"
  # json_diff=$(realpath "${json_diff}")
  html_diff="${json_diff}.html"
  if [ -f "$json_diff" ] || [ -f "$html_diff" ]; then
    printf '%s' "JSON and/or HTML output paths already exist. Aborting." >&2
    return 2
  fi

  docker pull registry.salsa.debian.org/reproducible-builds/diffoscope

  # We need to create it as a file so that Docker will know it should be a file
  # and not assume it should create a new empty directory.
  touch "$json_diff"
  chmod a+rw "$json_diff" # TODO find a better way

  # Create the diff.
  # -w "$(pwd)" \
  time docker run --rm -t \
    -w "/_" \
    -v "$(realpath "$file1")":"/a/$file1":ro \
    -v "$(realpath "$file2")":"/b/$file2":ro \
    -v "$(realpath "$json_diff")":"/_/$json_diff":rw \
    registry.salsa.debian.org/reproducible-builds/diffoscope \
    --json "/_/$json_diff" \
    "/a/$file1" \
    "/b/$file2" ||
    {
      retcode=$?
      # Diffoscope seems to return retcode 1 when files do not match.
      if [ 0 = $retcode ] || [ 1 = $retcode ]; then
        true
      else
        return $retcode
      fi
    }

  touch "$html_diff"
  chmod a+rw "$html_diff" # TODO find a better way
  # Export the JSON diff to HTML format.
  # -w "$(pwd)" \
  docker run --rm -t \
    -w "/_" \
    -v "$(realpath "$json_diff")":"/_/$json_diff":ro \
    -v "$(realpath "$html_diff")":"/_/$html_diff":rw \
    registry.salsa.debian.org/reproducible-builds/diffoscope \
    --load-existing-diff "/_/$json_diff" \
    --html "/_/$html_diff"
}

_diffoscope "$1" "$2"
