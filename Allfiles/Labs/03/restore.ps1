#include common
. ./MicrosoftPurview.ps1

$labPath = "$home/msftpurview/Allfiles/Labs/03";
$exportPath = "$labPath/export";

$suffix = GetSuffix;

Connect-AzAccount -UseDeviceAuthentication;

Select-AzSubscription "{SUBSCRIPTION_NAME}"

$purviewName = "main$suffix";
$apiVersion = "2022-02-01-preview";
$resourceGroupName = "msftpurview-$suffix";
$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id
$global:logindomain = (Get-AzContext).Tenant.Id;

$rooturl = "https://$purviewName.purview.azure.com";

#get tokens
$global:mgmtToken = GetToken "https://management.azure.com" "mgmt";
$global:token = GetToken "https://purview.azure.net" "purview";

#import the objects
ImportObjects "$exportPath";