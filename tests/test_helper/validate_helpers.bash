make_valid_template_fixture() {
    local dir="$1"
    mkdir -p "$dir/memory" "$dir/roles/strategist/scripts"
    cat > "$dir/CLAUDE.md" <<'EOF'
# CLAUDE
EOF
    cat > "$dir/ONTOLOGY.md" <<'EOF'
# ONTOLOGY
EOF
    cat > "$dir/README.md" <<'EOF'
# README
EOF
    cat > "$dir/memory/MEMORY.md" <<'EOF'
# MEMORY

| # | РП | Бюджет | P | Статус | Дедлайн |
|---|----|--------|---|--------|---------|
| 1 | test | 1h | P1 | pending | — |
EOF
    cat > "$dir/memory/hard-distinctions.md" <<'EOF'
# distinctions
EOF
    cat > "$dir/memory/protocol-open.md" <<'EOF'
# open
EOF
    cat > "$dir/memory/protocol-close.md" <<'EOF'
# close
EOF
    cat > "$dir/memory/navigation.md" <<'EOF'
# navigation
EOF
    cat > "$dir/roles/strategist/scripts/strategist.sh" <<'EOF'
#!/usr/bin/env bash
EOF
}
