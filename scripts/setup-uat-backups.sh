#!/bin/bash
set -euo pipefail

# -----------------------------
# CONFIGURATION
# -----------------------------
RESOURCE_GROUP="rg-uat"
LOCATION="eastus2"
STORAGE_ACCOUNT="stuatbackup001"
VAULT_NAME="rsv-uat"
POLICY_NAME="policy-uat"
FILESHAIRES=("fileshare-uat1" "fileshare-uat2")  # Add more as needed
SAMPLE_FILES=("file1.txt" "file2.txt")
BACKUP_TIME="23:00"

# -----------------------------
# LOGGING FUNCTION
# -----------------------------
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# -----------------------------
# STEP 1: Create Resource Group
# -----------------------------
log "Creating or verifying resource group $RESOURCE_GROUP..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# -----------------------------
# STEP 2: Create Storage Account
# -----------------------------
log "Creating storage account $STORAGE_ACCOUNT..."
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS

# Get storage account key
KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].value" -o tsv)

# -----------------------------
# STEP 3: Create File Shares and Upload Sample Files
# -----------------------------
for SHARE in "${FILESHAIRES[@]}"; do
  log "Creating file share: $SHARE..."
  az storage share create --name "$SHARE" --account-name "$STORAGE_ACCOUNT"

  # Upload sample files
  for FILE in "${SAMPLE_FILES[@]}"; do
    echo "Sample content for $FILE in $SHARE" > "$FILE"
    az storage file upload \
      --account-name "$STORAGE_ACCOUNT" \
      --account-key "$KEY" \
      --share-name "$SHARE" \
      --source "$FILE"
    rm "$FILE"
  done
done

# -----------------------------
# STEP 4: Create Recovery Services Vault
# -----------------------------
log "Creating Recovery Services Vault $VAULT_NAME..."
az backup vault create \
  --name "$VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION"

# -----------------------------
# STEP 5: Create Backup Policy
# -----------------------------
log "Creating backup policy $POLICY_NAME..."
az backup policy create \
  --vault-name "$VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$POLICY_NAME" \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --backup-schedule-frequency Daily \
  --backup-schedule-time "$BACKUP_TIME" \
  --retention-daily 7

# -----------------------------
# STEP 6: Enable Protection for All File Shares
# -----------------------------
for SHARE in "${FILESHAIRES[@]}"; do
  log "Enabling protection for $SHARE..."
  az backup protection enable-for-azurefileshare \
    --vault-name "$VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --storage-account "$STORAGE_ACCOUNT" \
    --azure-file-share "$SHARE" \
    --policy-name "$POLICY_NAME"
done

# -----------------------------
# STEP 7: Trigger Initial Backup for All File Shares
# -----------------------------
for SHARE in "${FILESHAIRES[@]}"; do
  log "Triggering initial backup for $SHARE..."
  az backup protection backup-now \
    --vault-name "$VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --container-name "storagecontainer;storage;$RESOURCE_GROUP;$STORAGE_ACCOUNT" \
    --item-name "$SHARE"
done

log "✅ UAT setup complete. All file shares are protected and backed up."