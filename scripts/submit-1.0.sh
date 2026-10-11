#!/bin/bash
set -euo pipefail

source "$HOME/.config/midgar/credentials.env"

APP=6787688416
VERSION_ID=7cb0d32d-ea4c-4274-abd0-2cb0f7bff54f
SUBMISSION=23240732-c79c-44db-b708-7ac075bb1be3

asc review items add --submission "$SUBMISSION" --item-type appStoreVersions --item-id "$VERSION_ID"
asc review items list --submission "$SUBMISSION" --paginate --output table
asc review submissions-submit --id "$SUBMISSION" --confirm
asc review status --app "$APP"
