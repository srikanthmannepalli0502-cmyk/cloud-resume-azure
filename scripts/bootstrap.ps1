<#
.SYNOPSIS
  One-time setup, run by YOU (as subscription Owner) before Terraform.

  Creates:
    - rg-<prefix>          resource group Terraform deploys the site into
    - rg-<prefix>-tfstate  resource group holding Terraform state + the GitHub identity
    - a storage account for Terraform remote state
    - a user-assigned managed identity that GitHub Actions logs in as (OIDC, no secrets)
      with federated credentials for pushes to main and pull requests
    - role assignments scoped to just these resource groups

  Uses a managed identity instead of an Entra ID app registration because
  university tenants often block students from creating app registrations.

.EXAMPLE
  az login
  ./scripts/bootstrap.ps1 -GitHubRepo "your-username/cloud-resume-azure"
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$GitHubRepo,           # "owner/repo", exact casing as on GitHub
  [string]$Location = "eastus",
  [string]$Prefix = "cloudresume"
)

$ErrorActionPreference = "Stop"

function Invoke-AzCli {
  $out = & az @args
  if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed" }
  return $out
}

function Grant-Role($PrincipalId, $PrincipalType, $Role, $Scope) {
  $existing = Invoke-AzCli role assignment list --role $Role --scope $Scope --query "[?principalId=='$PrincipalId'].id | [0]" -o tsv
  if ($existing) { Write-Host "  = $Role already granted"; return }
  Invoke-AzCli role assignment create --assignee-object-id $PrincipalId --assignee-principal-type $PrincipalType `
    --role $Role --scope $Scope --output none
  Write-Host "  + $Role"
}

$sub    = Invoke-AzCli account show --query id -o tsv
$tenant = Invoke-AzCli account show --query tenantId -o tsv
Write-Host "Subscription: $(Invoke-AzCli account show --query name -o tsv) ($sub)"

$appRg   = "rg-$Prefix"
$stateRg = "rg-$Prefix-tfstate"

Write-Host "`nRegistering resource providers..."
foreach ($ns in "Microsoft.Storage", "Microsoft.Web", "Microsoft.DocumentDB", "Microsoft.Cdn",
                "Microsoft.Insights", "Microsoft.OperationalInsights", "Microsoft.ManagedIdentity") {
  Invoke-AzCli provider register --namespace $ns --output none
}

Write-Host "Creating resource groups..."
Invoke-AzCli group create -n $appRg   -l $Location --output none
Invoke-AzCli group create -n $stateRg -l $Location --output none

Write-Host "Creating Terraform state storage..."
$stateSa = Invoke-AzCli storage account list -g $stateRg --query "[0].name" -o tsv
if (-not $stateSa) {
  $rand = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
  $stateSa = ("sttf" + $Prefix).Substring(0, [Math]::Min(18, 4 + $Prefix.Length)) + $rand
  Invoke-AzCli storage account create -n $stateSa -g $stateRg -l $Location --sku Standard_LRS `
    --min-tls-version TLS1_2 --allow-blob-public-access false --output none
}
Invoke-AzCli storage container-rm create --storage-account $stateSa -g $stateRg -n tfstate --output none
$stateSaId = Invoke-AzCli storage account show -n $stateSa -g $stateRg --query id -o tsv

Write-Host "Creating GitHub Actions identity..."
$idName = "id-$Prefix-github"
Invoke-AzCli identity create -n $idName -g $stateRg -l $Location --output none
$clientId    = Invoke-AzCli identity show -n $idName -g $stateRg --query clientId -o tsv
$principalId = Invoke-AzCli identity show -n $idName -g $stateRg --query principalId -o tsv

$subjects = @{
  "github-main" = "repo:${GitHubRepo}:ref:refs/heads/main"
  "github-pr"   = "repo:${GitHubRepo}:pull_request"
}
foreach ($name in $subjects.Keys) {
  $exists = Invoke-AzCli identity federated-credential list --identity-name $idName -g $stateRg --query "[?name=='$name'].name" -o tsv
  if (-not $exists) {
    Invoke-AzCli identity federated-credential create --name $name --identity-name $idName -g $stateRg `
      --issuer "https://token.actions.githubusercontent.com" `
      --subject $subjects[$name] --audiences "api://AzureADTokenExchange" --output none
  }
}

$appRgId = "/subscriptions/$sub/resourceGroups/$appRg"

Write-Host "`nGranting roles to the GitHub identity..."
Grant-Role $principalId "ServicePrincipal" "Contributor"                   $appRgId
Grant-Role $principalId "ServicePrincipal" "Storage Blob Data Contributor" $appRgId    # upload site files
Grant-Role $principalId "ServicePrincipal" "Storage Blob Data Contributor" $stateSaId  # read/write tfstate

Write-Host "Granting roles to you (for local terraform + testing)..."
$me = Invoke-AzCli ad signed-in-user show --query id -o tsv
Grant-Role $me "User" "Storage Blob Data Contributor" $stateSaId
Grant-Role $me "User" "Storage Blob Data Contributor" $appRgId

$backendFile = Join-Path $PSScriptRoot "..\infra\backend.hcl"
@"
resource_group_name  = "$stateRg"
storage_account_name = "$stateSa"
container_name       = "tfstate"
key                  = "cloud-resume.tfstate"
"@ | Set-Content -Encoding utf8 $backendFile

Write-Host @"

Done. Wrote infra/backend.hcl.

Add these as GitHub repository VARIABLES
(Settings > Secrets and variables > Actions > Variables tab):

  AZURE_CLIENT_ID          $clientId
  AZURE_TENANT_ID          $tenant
  AZURE_SUBSCRIPTION_ID    $sub
  AZURE_RESOURCE_GROUP     $appRg
  TFSTATE_RESOURCE_GROUP   $stateRg
  TFSTATE_STORAGE_ACCOUNT  $stateSa

Role assignments can take a few minutes to take effect.
"@
