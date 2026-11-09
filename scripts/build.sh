#!/bin/bash
set -e

PUBLIC_DIR="./public"
mkdir -p "$PUBLIC_DIR"
PIDS=()

echo "--- Phase 1: Concurrent Workspace Builds ---"
# Iterate through all workspaces in the c4-catalogs directory
for d in c4-catalogs/*/; do
    if [ -d "$d" ]; then
        WORKSPACE_NAME=$(basename "$d")
        
        # Calculate current cryptographic hash of the workspace DSLs
        CURRENT_HASH=$(sha256sum "$d"*.dsl | sha256sum | awk '{print $1}')
        
        # Check if this exact workspace version is already in the cache
        PREV_HASH_FILE="$PUBLIC_DIR/$WORKSPACE_NAME/.dsl_hash"
        if [ -f "$PREV_HASH_FILE" ] && [ "$(cat "$PREV_HASH_FILE")" = "$CURRENT_HASH" ]; then
            echo "[$WORKSPACE_NAME] No changes detected. Skipping build."
            continue
        fi
        
        echo "[$WORKSPACE_NAME] Changes detected (or new). Starting concurrent build..."
        mkdir -p "$PUBLIC_DIR/$WORKSPACE_NAME"
        
        # Run Docker in a subshell and background it for concurrency
        (
            docker run --rm \
                --network none \
                -u $(id -u):$(id -g) \
                -v "$(pwd)/$d":/usr/local/structurizr/src \
                -v "$(pwd)/$PUBLIC_DIR/$WORKSPACE_NAME":/usr/local/structurizr/out \
                structurizr/cli:3.2.1 \
                export -workspace src/workspace.dsl -format static -output out
            
            # Save the hash only if the build succeeds
            echo "$CURRENT_HASH" > "$PUBLIC_DIR/$WORKSPACE_NAME/.dsl_hash"
        ) &
        
        # Store Process ID
        PIDS+=($!)
    fi
done

# Wait for all background builds to complete (The Barrier)
for pid in "${PIDS[@]}"; do
    wait $pid || exit 1 # Fail the pipeline if any child process fails
done

echo "All concurrent builds completed."


echo "--- Phase 2: AOT Portal & Manifest Generation ---"
cd "$PUBLIC_DIR"

# 1. Generate Manifest
echo "Generating manifest.json..."
WORKSPACES=$(find . -mindepth 1 -maxdepth 1 -type d | sed 's|./||' | jq -R -s -c 'split("\n")[:-1]')
echo "{\"last_updated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"workspaces\": $WORKSPACES}" > manifest.json

# 2. Generate HTML Entrypoint
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
        .card:hover { transform: translateY(-3px); }
        .card h2 { margin: 0 0 0.5rem 0; font-size: 1.25rem; color: var(--accent); text-transform: capitalize; }
    </style>
</head>
<body>
    <h1>Architecture Catalog Portal</h1>
    <div class="grid">
EOF

# Inject a card for every workspace found in the directory
for d in */ ; do
    DIR_NAME=${d%/}
    TITLE=$(echo "$DIR_NAME" | tr '_' ' ')
    echo "        <a href=\"/$DIR_NAME/index.html\" class=\"card\">" >> index.html
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
