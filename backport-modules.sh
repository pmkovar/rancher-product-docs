#!/bin/bash

# A script to copy or patch staged files from the 'latest' version
# directory to other specified version directories.
#
# If a target file exists, it will be patched. If it's new, it will be copied.
#
# Note: It does not properly handle moved/renamed files.
#
# Usage:
#   ./backport-modules.sh              (syncs to all found versions)
#   ./backport-modules.sh v2.11 v2.12    (syncs to only v2.11 and v2.12)

# The source directory containing the files to be copied.
SOURCE_PATH="versions/latest/modules/"
# The Antora playbook file to read versions from.
PLAYBOOK_FILE="playbook-remote.yml"

# Function to print a formatted message
print_message() {
  echo "=> $1"
}

# Ensure the script is run from the root of a Git repository
if [ ! -d .git ]; then
  print_message "Error: This script must be run from the root of your Git repository."
  exit 1
fi

# Check if the playbook file exists before proceeding
if [ ! -f "$PLAYBOOK_FILE" ]; then
  print_message "Error: Antora playbook '$PLAYBOOK_FILE' not found."
  print_message "Please run this script from the root of your repository."
  exit 1
fi

# Read the start_paths line from the playbook, ensuring it's not commented out.
# Then, extract the content between brackets [].
paths_str=$(grep -v '^ *#' "$PLAYBOOK_FILE" | grep '^ *start_paths:' | sed -n 's/.*\[\(.*\)\].*/\1/p')

# Convert the comma-separated string into an array of paths
IFS=',' read -r -a all_paths <<< "$paths_str"

# Filter paths to get only version numbers (e.g., v2.12)
DEFAULT_TARGET_VERSIONS=()
for path in "${all_paths[@]}"; do
  # Trim leading/trailing whitespace
  path=$(echo "$path" | xargs)
  # Check if the path is a version path (e.g., "versions/v2.11")
  if [[ "$path" == "versions/v"* ]]; then
    # Extract the version directory name (e.g., "v2.11")
    version=$(basename "$path")
    DEFAULT_TARGET_VERSIONS+=("$version")
  fi
done

# Determine which versions to target
TARGET_VERSIONS=()
if [ "$#" -gt 0 ]; then
  # Use versions from command line arguments, but validate them first
  print_message "Validating specified target versions..."
  for requested_version in "$@"; do
    is_valid=false
    for valid_version in "${DEFAULT_TARGET_VERSIONS[@]}"; do
      if [[ "$requested_version" == "$valid_version" ]]; then
        is_valid=true
        break
      fi
    done

    if [ "$is_valid" = false ]; then
      print_message "Error: Target version '$requested_version' is not a valid version found in '$PLAYBOOK_FILE'."
      print_message "Valid versions are: ${DEFAULT_TARGET_VERSIONS[*]}"
      exit 1
    fi
  done
  TARGET_VERSIONS=("$@")
  print_message "Using specified target versions from command line."
else
  # Use default versions from the script
  TARGET_VERSIONS=("${DEFAULT_TARGET_VERSIONS[@]}")
  print_message "No versions specified, using dynamically detected default versions."
fi

print_message "Starting sync of staged files..."
print_message "Target versions: ${TARGET_VERSIONS[*]}"
echo "-----------------------------------------------------"

# Get a list of files staged for commit within the specified source path
staged_files=$(git diff --name-only --cached -- "$SOURCE_PATH"**)

if [ -z "$staged_files" ]; then
  print_message "No staged files found in '$SOURCE_PATH'. Nothing to do."
  exit 0
fi

# Loop through each staged file
while IFS= read -r file; do
  if [ -f "$file" ]; then # Check if the item is a file
    echo
    print_message "Processing: $file"

    # Loop through each target version directory
    for version in "${TARGET_VERSIONS[@]}"; do
      # Construct the destination path by replacing 'latest' with the target version number
      dest_file="${file/latest/$version}"

      # Get the directory part of the destination path
      dest_dir=$(dirname "$dest_file")

      # Either PATCH or COPY the file
      if [ -f "$dest_file" ]; then
        # File exists, so we create and apply a patch
        echo "  - Target exists: $dest_file. Attempting to apply patch..."
        
        # Create a temporary file for the diff
        patch_file=$(mktemp)

        # Generate the patch by comparing the target (old) to the source (new)
        diff -u "$dest_file" "$file" > "$patch_file"

        # Check if the patch file has content (i.e., if there are differences)
        if [ -s "$patch_file" ]; then
          if patch --quiet "$dest_file" < "$patch_file"; then
            echo "  - SUCCESS: Patch applied."
          else
            echo "  - FAILED: Patch could not be applied. Manual merge required."
            echo "  - Check for a .rej file and review the changes in $dest_file manually."
          fi
        else
          echo "  - INFO: No differences found. File is already in sync."
        fi

        # Clean up the temporary patch file
        rm "$patch_file"
      else
        # File does not exist, so we copy it
        echo "  - Target is new. Copying file..."

        # Create the destination directory if it doesn't exist
        if [ ! -d "$dest_dir" ]; then
          mkdir -p "$dest_dir"
          echo "  - Created directory: $dest_dir"
        fi

        # Copy the source file to the destination
        cp "$file" "$dest_file"
        echo "  - Copied to: $dest_file"
      fi
    done
  fi
done <<< "$staged_files"

echo "-----------------------------------------------------"
print_message "Sync complete!"
print_message "Note: The files are copied/patched but not staged for commit. Please review and 'git add' them manually."

