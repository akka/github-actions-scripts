#!/bin/bash
# ensure the build didn't change any git controlled files in artifact-bom/
set -euo pipefail

if git diff --exit-code --quiet artifact-bom/; then
  echo "✅ No changes detected."
else
  echo "❌ ERROR: Files in artifact-bom/ changed which indicates a mismatch of dependencies compared to sbt." >&2
  echo "Ensure to run \`sbt makeBom\` and commit the updated pom.xml files." >&2
  git diff artifact-bom/
  exit 1
fi
