#!/bin/bash
# detect-gebco-year.sh
# Scrapes GEBCO website to find the latest published grid year.
# Exits 0 with the year on stdout, exits 1 on failure.

set -euo pipefail

# GEBCO publishes grids under predictable URL patterns on their news page.
# Each release has a canonical news item. We check whether the COG on
# source.coop exists for the candidate year.

CURRENT_YEAR=$(date +%Y)
FOUND_YEAR=""

# Check up to 2 years ahead (in case we're running late)
for YEAR in $CURRENT_YEAR $((CURRENT_YEAR - 1)); do
  COG_URL="https://s3.us-west-2.amazonaws.com/us-west-2.opendata.source.coop/alexgleith/gebco-${YEAR}/GEBCO_${YEAR}.tif"

  # Use a HEAD request + range to probe for the COG (fast, no full download)
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 30 \
    --retry 3 \
    -r "0-1023" \
    "$COG_URL")

  if [ "$HTTP_CODE" = "206" ] || [ "$HTTP_CODE" = "200" ]; then
    FOUND_YEAR=$YEAR
    break
  fi
done

if [ -z "$FOUND_YEAR" ]; then
  echo "ERROR: Could not find a valid GEBCO COG for year $CURRENT_YEAR or $((CURRENT_YEAR - 1))" >&2
  exit 1
fi

echo "$FOUND_YEAR"
