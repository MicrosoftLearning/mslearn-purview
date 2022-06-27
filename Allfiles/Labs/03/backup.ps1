Connect-AzAccount -UseDeviceAuthentication;

SelectSubscription

$labPath = "$home/msftpurview/Allfiles/Labs";
$modulePath = "$labPath/03";
$exportPath = "$modulePath/export";

#include common functions
. $labPath/common/MicrosoftPurview.ps1

$location = "eastus";
$suffix = GetSuffix;
$accountName = "main$suffix";
$resourceGroupName = "msftpurview-$suffix";

$purviewName = "main$suffix";
$apiVersion = "2022-02-01-preview";

$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id
$global:logindomain = (Get-AzContext).Tenant.Id;

$rooturl = "https://$purviewName.purview.azure.com";

#get tokens
$global:mgmtToken = GetToken "https://management.azure.com" "mgmt";
$global:token = GetToken "https://purview.azure.net" "purview";

#import the objects
ExportObjects "$exportPath";