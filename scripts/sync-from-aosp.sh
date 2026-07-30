#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
manifest="$repo_root/manifest/source-paths.txt"

usage() {
	cat <<'EOF'
Usage: scripts/sync-from-aosp.sh SOURCE_TREE [REF] [DESTINATION]

Copy the paths in manifest/source-paths.txt from an AOSP kernel Git object into
this study repository (or DESTINATION). Existing files in those paths may be
overwritten; files not present in the new source revision are not deleted.

Examples:
  scripts/sync-from-aosp.sh /path/to/kernel/common aosp/android15-6.6
  scripts/sync-from-aosp.sh /path/to/kernel/common <commit> /tmp/study-tree
EOF
}

if (( $# < 1 || $# > 3 )); then
	usage >&2
	exit 2
fi

source_tree=$(cd -- "$1" && pwd)
ref=${2:-aosp/android15-6.6}
destination=${3:-$repo_root}
mkdir -p -- "$destination"
destination=$(cd -- "$destination" && pwd)

if [[ "$source_tree" == "$destination" ]]; then
	echo "refusing to extract into the source kernel tree" >&2
	exit 1
fi

commit=$(git -C "$source_tree" rev-parse --verify "$ref^{commit}")
mapfile -t source_paths < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$manifest")

for path in "${source_paths[@]}"; do
	if ! git -C "$source_tree" cat-file -e "$commit:$path"; then
		echo "manifest path does not exist at $commit: $path" >&2
		exit 1
	fi
done

git -C "$source_tree" archive --format=tar "$commit" -- "${source_paths[@]}" |
	tar -xf - -C "$destination"

commit_date=$(git -C "$source_tree" show -s --format=%cs "$commit")
subject=$(git -C "$source_tree" show -s --format=%s "$commit")
version=$(git -C "$source_tree" show "$commit:Makefile" |
	awk '/^VERSION =/{v=$3} /^PATCHLEVEL =/{p=$3} /^SUBLEVEL =/{s=$3} END{print v "." p "." s}')
remote=$(git -C "$source_tree" remote get-url aosp 2>/dev/null || true)

{
	printf 'AOSP_REMOTE=%s\n' "${remote:-unknown}"
	printf 'AOSP_REF=%s\n' "$ref"
	printf 'AOSP_COMMIT=%s\n' "$commit"
	printf 'AOSP_COMMIT_DATE=%s\n' "$commit_date"
	printf 'KERNEL_VERSION=%s\n' "$version"
	printf 'AOSP_SUBJECT=%s\n' "$subject"
} >"$destination/SOURCE.lock"

printf 'Synced %s (%s) into %s\n' "$commit" "$version" "$destination"
