#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

short_sha() {
  local repo="$1"
  local ref="$2"
  git -C "$repo" rev-parse --short=9 "$ref"
}

has_ref() {
  local repo="$1"
  local ref="$2"
  git -C "$repo" rev-parse --verify "$ref" >/dev/null 2>&1
}

ahead_behind() {
  local repo="$1"
  local left="$2"
  local right="$3"
  git -C "$repo" rev-list --left-right --count "${left}...${right}"
}

reachable_from() {
  local repo="$1"
  local base="$2"
  local head="$3"
  git -C "$repo" merge-base --is-ancestor "$base" "$head"
}

worktree_state() {
  local repo="$1"
  if git -C "$repo" diff --quiet --ignore-submodules=all HEAD -- && \
     [[ -z "$(git -C "$repo" ls-files --others --exclude-standard)" ]]; then
    echo "clean"
  else
    echo "dirty"
  fi
}

print_header() {
  printf "\n== %s ==\n" "$1"
}

print_repo_summary() {
  local name="$1"
  local repo="$2"
  local upstream_ref="$3"

  print_header "$name"
  printf "path: %s\n" "$repo"
  printf "head: %s\n" "$(short_sha "$repo" HEAD)"
  printf "worktree: %s\n" "$(worktree_state "$repo")"

  if has_ref "$repo" "$upstream_ref"; then
    read -r ahead behind < <(ahead_behind "$repo" "$upstream_ref" HEAD)
    printf "vs %s: ahead %s, behind %s\n" "$upstream_ref" "$behind" "$ahead"
  else
    printf "vs %s: unavailable\n" "$upstream_ref"
  fi
}

print_component_summary() {
  local name="$1"
  local repo="$2"
  local expected_ref="$3"
  local upstream_ref="$4"
  local mode="$5"
  local candidate_ref="${6:-}"

  print_header "$name"
  printf "path: %s\n" "$repo"
  printf "mode: %s\n" "$mode"
  printf "head: %s\n" "$(short_sha "$repo" HEAD)"
  printf "worktree: %s\n" "$(worktree_state "$repo")"

  if has_ref "$repo" "$expected_ref"; then
    printf "expected branch: %s (%s)\n" "$expected_ref" "$(short_sha "$repo" "$expected_ref")"
    if reachable_from "$repo" HEAD "$expected_ref"; then
      printf "pin ancestry: HEAD is reachable from %s\n" "$expected_ref"
    else
      printf "pin ancestry: WARNING HEAD is NOT reachable from %s\n" "$expected_ref"
    fi
  else
    printf "expected branch: %s (missing)\n" "$expected_ref"
  fi

  if has_ref "$repo" "$upstream_ref"; then
    printf "upstream branch: %s (%s)\n" "$upstream_ref" "$(short_sha "$repo" "$upstream_ref")"
    read -r ahead behind < <(ahead_behind "$repo" "$upstream_ref" HEAD)
    printf "vs %s: ahead %s, behind %s\n" "$upstream_ref" "$behind" "$ahead"
  else
    printf "upstream branch: %s (missing)\n" "$upstream_ref"
  fi

  if [[ -n "$candidate_ref" ]]; then
    if has_ref "$repo" "$candidate_ref"; then
      printf "review branch: %s (%s)\n" "$candidate_ref" "$(short_sha "$repo" "$candidate_ref")"
    else
      printf "review branch: %s (missing)\n" "$candidate_ref"
    fi
  fi
}

check_doc_contains_pin() {
  local doc_path="$1"
  local repo="$2"
  local pin
  pin="$(short_sha "$repo" HEAD)"

  print_header "Doc Check"
  printf "doc: %s\n" "$doc_path"
  if rg -q "$pin" "$doc_path"; then
    printf "pin reference: found %s\n" "$pin"
  else
    printf "pin reference: WARNING missing %s\n" "$pin"
  fi
}

main() {
  cd "$REPO_ROOT"

  print_repo_summary "cmux" "$REPO_ROOT" "upstream/main"
  print_component_summary \
    "ghostty" \
    "$REPO_ROOT/ghostty" \
    "origin/main" \
    "upstream/main" \
    "fork-carried" \
    "origin/sid-upstream-sync-apr13-clean"
  check_doc_contains_pin "$REPO_ROOT/docs/ghostty-fork.md" "$REPO_ROOT/ghostty"

  print_component_summary \
    "vendor/bonsplit" \
    "$REPO_ROOT/vendor/bonsplit" \
    "origin/main" \
    "origin/main" \
    "tracking-upstream"

  print_component_summary \
    "vendor/ctap2" \
    "$REPO_ROOT/vendor/ctap2" \
    "origin/main" \
    "origin/main" \
    "fork-owned-library"

  print_component_summary \
    "vendor/zig-crypto" \
    "$REPO_ROOT/vendor/zig-crypto" \
    "origin/main" \
    "origin/main" \
    "fork-owned-library"

  print_component_summary \
    "vendor/zig-keychain" \
    "$REPO_ROOT/vendor/zig-keychain" \
    "origin/main" \
    "origin/main" \
    "fork-owned-library"

  print_component_summary \
    "vendor/zig-notify" \
    "$REPO_ROOT/vendor/zig-notify" \
    "origin/main" \
    "origin/main" \
    "fork-owned-library"

  print_component_summary \
    "homebrew-cmux" \
    "$REPO_ROOT/homebrew-cmux" \
    "origin/main" \
    "origin/main" \
    "tracking-upstream"
}

main "$@"
