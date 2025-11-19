#!/bin/bash
# organise sbt generated pom.xml files to be committed to repos for analysis tools

SEARCH_DIR="."
VERSION_REGEX='_2\.13-[0-9]+\.[0-9]+\.[0-9]+(_[0-9]+)?(-[A-Za-z0-9]+)?\.pom$'

set -euo pipefail

# --- Detect OS and set the correct sed flag ---
SED_EXTENDED_REGEX_FLAG="-E" # Default to macOS/BSD
SED_INPLACE="-i ''"
if [[ "$(uname -s)" == "Linux" ]]; then
    # Change to -r if running on Linux (GNU sed)
    SED_EXTENDED_REGEX_FLAG="-r"
    SED_INPLACE='-i'
fi

# Find the files and read each file path into the 'file_path' variable.
find "$SEARCH_DIR" -type f -name "*.pom" | while IFS= read -r file_path; do

    # Get only the filename (e.g., "artifact-name-1.5.22.pom")
    filename=$(basename "$file_path")

    # Uses shell parameter expansion to get the part *before* the VERSION_STRING.
    # Example: "artifact-name-1.5.22.pom" -> "artifact-name"
    dir_name=$(echo "$filename" | sed "${SED_EXTENDED_REGEX_FLAG}" "s/$VERSION_REGEX//")

    # Check if the extraction resulted in a valid name (i.e., the string was actually found)
    if [[ "$dir_name" == "$filename" || -z "$dir_name" ]]; then
        echo "Warning: File '$filename' does not match the version pattern '$VERSION_REGEX'. Skipping."
        continue
    fi

    DEST_DIR="./generated-poms/$dir_name"
    DEST_FILE="$DEST_DIR/pom.xml"

    mkdir -p "$DEST_DIR"
    cp "$file_path" "$DEST_FILE"

    # Remove repositories section
    sed "${SED_INPLACE}" '' '/<repositories>/,/<\/repositories>/d' "${DEST_FILE}

    echo "$file_path -> $DEST_FILE"
done

echo "Script finished successfully."
