#!/bin/bash
set -e

echo "=== Starting Automated Bot Maintenance & Graphics Run ==="

# 1. Ensure required dependencies are present on the GitHub Runner
if ! command -v convert &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Installing ImageMagick and jq..."
    sudo apt-get update -qq && sudo apt-get install -y -qq imagemagick jq curl
fi

# 2. Configuration & Directories
BASE_DIR="./data/bot_graphics"
LOG_FILE="$BASE_DIR/admin_audit.log"
CATEGORIES=("news" "social_media" "product_mockups" "reports" "alerts")
TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S UTC"

mkdir -p "$BASE_DIR"
touch "$LOG_FILE"

# 3. Core Generation & Realism Function
generate_and_stamp() {
    local category="$1"
    local prompt="$2"
    local out_dir="$BASE_DIR/$category"
    mkdir -p "$out_dir"

    local filename="gfx_$(date +%s).png"
    local filepath="$out_dir/$filename"
    local temp_file="/tmp/raw_$filename"
    local current_ts=$(date -u +"$TIMESTAMP_FORMAT")

    # Skip API call if OPENAI_API_KEY is not set in GitHub Secrets (creates a placeholder/updates existing instead)
    if [[ -n "$OPENAI_API_KEY" ]]; then
        local full_prompt="$prompt, candid photography, natural lighting, 35mm lens, subtle film grain, unedited raw photo look"
        
        local response=$(curl -s -X POST "https://openai.com" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -d "{
                \"model\": \"dall-e-3\",
                \"prompt\": \"$full_prompt\",
                \"n\": 1,
                \"size\": \"1024x1024\"
            }")

        local image_url=$(echo "$response" | jq -r '.data[0].url')

        if [[ "$image_url" != "null" && -n "$image_url" ]]; then
            curl -s "$image_url" -o "$temp_file"
            
            # Apply Gaussian sensor grain & forensic drop-shadow timestamp
            convert "$temp_file" \
                -attenuate 0.15 +noise Gaussian \
                -gravity SouthEast \
                -font DejaVu-Sans-Mono \
                -pointsize 20 \
                -fill "rgba(0,0,0,0.75)" -annotate +22+22 "$current_ts" \
                -fill "rgba(255,255,255,0.9)" -annotate +20+20 "$current_ts" \
                "$filepath"
            
            rm -f "$temp_file"
            echo "[$(date -u +"%Y-%m-%d %H:%M:%S")] GENERATED: $filepath" >> "$LOG_FILE"
        else
            echo "[$(date -u +"%Y-%m-%d %H:%M:%S")] ERROR: API failed for $category" >> "$LOG_FILE"
        fi
    else
        echo "No OPENAI_API_KEY found. Skipping new image generation for $category."
    fi
}

# 4. Execute Tasks Across All Categories
for cat in "${CATEGORIES[@]}"; do
    echo "Processing category: $cat"
    generate_and_stamp "$cat" "Editorial real-world scene representing $cat update"
done

# 5. Automated Retention Cleanup (Remove images older than 30 days)
find "$BASE_DIR" -type f -name "*.png" -mtime +30 -exec rm -f {} \;

# 6. Update Last-Run Metadata JSON for Your Website Frontend
cat <<EOF > "$BASE_DIR/status.json"
{
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "active",
  "categories": ["news", "social_media", "product_mockups", "reports", "alerts"]
}
EOF

echo "=== Automation Run Complete ==="
