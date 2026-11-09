#!/bin/bash
set -e

mkdir -p ./public
PIDS=()

for d in catalogs/*/; do
    if [ -d "$d" ]; then
        WORKSPACE_NAME=$(basename "$d")
        
        # Calculate current cryptographic hash of the workspace DSLs
        CURRENT_HASH=$(sha256sum "$d"*.dsl | sha256sum | awk '{print $1}')
        
        # Check if this exact workspace version is already in the cache
        PREV_HASH_FILE="./public/$WORKSPACE_NAME/.dsl_hash"
        if [ -f "$PREV_HASH_FILE" ] && [ "$(cat "$PREV_HASH_FILE")" = "$CURRENT_HASH" ]; then
            echo "[$WORKSPACE_NAME] No changes detected. Skipping build."
            continue
        fi
        
        echo "[$WORKSPACE_NAME] Changes detected (or new). Starting concurrent build..."
        mkdir -p "./public/$WORKSPACE_NAME"
        
        # Run Docker in a subshell and background it
        (
            docker run --rm \
                --network none \
                -u $(id -u):$(id -g) \
                -v "$(pwd)/$d":/usr/local/structurizr/src \
                -v "$(pwd)/public/$WORKSPACE_NAME":/usr/local/structurizr/out \
                structurizr/cli:3.2.1 \
                export -workspace src/workspace.dsl -format static -output out
            
            # Save the hash only if the build succeeds
            echo "$CURRENT_HASH" > "./public/$WORKSPACE_NAME/.dsl_hash"
        ) &
        
        # Store Process ID
        PIDS+=($!)
    fi
done

# Wait for all background builds to complete
for pid in "${PIDS[@]}"; do
    wait $pid || exit 1 # Fail the pipeline if any child process fails
done

echo "All concurrent builds completed."
