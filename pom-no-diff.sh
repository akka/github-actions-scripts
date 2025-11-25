#!/bin/bash
#
set -euo pipefail

if git diff --exit-code --quiet; then
  echo "✅ No changes detected."
else
  echo "❌ ERROR: Generated pom.xml files are out of sync with the repository." >&2
  echo "Run 'sbt makePom' and https://github.com/akka/github-actions-scripts/raw/refs/heads/main/pom-organize.sh in the repo directory to update and commit the resulting changes." >&2
  git diff
  exit 1
fi
