# Общие хелперы для тестов extractor

make_extractor_env() {
    local script_dir="$1"
    local home_dir="$2"
    local workspace_dir="$3"
    local claude_path="$4"
    local extras="${5:-}"

    local iwe_ws
    iwe_ws="$(cd "$script_dir/../../../.." && pwd)"
    local env_dir="$home_dir/.$(basename "$iwe_ws")"
    mkdir -p "$env_dir"
    cat > "$env_dir/env" <<EOF
WORKSPACE_DIR=$workspace_dir
CLAUDE_PATH=$claude_path
GITHUB_USER=testuser
$extras
EOF
    printf '%s\n' "$env_dir/env"
}

make_mock_claude() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${MOCK_CLAUDE_ARGS_FILE}"
exit 0
EOF
    chmod +x "$bin_dir/claude"
}

make_mock_git() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_GIT_ARGS_FILE}"
case "$1" in
  reset|add|push) exit 0 ;;
  commit) exit 0 ;;
  diff)
    if [[ "$*" == *"--cached --quiet"* ]]; then
      exit 1
    fi
    if [[ "$*" == *"origin/main..HEAD"* ]]; then
      exit 1
    fi
    exit 0
    ;;
  *) /usr/bin/git "$@" ;;
esac
EOF
    chmod +x "$bin_dir/git"
}

make_mock_notify_script() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" >> "${MOCK_NOTIFY_FILE}"
exit 0
EOF
    chmod +x "$path"
}
