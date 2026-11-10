#!/bin/bash
set -e

PUBLIC_DIR="./public"
mkdir -p "$PUBLIC_DIR"
PIDS=()

# --- Self-Contained Structurizr CLI Bootstrap & Verification ---
BIN_DIR="$(pwd)/bin"
STRUCTURIZR_BIN="$BIN_DIR/structurizr.sh"
ZIP_PATH="$(pwd)/structurizr-cli.zip"

# Validated latest CLI release URL and its actual SHA-256 hash
STRUCTURIZR_URL="https://github.com/structurizr/cli/releases/download/v2025.11.09/structurizr-cli.zip"
EXPECTED_SHA256="f5365a463fc44d539ed19bec00c48ba1e1ecda0ccfd1ba40d2e7472d264eb79a"

if [ ! -f "$STRUCTURIZR_BIN" ]; then
    echo "Structurizr CLI binary not found locally. Bootstrapping toolchain..."
    mkdir -p "$BIN_DIR"
    
    echo "Downloading Structurizr CLI from $STRUCTURIZR_URL..."
    curl -sL "$STRUCTURIZR_URL" -o "$ZIP_PATH"
    
    echo "Verifying cryptographic SHA-256 hash..."
    ACTUAL_SHA256=$(sha256sum "$ZIP_PATH" | awk '{print $1}')
    
    # Fixed the condition to properly compare actual against expected
    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo "ERROR: Hash mismatch for downloaded Structurizr CLI zip!"
        echo "Expected: $EXPECTED_SHA256"
        echo "Actual:   $ACTUAL_SHA256"
        exit 1
    fi
    echo "Hash verification passed ($ACTUAL_SHA256)."
    
    echo "Extracting archive..."
    unzip -q "$ZIP_PATH" -d "$BIN_DIR"
    chmod +x "$STRUCTURIZR_BIN"
    rm "$ZIP_PATH"
    echo "Bootstrap complete."
fi
# -------------------------------------------------------------

echo "--- Phase 0: Fetch Live Production Manifest ---"
LIVE_MANIFEST="/tmp/live_manifest.json"
if curl -s -f -L "${PAGES_BASE_URL}/manifest.json" -o "$LIVE_MANIFEST"; then
    echo "Fetched live manifest from ${PAGES_BASE_URL}/manifest.json"
else
    echo "No live manifest found. Building all catalogs."
    echo '{"workspaces":{}}' > "$LIVE_MANIFEST"
fi

declare -A CURRENT_HASHES

echo "--- Phase 1: Concurrent Workspace Builds ---"
for d in c4-catalogs/*/; do
    if [ -d "$d" ]; then
        WORKSPACE_NAME=$(basename "$d")
        
        CURRENT_HASH=$(sha256sum "$d"*.dsl | sha256sum | awk '{print $1}')
        CURRENT_HASHES["$WORKSPACE_NAME"]="$CURRENT_HASH"
        
        PROD_HASH=$(jq -r ".workspaces[\"$WORKSPACE_NAME\"] // empty" "$LIVE_MANIFEST" 2>/dev/null || echo "")
        
        if [ "$PROD_HASH" = "$CURRENT_HASH" ] && [ -f "$PUBLIC_DIR/$WORKSPACE_NAME/index.html" ]; then
            echo "[$WORKSPACE_NAME] Matches live production and exists in cache. Skipping build."
            continue
        fi
        
        echo "[$WORKSPACE_NAME] Drift detected or cache evicted. Starting native build..."
        rm -rf "$PUBLIC_DIR/$WORKSPACE_NAME"
        mkdir -p "$PUBLIC_DIR/$WORKSPACE_NAME"
        
        # Run natively in background subshell using sh invocation
        (
            bash "$STRUCTURIZR_BIN" export \
                -workspace "$d/workspace.dsl" \
                -format static \
                -output "$PUBLIC_DIR/$WORKSPACE_NAME"
        ) &
        
        PIDS+=($!)
    fi
done

# The Barrier: Wait for all concurrent builds to finish
for pid in "${PIDS[@]}"; do
    wait $pid || exit 1
done
echo "All native concurrent builds completed."


echo "--- Phase 2: AOT Portal & Manifest Generation ---"
cd "$PUBLIC_DIR"

echo "Generating manifest.json..."
jq -n --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{last_updated: $date, workspaces: {}}' > manifest.json

for WORKSPACE_NAME in "${!CURRENT_HASHES[@]}"; do
    HASH="${CURRENT_HASHES[$WORKSPACE_NAME]}"
    jq --arg w "$WORKSPACE_NAME" --arg h "$HASH" '.workspaces[$w] =$h' manifest.json > tmp.json && mv tmp.json manifest.json
done

echo "Generating index.html..."
cat <<EOF > index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Architecture Catalog Portal</title>
    <style>
        :root { --bg: #0f172a; --card: #1e293b; --text: #f8fafc; --accent: #38bdf8; }
        body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); padding: 2rem; margin: 0; }
        h1 { border-bottom: 2px solid var(--card); padding-bottom: 1rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1.5rem; margin-top: 2rem; }
        .card { background: var(--card); padding: 1.5rem; border-radius: 8px; text-decoration: none; color: var(--text); border: 1px solid #334155; transition: transform 0.2s, border-color: var(--accent); }
        .card:hover { transform: translateY(-3px); border-color: var(--accent); }
        .card h2 { margin: 0 0 0.5rem 0; font-size: 1.25rem; color: var(--accent); text-transform: capitalize; }
    </style>
</head>
<body>
    <h1>Architecture Catalog Portal</h1>
    <div class="grid">
EOF

for WORKSPACE_NAME in
