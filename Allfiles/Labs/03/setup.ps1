$InformationPreference = "Continue"

Connect-AzAccount -UseDeviceAuthentication;

$allFilesPath = "$home/msftpurview/Allfiles";
$labPath = "$allFilesPath/Labs";
$modulePath = "$labPath/03";
$exportPath = "$modulePath/export";
$templatesPath = "$allFilesPath/templates";
$dataSetsPath = "$allFilesPath/datasets";
$pipelinesPath = "$allFilesPath/pipelines";
$filesPath = "$labPath/files/";

#include common functions
. $labPath/common/MicrosoftPurview.ps1

SelectSubscription;

Register-ResourceProvider -ProviderNamespace Microsoft.Purview
Register-ResourceProvider -ProviderNamespace Microsoft.Synapse

$location = "eastus";
$suffix = GetSuffix;
$accountName = "main$suffix";
$resourceGroupName = "msftpurview-$suffix";
$purviewName = "main$suffix";

$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id
$global:logindomain = (Get-AzContext).Tenant.Id;

$rooturl = "https://$purviewName.purview.azure.com";

#create the resource group
New-AzResourceGroup -Name $resourceGroupName -Location $location -force;

#run the deployment...
$templatesFile1 = "$labPath/template1.json"
$templatesFile2 = "$labPath/template2.json"
$templatesFile2Final = "$labPath/template2-final.json"

$parametersFile = "$labPath/parameters.json"
$parametersFileFinal = "$labPath/parameters-final.json"


$content = Get-Content -Path $parametersFile -raw;
$content = $content.Replace("GET-SUFFIX",$suffix);
$content | Set-Content -Path $parametersFileFinal;

New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templatesFile1 -TemplateParameterFile $parametersFileFinal;

Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
Install-Module Az.Purview

$provisionedPurviewAccount = Get-AzPurviewAccount -Name $purviewName -ResourceGroupName $resourceGroupName

Write-Information "Managed storage account: $($provisionedPurviewAccount.ManagedResourceStorageAccount)"
Write-Information "Managed Event Hub namespace: $($provisionedPurviewAccount.ManagedResourceEventHubNamespace)"

$content = Get-Content -Path $templatesFile2 -Raw
$content = $content.Replace("##MANAGED_STORAGE_ACCOUNT_RESOURCE_ID##",$provisionedPurviewAccount.ManagedResourceStorageAccount);
$content | Set-Content -Path $templatesFile2Final;

New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templatesFile2Final -TemplateParameterFile $parametersFileFinal;

if ([System.Environment]::OSVersion.Platform -eq "Unix")
{
        $azCopyLink = Check-HttpRedirect "https://aka.ms/downloadazcopy-v10-linux"

        if (!$azCopyLink)
        {
                $azCopyLink = "https://azcopyvnext.azureedge.net/release20200709/azcopy_linux_amd64_10.15.0.tar.gz"
        }

        Invoke-WebRequest $azCopyLink -OutFile "azCopy.tar.gz"
        tar -xf "azCopy.tar.gz"
        $azCopyCommand = (Get-ChildItem -Path "$labPath" -Recurse azcopy).Directory.FullName

        if ($azCopyCommand.Count -gt 1)
        {
                $azCopyCommand = $azCopyCommand[0]
        }
        
        cd $azCopyCommand;
        chmod +x azcopy;
        cd $modulePath;
        $azCopyCommand += "\azcopy";
}
else
{
        $azCopyLink = Check-HttpRedirect "https://aka.ms/downloadazcopy-v10-windows"

        if (!$azCopyLink)
        {
                $azCopyLink = "https://azcopyvnext.azureedge.net/release20200501/azcopy_windows_amd64_10.4.3.zip"
        }

        Invoke-WebRequest $azCopyLink -OutFile "azCopy.zip"
        Expand-Archive "azCopy.zip" -DestinationPath ".\" -Force
        $azCopyCommand = (Get-ChildItem -Path ".\" -Recurse azcopy.exe).Directory.FullName
        $azCopyCommand += "\azcopy"
}

#upload some files
$publicDataUrl = $filesPath;
$dataLakeAccountName = "storage$suffix";
$dataLakeStorageUrl = "https://"+ $dataLakeAccountName + ".dfs.core.windows.net/"
$dataLakeStorageBlobUrl = "https://"+ $dataLakeAccountName + ".blob.core.windows.net/"
$dataLakeStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $dataLakeAccountName)[0].Value
$dataLakeContext = New-AzStorageContext -StorageAccountName $dataLakeAccountName -StorageAccountKey $dataLakeStorageAccountKey

$wwiContainer1 = New-AzStorageContainer -Permission Container -name "wwi-01" -context $dataLakeContext -ea silentlycontinue;
$wwiContainer2 = New-AzStorageContainer -Permission Container -name "wwi-02" -context $dataLakeContext -ea silentlycontinue;
$wwiContainer3 = New-AzStorageContainer -Permission Container -name "wwi-03" -context $dataLakeContext -ea silentlycontinue;

$destinationSasKey = New-AzStorageContainerSASToken -Container "wwi-02" -Context $dataLakeContext -Permission rwdl

Write-Information "Copying single files from the public data account..."

$singleFiles = @{
        customer_info = "wwi-02/customer-info/customerinfo.csv"
        products = "wwi-02/data-generators/generator-product.csv"
        dates = "wwi-02/data-generators/generator-date.csv"
}

foreach ($singleFile in $singleFiles.Keys) {
        $source = $publicDataUrl + $singleFiles[$singleFile]
        $destination = $dataLakeStorageBlobUrl + $singleFiles[$singleFile] + $destinationSasKey
        Write-Information "Copying file $($source) to $($destination)"
        & $azCopyCommand copy $source $destination 
}


$userName = ((az ad signed-in-user show) | ConvertFrom-JSON).UserPrincipalName
$user = Get-AzADUser -UserPrincipalName $username
$objectId = $user.id;

#get tokens
$global:mgmtToken = GetToken "https://management.azure.com" "mgmt";
$global:token = GetToken "https://purview.azure.net" "purview";

$global:mgmtheaders = @{
        Authorization="Bearer $mgmttoken"
        "Content-Type"="application/json"
    }

#ensure collection admin present
AddRootCollectionAdmin $objectId;
