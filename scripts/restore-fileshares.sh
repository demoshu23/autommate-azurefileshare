#!/bin/bash
set -euo pipefail

# ==============================
# INPUTS (from pipeline variables)
# ==============================
ENVIRONMENT=${ENVIRONMENT:?}
RESOURCE_GROUP=${RESOURCE_GROUP:?}
VAULT_NAME=${VAULT_NAME:?}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT:?}

# Optional
MAX_PARALLEL=${MAX_PARALLEL:-2}
POLL_INTERVAL=${POLL_INTERVAL:-30}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$ENVIRONMENT] $1"
}

retry() {
  local n=0
  local max=3
  local delay=10
  until "$@"; do
    ((n++))
    if (( n >= max )); then
      log "Command failed after $n attempts: $*"
      return 1
    fi
    log "Retry $n/$max..."
    sleep $delay
  done
}

# ==============================
# STEP 1: Fetch file shares
# ==============================
log "Fetching Azure File Shares..."

ITEMS=$(az backup item list \
  --resource-group "$RESOURCE_GROUP" \
  --vault-name "$VAULT_NAME" \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --query "[].name" -o tsv)

[ -z "$ITEMS" ] && { log "No items found"; exit 0; }

# ==============================
# PROCESS FUNCTION
# ==============================
process_share() {
  local ITEM=$1

  log "Processing: $ITEM"

  # Step 2: Get latest recovery point
  RP=$(az backup recoverypoint list \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$VAULT_NAME" \
    --container-name "$STORAGE_ACCOUNT" \
    --item-name "$ITEM" \
    --query "sort_by([], &properties.recoveryPointTime)[-1].name" \
    -o tsv)

  if [ -z "$RP" ]; then
    log "No recovery point for $ITEM"
    return 0
  fi

  log "Latest RP: $RP"

  # Step 3: Trigger restore
  JOB_ID=$(retry az backup restore restore-azurefileshare \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$VAULT_NAME" \
    --container-name "$STORAGE_ACCOUNT" \
    --item-name "$ITEM" \
    --recovery-point-id "$RP" \
    --restore-mode OriginalLocation \
    --resolve-conflict Overwrite \
    --query "name" -o tsv)

  log "Restore job: $JOB_ID"

  # Step 4: Wait for completion
  STATUS="InProgress"

  while [[ "$STATUS" == "InProgress" || "$STATUS" == "Queued" ]]; do
    sleep "$POLL_INTERVAL"

    STATUS=$(az backup job show \
      --resource-group "$RESOURCE_GROUP" \
      --vault-name "$VAULT_NAME" \
      --name "$JOB_ID" \
      --query "status" -o tsv)

    log "$ITEM → $STATUS"
  done

  if [[ "$STATUS" != "Completed" ]]; then
    log "FAILED: $ITEM"
    return 1
  fi

  log "SUCCESS: $ITEM"
}

# ==============================
# PARALLEL EXECUTION
# ==============================
log "Starting restore (parallel=$MAX_PARALLEL)..."

echo "$ITEMS" | xargs -I {} -P "$MAX_PARALLEL" bash -c '
  process_share "$@"' _ {}

log "All restores completed."