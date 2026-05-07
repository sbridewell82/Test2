#!/usr/bin/env bash
# Imports git repositories from a zip file into a GitLab instance.
#
# Usage:
#   GITLAB_TOKEN=<token> ./import_repos.sh <zip-file> <gitlab-url> <namespace>
#
# Arguments:
#   zip-file     Path to the zip file containing repository directories
#   gitlab-url   Base URL of your GitLab instance (e.g. https://gitlab.example.com)
#   namespace    GitLab namespace (username or group path) to import repos into
#
# The zip is expected to contain one directory per repository, each with a .git
# folder (i.e. regular clones). Bare repos (.git is the root) are also supported.
#
# Requires: git, curl, unzip, jq

set -euo pipefail

# ── argument validation ──────────────────────────────────────────────────────

if [[ $# -lt 3 ]]; then
  echo "Usage: GITLAB_TOKEN=<token> $0 <zip-file> <gitlab-url> <namespace>" >&2
  exit 1
fi

ZIP_FILE="$1"
GITLAB_URL="${2%/}"   # strip trailing slash
NAMESPACE="$3"
TOKEN="${GITLAB_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  echo "Error: GITLAB_TOKEN environment variable is not set." >&2
  exit 1
fi

if [[ ! -f "$ZIP_FILE" ]]; then
  echo "Error: zip file not found: $ZIP_FILE" >&2
  exit 1
fi

for cmd in git curl unzip jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
done

# ── helpers ──────────────────────────────────────────────────────────────────

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
warn() { echo "[$(date '+%H:%M:%S')] ⚠ $*" >&2; }
fail() { echo "[$(date '+%H:%M:%S')] ✗ $*" >&2; }

gitlab_api() {
  # gitlab_api <method> <path> [curl-extra-args...]
  local method="$1" api_path="$2"; shift 2
  curl -fsSL \
    --request "$method" \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --header "Content-Type: application/json" \
    "$@" \
    "${GITLAB_URL}/api/v4${api_path}"
}

# Resolve namespace ID (works for both users and groups)
resolve_namespace_id() {
  local ns="$1"
  local id

  # Try as a group first
  id=$(gitlab_api GET "/groups/$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1],safe='')); " "$ns" 2>/dev/null || printf '%s' "$ns" | sed 's|/|%2F|g')" 2>/dev/null \
    | jq -r '.id // empty' 2>/dev/null || true)

  if [[ -n "$id" ]]; then
    echo "$id"
    return
  fi

  # Fall back to user namespace
  id=$(gitlab_api GET "/users?username=$(printf '%s' "$ns" | sed 's|/|%2F|g')" 2>/dev/null \
    | jq -r '.[0].namespace_id // .[0].id // empty' 2>/dev/null || true)

  echo "$id"
}

create_gitlab_project() {
  local name="$1" ns_id="$2"
  gitlab_api POST "/projects" \
    --data "$(jq -n --arg name "$name" --argjson ns "$ns_id" \
      '{name: $name, namespace_id: $ns, visibility: "private", initialize_with_readme: false}')"
}

# ── main logic ───────────────────────────────────────────────────────────────

log "Extracting $ZIP_FILE …"
unzip -q "$ZIP_FILE" -d "$WORK_DIR/extracted"

log "Resolving namespace '$NAMESPACE' …"
NS_ID="$(resolve_namespace_id "$NAMESPACE")"
if [[ -z "$NS_ID" ]]; then
  echo "Error: could not resolve GitLab namespace '$NAMESPACE'. Check the name and your token permissions." >&2
  exit 1
fi
log "Namespace ID: $NS_ID"

SUCCEEDED=0
FAILED=0

# Detect repos: a directory that either contains .git/ or is itself a bare repo
# (has HEAD, objects/, refs/ at its root).
find "$WORK_DIR/extracted" -mindepth 1 -maxdepth 2 -type d | while read -r dir; do
  is_git=false
  bare=false

  if [[ -d "$dir/.git" ]]; then
    is_git=true
  elif [[ -f "$dir/HEAD" && -d "$dir/objects" && -d "$dir/refs" ]]; then
    is_git=true
    bare=true
  fi

  "$is_git" || continue

  repo_name="$(basename "$dir" .git)"
  log "Importing '$repo_name' …"

  # Create project on GitLab
  project_json="$(create_gitlab_project "$repo_name" "$NS_ID" 2>&1)" || {
    fail "Failed to create project '$repo_name': $project_json"
    FAILED=$((FAILED + 1))
    continue
  }

  ssh_url="$(echo "$project_json" | jq -r '.ssh_url_to_repo')"
  http_url="$(echo "$project_json" | jq -r '.http_url_to_repo')"

  # Embed token into the HTTP URL for push auth
  push_url="${http_url//:\/\//://oauth2:${TOKEN}@}"

  clone_dir="$WORK_DIR/push_$$_${repo_name}"

  if "$bare"; then
    git clone --bare "$dir" "$clone_dir" -q
  else
    git clone --mirror "$dir" "$clone_dir" -q
  fi

  if git -C "$clone_dir" push --mirror "$push_url" -q 2>&1; then
    ok "'$repo_name' → ${GITLAB_URL}/${NAMESPACE}/${repo_name}"
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    fail "Push failed for '$repo_name' (project created at $http_url)"
    FAILED=$((FAILED + 1))
  fi

  rm -rf "$clone_dir"
done

echo ""
log "Done. Succeeded: $SUCCEEDED  Failed: $FAILED"
[[ $FAILED -eq 0 ]]
