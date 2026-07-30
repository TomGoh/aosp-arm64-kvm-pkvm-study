#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
manifest="$repo_root/manifest/source-paths.txt"

if (( $# < 1 || $# > 3 )); then
	echo "Usage: scripts/verify-source.sh SOURCE_TREE [REF] [STUDY_TREE]" >&2
	exit 2
fi

source_tree=$(cd -- "$1" && pwd)
ref=${2:-$(sed -n 's/^AOSP_COMMIT=//p' "$repo_root/SOURCE.lock")}
study_tree=${3:-$repo_root}
study_tree=$(cd -- "$study_tree" && pwd)
commit=$(git -C "$source_tree" rev-parse --verify "$ref^{commit}")
expected=$(mktemp -d /tmp/pkvm-study-verify.XXXXXX)
trap 'rm -rf -- "$expected"' EXIT

mapfile -t source_paths < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$manifest")
git -C "$source_tree" archive --format=tar "$commit" -- "${source_paths[@]}" |
	tar -xf - -C "$expected"

status=0
for path in "${source_paths[@]}"; do
	if ! diff -qr -- "$expected/$path" "$study_tree/$path"; then
		status=1
	fi
done

if (( status != 0 )); then
	echo "Source verification failed for $commit" >&2
	exit "$status"
fi

printf 'All manifested files match AOSP commit %s\n' "$commit"
