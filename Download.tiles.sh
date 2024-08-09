#!/bin/bash

# Constants
FILE_URL="https://download.versatiles.org/osm.versatiles"
TARGET="./versatiles"
TEMP_FILE="${TARGET}/osm.versatiles.part"
CHUNK_SIZE=$((10 * 1024 * 1024)) # 10MB in bytes
BUFFER_SIZE=$((1 * 1024 * 1024)) # 1MB buffer

# Function to check available disk space
check_disk_space() {
    local dir="$1"
    df "$dir" | tail -1 | awk '{print $4 * 1024}' # Convert to bytes
}

# Function to prompt the user for download preference
prompt_download_preference() {
    local available_space="$1"
    local required_space="$2"
    local choice

    if [ "$available_space" -ge "$required_space" ]; then
read -p "Sufficient disk space available.
Do you want to proceed with a full download? (Y/n): " choice
        choice=${choice:-Y}
    else
        echo "Insufficient disk space."
    fi

    echo "$choice"
}

# Function to download file in chunks
download_file_in_chunks() {
    local start="$1"
    local end="$2"
    local url="$3"
    local output_file="$4"
    local chunk_number="$5"
    local total_chunks="$6"

    echo "Downloading chunk: $start to $end ($(awk "BEGIN {printf \"%.2f\", ($chunk_number * 100) / $total_chunks}")%)"
    curl -L --progress-bar "$url" -r $start-$end >> "$output_file"

    for ((i=0; i<2; i++)); do
        tput cuu1
        tput el
    done
}


# Function to handle full download
handle_full_download() {
    local file_size_bytes="$1"
    local temp_file="$2"
    local url="$3"
    local total_chunks=$(( (file_size_bytes + CHUNK_SIZE - 1) / CHUNK_SIZE ))
    local chunk_number

    if [ -f "$temp_file" ]; then
        local start
        start=$(stat -c%s "$temp_file")
        chunk_number=$(( start / CHUNK_SIZE ))
        echo "File: $temp_file"
        echo "Resuming download from byte $start"
    else
        local start=0
        chunk_number=1
    fi

    for (( current_start=start; current_start<file_size_bytes; current_start+=CHUNK_SIZE )); do
        local current_end=$((current_start + CHUNK_SIZE - 1))
        [ $current_end -ge $file_size_bytes ] && current_end=$((file_size_bytes - 1))

        download_file_in_chunks $current_start $current_end "$url" "$temp_file" $chunk_number $total_chunks
        ((chunk_number++))
    done

    echo "Download complete. File saved as $temp_file"
}

# Function to vaildate the bounding box values
validate_bbox() {
    for coord in "$x_min" "$y_min" "$x_max" "$y_max"; do
        echo "$coord" | awk '/^-?[0-9]+(\.[0-9]+)?$/ {exit 0} {exit 1}' || { echo "Error: All coordinates must be numbers."; return 1; }
    done

    echo "$x_min $x_max" | awk '{if ($1 < -180.0 || $1 > 180.0 || $2 < -180.0 || $2 > 180.0) exit 1; exit 0}' || { echo "Error: Longitude values must be between -180.0 and 180.0."; return 1; }
    echo "$y_min $y_max" | awk '{if ($1 < -90.0 || $1 > 90.0 || $2 < -90.0 || $2 > 90.0) exit 1; exit 0}' || { echo "Error: Latitude values must be between -90.0 and 90.0."; return 1; }
    echo "$x_min $x_max" | awk '{if ($1 >= $2) exit 1; exit 0}' || { echo "Error: Ensure min_Longitude < max_Longitude."; return 1; }
    echo "$y_min $y_max" | awk '{if ($1 >= $2) exit 1; exit 0}' || { echo "Error: Ensure min_Latitude < max_Latitude."; return 1; }

    return 0
}

# Main script execution
main() {
    local file_size
    local file_size_bytes
    local available_space
    local required_space
    local user_choice
    local attempts
    local max_attempts

    # Function to get the file size from the URL
    file_size=$(curl -sI "$FILE_URL" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
    if [ -z "$file_size" ]; then
        echo "Failed to get file size from URL."
        exit 1
    fi

    file_size_bytes=$(echo "$file_size" | awk '{print int($1)}')
    available_space=$(check_disk_space $TARGET)
    required_space=$((file_size_bytes + BUFFER_SIZE))

    [ ! -d "$TARGET" ] && mkdir -p "$TARGET"

    user_choice=$(prompt_download_preference "$available_space" "$required_space")

    if [[ "$user_choice" == "Y" || "$user_choice" == "y" ]]; then
        handle_full_download "$file_size_bytes" "$TEMP_FILE" "$FILE_URL"
    else
        echo "Please specify the bounding box area to download."
        echo "For more information, please refer to:"
        echo " * https://wiki.openstreetmap.org/wiki/Bounding_box"
        echo " * https://bboxfinder.com/"
        echo -n "(Area) "
        attempts=0
        max_attempts=3

        while (( attempts < max_attempts )); do

read -r input
IFS=',' read -r x_min y_min x_max y_max <<EOF
$input
EOF

            if validate_bbox; then break; fi

            echo -n "Error: Invalid bbox values provided."
            ((attempts++))
            if (( attempts == max_attempts )); then
                echo ""
                echo "Error: Maximum attempts reached. Exiting."
                exit 1
            fi
            echo " Please try again."
            echo "Guide: All 4 numbers must be separated by commas."
            echo "Guide: For example, to download only tiles for Switzerland, type below"
            echo "Guide: (Area) 5.956,45.818,10.492,47.808"
            echo -n "(Area) "
        done

        echo "versatiles convert -bbox \"${x_min},${y_min},${x_max},${y_max}\" $FILE_URL ${TARGET}/osm.versatiles"
    fi
}

# Run the main function
main
