# Общие хелперы для тестов strategist

# Создать минимальный валидный env-файл
make_valid_env() {
    local path="$1"
    cat > "$path" <<'EOF'
WORKSPACE_DIR=/home/test/IWE2
CLAUDE_PATH=/usr/local/bin/claude
GITHUB_USER=testuser
EXOCORTEX_REPO=DS-exocortex
TIMEZONE_HOUR=+3
TIMEZONE_DESC=MSK
HOME_DIR=/home/test
CLAUDE_PROJECT_SLUG=-home-test-IWE2
EOF
}

# Создать env-файл с опасным содержимым
make_dangerous_env() {
    local path="$1"
    cat > "$path" <<'EOF'
WORKSPACE_DIR=/home/test/IWE2
eval "rm -rf /"
CLAUDE_PATH=/usr/local/bin/claude
EOF
}

# Создать env-файл с source-инъекцией
make_source_injection_env() {
    local path="$1"
    cat > "$path" <<'EOF'
WORKSPACE_DIR=/home/test/IWE2
source /etc/passwd
EOF
}
