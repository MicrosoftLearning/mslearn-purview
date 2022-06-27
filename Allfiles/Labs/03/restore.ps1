#include common
. ./MicrosoftPurview.ps1

#Connect-AzAccount -UseDeviceAuthentication;

#SelectSubscription;

$allFilesPath = "$home/msftpurview/Allfiles";
$labPath = "$allFilesPath/Labs";
$modulePath = "$labPath/03";
$exportPath = "$modulePath/export";
$templatesPath = "$allFilesPath/templates";
$dataSetsPath = "$allFilesPath/datasets";
$pipelinesPath = "$allFilesPath/pipelines";
$filesPath = "$labPath/files/";

$suffix = GetSuffix;

$purviewName = "main$suffix";
$apiVersion = "2022-02-01-preview";
$resourceGroupName = "msftpurview-$suffix";
$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id
$global:logindomain = (Get-AzContext).Tenant.Id;

$rooturl = "https://$purviewName.purview.azure.com";

#get tokens
$global:mgmtToken = GetToken "https://management.azure.com" "mgmt" $true;
$global:token = GetToken "https://purview.azure.net" "purview" $true;

#import the objects
ImportObjects "$exportPath";