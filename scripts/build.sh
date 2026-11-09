#!/bin/bash
set -e

PUBLIC_DIR="./public"
mkdir -p "$PUBLIC_DIR"
PIDS=()

echo "--- Phase 0: Fetch Live Production Manifest ---"
LIVE_MANIFEST="/tmp/live_manifest.json"
if curl -s -f -L "${PAGES_BASE_URL}/manifest.json" -o "$LIVE_MANIFEST"; then
    echo "Fetched live manifest from ${PAGES_BASE_URL}/manifest.json"
else
    echo "No live manifest found at ${PAGES_BASE_URL}/manifest.json (first deploy or unreachable). Building all."
    echo '{"workspaces":{}}' > "$LIVE_MANIFEST"
fi

# Associative array to hold current hashes in memory (no .dsl_hash files needed)
declare -A CURRENT_HASHES

echo "--- Phase 1: Concurrent Workspace Builds ---"
for d in c4-catalogs/*/; do
    if [ -d "$d" ]; then
        WORKSPACE_NAME=$(basename "$d")
        
        # Calculate current cryptographic hash of the source DSLs
        CURRENT_HASH=$(sha256sum "$d"*.dsl | sha256sum | awk '{print $1}')
        CURRENT_HASHES["$WORKSPACE_NAME"]="$CURRENT_HASH"
        
        # Read what is deployed in live production
        PROD_HASH=$(jq -r ".workspaces[\"$WORKSPACE_NAME\"] // empty" "$LIVE_MANIFEST" 2>/dev/null || echo "")
        
        # Skip ONLY if it matches live production AND the cached HTML wasn't evicted
        if [ "$PROD_HASH" = "$CURRENT_HASH" ] && [ -f "$PUBLIC_DIR/$WORKSPACE_NAME/index.html" ]; then
            echo "[$WORKSPACE_NAME] Matches live production and exists in cache. Skipping build."
            continue
        fi
        
        echo "[$WORKSPACE_NAME] Drift detected or cache evicted. Starting concurrent build..."
        rm -rf "$PUBLIC_DIR/$WORKSPACE_NAME"
        mkdir -p "$PUBLIC_DIR/$WORKSPACE_NAME"
        
        (
            docker run --rm \
                --network none \
                -u $(id -u):$(id -g) \
                -v "$(pwd)/$d":/usr/local/structurizr/src \
                -v "$(pwd)/$PUBLIC_DIR/$WORKSPACE_NAME":/usr/local/structurizr/out \
                structurizr/cli:latest \
                export -workspace src/workspace.dsl -format static -output out
        ) &
        
        PIDS+=($!)
    fi
done

# The Barrier: Wait for all concurrent builds to finish
for pid in "${PIDS[@]}"; do
    wait $pid || exit 1
done
echo "All concurrent builds completed."


echo "--- Phase 2: AOT Portal & Manifest Generation ---"
cd "$PUBLIC_DIR"

echo "Generating manifest.json..."
jq -n --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{last_updated: $date, workspaces: {}}' > manifest.json

for WORKSPACE_NAME in "${!CURRENT_HASHES[@]}"; do
    HASH="${CURRENT_HASHES[$WORKSPACE_NAME]}"
    jq --arg w "$WORKSPACE_NAME" --arg h "$HASH" '.workspaces[$w] = $h' manifest.json > tmp.json && mv tmp.json manifest.json
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

for WORKSPACE_NAME in "${!CURRENT_HASHES[@]}"; do
    TITLE=$(echo "$WORKSPACE_NAME" | tr '_' ' ')
    echo "        <a href=\"./$WORKSPACE_NAME/index.html\" class=\"card\">" >> index.html
    echo "            <h2>$TITLE</h2>" >> index.html
    echo "            <p>View structural models and dynamic flows.</p>" >> index.html
    echo "        </a>" >> index.html
done

cat <<EOF >> index.html
    </div>
</body>
</html>
EOF

echo "Portal generation complete."
