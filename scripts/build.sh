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


echo "--- Phase 2: IDE Portal & Manifest Generation ---"
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
    <title>Architecture Workspace</title>
    <style>
        :root { --bg: #0f172a; --card: #1e293b; --text: #f8fafc; --accent: #38bdf8; --danger: #ef4444; }
        * { box-sizing: border-box; }
        
        /* 100vh Layout */
        body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); margin: 0; display: flex; height: 100vh; overflow: hidden; flex-direction: row; }
        
        /* Sidebar Layout */
        #sidebar { width: 350px; display: flex; flex-direction: column; border-right: 1px solid var(--card); background: #0b1121; flex-shrink: 0; }
        #sidebar-header { padding: 1.5rem; border-bottom: 1px solid var(--card); }
        #sidebar-header h1 { margin: 0 0 1rem 0; font-size: 1.25rem; }
        .search-bar { width: 100%; padding: 0.6rem 1rem; border-radius: 6px; border: 1px solid #334155; background: var(--card); color: var(--text); font-size: 0.95rem; }
        .search-bar:focus { outline: none; border-color: var(--accent); }
        
        #catalog { flex-grow: 1; overflow-y: auto; padding: 1.5rem; display: flex; flex-direction: column; gap: 1rem; }
        
        /* Card Styles */
        .card { background: var(--card); padding: 1.25rem; border-radius: 8px; border: 1px solid #334155; display: flex; flex-direction: column; transition: border-color 0.2s; }
        .card:hover { border-color: var(--accent); }
        .card h2 { margin: 0 0 0.5rem 0; font-size: 1.1rem; color: var(--accent); text-transform: capitalize; }
        .card p { margin: 0 0 1rem 0; font-size: 0.85rem; color: #94a3b8; }
        
        .actions { display: flex; gap: 0.5rem; }
        .btn { flex: 1; padding: 0.4rem; text-align: center; border-radius: 4px; text-decoration: none; font-size: 0.8rem; font-weight: 600; cursor: pointer; border: none; }
        .btn-primary { background: var(--accent); color: var(--bg); }
        .btn-primary:hover { opacity: 0.9; }
        .btn-secondary { background: #334155; color: var(--text); }
        .btn-secondary:hover { background: #475569; }
        
        /* Main Workspace Layout */
        #main-workspace { flex-grow: 1; display: flex; flex-direction: column; position: relative; background: var(--bg); overflow: hidden; }
        
        #empty-state { flex-grow: 1; display: flex; align-items: center; justify-content: center; flex-direction: column; color: #64748b; }
        #empty-state h3 { margin: 0; font-size: 1.2rem; font-weight: normal; }
        
        #tabs-view { display: none; flex-direction: column; height: 100%; }
        
        .tabs-toolbar { display: flex; background: #0f172a; border-bottom: 1px solid #334155; overflow-x: auto; scrollbar-width: none; }
        .tabs-toolbar::-webkit-scrollbar { display: none; }
        
        .tab { padding: 0.75rem 1.25rem; background: #1e293b; color: #94a3b8; border: none; border-right: 1px solid #334155; border-bottom: 2px solid transparent; cursor: pointer; display: flex; align-items: center; gap: 0.75rem; white-space: nowrap; font-size: 0.9rem; }
        .tab.active { background: var(--bg); color: var(--accent); border-bottom: 2px solid var(--accent); }
        .tab:hover:not(.active) { background: #2a3a52; }
        
        .tab-close { background: transparent; border: none; color: inherit; cursor: pointer; font-size: 1.2rem; line-height: 1; padding: 0 0.25rem; border-radius: 50%; display: flex; align-items: center; justify-content: center; }
        .tab-close:hover { color: var(--danger); }
        
        .iframe-container { flex-grow: 1; position: relative; background: #ffffff; }
        .iframe-container iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: none; display: none; }
        .iframe-container iframe.active { display: block; }
        
        .hidden { display: none !important; }
        
        /* Mobile Responsiveness - Vertical Split */
        @media (max-width: 768px) {
            body { flex-direction: column; }
            #sidebar { width: 100%; height: 40vh; border-right: none; border-bottom: 1px solid var(--card); }
            #main-workspace { height: 60vh; }
        }
    </style>
</head>
<body>
    
    <!-- Sidebar / Catalog List -->
    <div id="sidebar">
        <div id="sidebar-header">
            <h1>Architecture Catalog</h1>
            <input type="text" id="searchInput" class="search-bar" placeholder="Search architectures..." onkeyup="filterCards()">
        </div>
        <div id="catalog">
EOF

for WORKSPACE_NAME in "${!CURRENT_HASHES[@]}"; do
    TITLE=$(echo "$WORKSPACE_NAME" | tr '_' ' ')
    TITLE_LOWER=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
    
    cat <<EOF >> index.html
            <div class="card" data-title="${TITLE_LOWER}">
                <h2>$TITLE</h2>
                <p>Structural models & flows</p>
                <div class="actions">
                    <button class="btn btn-primary" onclick="openInTab('$WORKSPACE_NAME', '$TITLE')">Open Tab</button>
                    <a href="./$WORKSPACE_NAME/index.html" target="_blank" class="btn btn-secondary">Direct Link ↗</a>
                </div>
            </div>
EOF
done

cat <<EOF >> index.html
        </div>
    </div>

    <!-- Main Dynamic Workspace -->
    <div id="main-workspace">
        <div id="empty-state">
            <h3>Select an architecture from the sidebar to open.</h3>
        </div>
        
        <div id="tabs-view">
            <div class="tabs-toolbar" id="tabs-toolbar"></div>
            <div class="iframe-container" id="iframe-container"></div>
        </div>
    </div>

    <script>
        // 1. Sidebar Search Filter
        function filterCards() {
            const query = document.getElementById('searchInput').value.toLowerCase();
            const cards = document.querySelectorAll('.card');
            cards.forEach(card => {
                const title = card.getAttribute('data-title');
                if (title.includes(query)) {
                    card.classList.remove('hidden');
                } else {
                    card.classList.add('hidden');
                }
            });
        }

        // 2. Tab & Workspace Management
        let openTabs = [];
        let activeTab = null;

        function openInTab(id, title) {
            // Hide empty state, show tabs wrapper
            document.getElementById('empty-state').style.display = 'none';
            document.getElementById('tabs-view').style.display = 'flex';

            // Only create if it isn't already open
            if (!openTabs.includes(id)) {
                openTabs.push(id);
                
                // Create Tab button
                const tab = document.createElement('button');
                tab.className = 'tab';
                tab.id = 'tab-' + id;
                tab.onclick = () => setActiveTab(id);
                
                const tabText = document.createElement('span');
                tabText.textContent = title;
                
                const closeBtn = document.createElement('span');
                closeBtn.className = 'tab-close';
                closeBtn.innerHTML = '&times;';
                closeBtn.onclick = (e) => closeTab(e, id);
                
                tab.appendChild(tabText);
                tab.appendChild(closeBtn);
                document.getElementById('tabs-toolbar').appendChild(tab);

                // Create iframe
                const iframe = document.createElement('iframe');
                iframe.id = 'iframe-' + id;
                iframe.src = './' + id + '/index.html';
                document.getElementById('iframe-container').appendChild(iframe);
            }
            
            // Switch focus to the tab
            setActiveTab(id);
        }

        function setActiveTab(id) {
            activeTab = id;
            
            // Remove active classes
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.iframe-container iframe').forEach(i => i.classList.remove('active'));
            
            // Apply active class to requested target
            document.getElementById('tab-' + id).classList.add('active');
            document.getElementById('iframe-' + id).classList.add('active');
        }

        function closeTab(event, id) {
            event.stopPropagation(); // Prevent tab click trigger
            
            // Destroy nodes
            document.getElementById('tab-' + id).remove();
            document.getElementById('iframe-' + id).remove();
            
            openTabs = openTabs.filter(t => t !== id);
            
            if (openTabs.length === 0) {
                // No tabs left -> show empty state
                document.getElementById('empty-state').style.display = 'flex';
                document.getElementById('tabs-view').style.display = 'none';
                activeTab = null;
            } else if (activeTab === id) {
                // If closing active tab, shift focus to the last remaining tab
                setActiveTab(openTabs[openTabs.length - 1]);
            }
        }
    </script>
</body>
</html>
EOF

echo "Portal generation complete."

echo "--- Phase 3: LLM Context Generation (llms.txt) ---"
# Initialize the root llms.txt index
echo "# C4 Architecture Catalogs" > llms.txt
echo "> This index provides raw Structurizr DSL boundaries formatted for LLM and Agent ingestion." >> llms.txt
echo "" >> llms.txt

# Absolute URL root for the agent crawler
BASE_URL="https://computerwwwizards.github.io/.architecture"

for WORKSPACE_NAME in "${!CURRENT_HASHES[@]}"; do
    TITLE=$(echo "$WORKSPACE_NAME" | tr '_' ' ')
    MD_FILE="$WORKSPACE_NAME/llm-context.md"
    
    # 1. Create the markdown wrapper containing the raw DSL
    echo "# $TITLE Architecture" > "$MD_FILE"
    echo '```dsl' >> "$MD_FILE"
    cat "../c4-catalogs/$WORKSPACE_NAME/workspace.dsl" >> "$MD_FILE"
    echo '```' >> "$MD_FILE"
    
    # 2. Append the absolute URL anchor to the root llms.txt
    echo "- [$TITLE Architecture DSL]($BASE_URL/$MD_FILE)" >> llms.txt
done

echo "LLM context generation complete."
