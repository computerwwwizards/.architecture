#!/bin/bash
set -e

# Target directory where all individual builds were downloaded
PUBLIC_DIR="./public"
cd $PUBLIC_DIR

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
        .card { background: var(--card); padding: 1.5rem; border-radius: 8px; text-decoration: none; color: var(--text); border: 1px solid #334155; transition: transform 0.2s, border-color 0.2s; }
        .card:hover { transform: translateY(-3px); border-color: var(--accent); }
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
