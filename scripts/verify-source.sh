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
work=$(mktemp -d "${TMPDIR:-/tmp}/pkvm-study-verify.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

source_paths=()
while IFS= read -r path; do
	source_paths+=("$path")
done < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$manifest")

# Compare "<mode> <blob>\t<path>" lines rather than extracting the expected
# tree: the kernel has paths that differ only in case (xt_MARK.h/xt_mark.h),
# which a case-insensitive temporary directory would silently merge.
git -c core.quotePath=false -C "$source_tree" ls-tree -r "$commit" -- "${source_paths[@]}" |
	awk -F'\t' '{split($1, f, " "); print f[1] " " f[3] "\t" $2}' |
	LC_ALL=C sort -t$'\t' -k2 >"$work/expected"

cd -- "$study_tree"
find "${source_paths[@]}" -type f 2>/dev/null | LC_ALL=C sort >"$work/files" || true
find "${source_paths[@]}" -type l 2>/dev/null | LC_ALL=C sort >"$work/links" || true

git hash-object --no-filters --stdin-paths <"$work/files" >"$work/blobs"
while IFS= read -r file; do
	if [[ -x "$file" ]]; then echo 100755; else echo 100644; fi
done <"$work/files" >"$work/modes"
{
	paste -d' ' "$work/modes" "$work/blobs" | paste - "$work/files"
	while IFS= read -r link; do
		blob=$(printf '%s' "$(readlink -- "$link")" | git hash-object --stdin)
		printf '120000 %s\t%s\n' "$blob" "$link"
	done <"$work/links"
} | LC_ALL=C sort -t$'\t' -k2 >"$work/actual"

if ! diff -u --label "AOSP $commit" --label "$study_tree" \
	"$work/expected" "$work/actual"; then
	echo "Source verification failed for $commit" >&2
	exit 1
fi

printf 'All %d manifested files match AOSP commit %s\n' \
	"$(wc -l <"$work/expected")" "$commit"
