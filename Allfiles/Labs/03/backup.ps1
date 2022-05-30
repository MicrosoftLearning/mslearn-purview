#include common
. MicrosoftPurview.ps1

[Reflection.Assembly]::LoadWithPartialName("Newtonsoft.Json.dll”);

$profilePath = $env:USERPROFILE;
$exportPath = "$profilePath\OneDrive\My Scripts\Microsoft";
$exportPath = "C:\github\solliancenet\LP_AZ_microsoft-purview\Allfiles\Labs\03\export"

cd $exportPath;

$suffix = GetSuffix;

$purviewName = "main$suffix";
$apiVersion = "2022-02-01-preview";
$subscriptionId = "{SUBSCRIPTION_ID}";
$resourceGroupName = "{RESOURCE_GROUP_NAME}";

$rooturl = "https://$purviewName.purview.azure.com";

#get tokens
$global:mgmtToken = GetToken "https://management.azure.com" "mgmt";
$global:token = GetToken "https://purview.azure.net" "purview";

#import the objects
ExportObjects "$exportPath";