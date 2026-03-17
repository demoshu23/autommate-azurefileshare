# autommate-azurefileshare

create library group
create service connection and authenticate

az group create --name rg-uat --location eastus2

az backup vault create \
    --name rsv-uat \
    --resource-group rg-uat \
    --location eastus2

1️⃣ Create a Resource Group (if missing)
az group create \
  --name rg-uat \
  --location eastus2

2️⃣ Create Storage Account
az storage account create \
  --name stuatbackup001 \
  --resource-group rg-uat \
  --location eastus2 \
  --sku Standard_LRS

3️⃣ Create a File Share
az storage share create \
  --name fileshare-uat \
  --account-name stuatbackup001
  
4️⃣ Add Sample Files to the Share
# Get storage account key
KEY=$(az storage account keys list \
  --account-name stuatbackup001 \
  --resource-group rg-uat \
  --query "[0].value" -o tsv)

# Create sample files
echo "Hello UAT Backup" > file1.txt
echo "Pipeline test" > file2.txt

# Upload files
az storage file upload \
  --account-name stuatbackup001 \
  --account-key $KEY \
  --share-name fileshare-uat \
  --source file1.txt
az storage file upload \
  --account-name stuatbackup001 \
  --account-key $KEY \
  --share-name fileshare-uat \
  --source file2.txt
  
5️⃣ Create Recovery Services Vault
az backup vault create \
  --name rsv-uat \
  --resource-group rg-uat \
  --location eastus2
  
6️⃣ Set Backup Policy for Azure Files
az backup policy create \
  --vault-name rsv-uat \
  --resource-group rg-uat \
  --name policy-uat \
  --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --backup-schedule-frequency Daily \
  --backup-schedule-time 23:00 \
  --retention-daily 7
  
7️⃣ Enable Protection (Link File Share to Vault)
az backup protection enable-for-azurefileshare \
  --vault-name rsv-uat \
  --resource-group rg-uat \
  --storage-account stuatbackup001 \
  --azure-file-share fileshare-uat \
  --policy-name policy-uat
  
8️⃣ Trigger Initial Backup (so recovery points exist)
az backup protection backup-now \
  --vault-name rsv-uat \
  --resource-group rg-uat \
  --container-name storagecontainer;storage;rg-uat;stuatbackup001 \
  --item-name fileshare-uat

Wait until this job completes before running your restore pipeline.

✅ 9️⃣ Test Your Restore Script

Once the above steps are completed:

Your script will now find one protected file share (fileshare-uat)

It will pick the latest recovery point and restore to the original location

[2026-03-17 16:52:47] [uat] Fetching Azure File Shares...
[2026-03-17 16:52:49] [uat] Found: fileshare-uat
[2026-03-17 16:52:50] [uat] Restore started...
