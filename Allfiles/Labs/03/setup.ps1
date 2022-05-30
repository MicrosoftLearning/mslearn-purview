#include common
. MicrosoftPurview.ps1

$location = "eastus";
$suffix = GetSuffix;
$accountName = "main-$suffix";
$rsGroupName = "msftpurview-$suffix";

$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id
$global:logindomain = (Get-AzContext).Tenant.Id;

#create the resource group
New-AzResourceGroup -Name $rsGroupName -Location $location;

#run the deployment...
$templatesFile = "template.json"
$parametersFile = "parameters.json"
New-AzResourceGroupDeployment -ResourceGroupName $rsGroupName -TemplateFile $templatesFile -TemplateParameterFile "$parametersFile";

if ([System.Environment]::OSVersion.Platform -eq "Unix")
{
        $azCopyLink = Check-HttpRedirect "https://aka.ms/downloadazcopy-v10-linux"

        if (!$azCopyLink)
        {
                $azCopyLink = "https://azcopyvnext.azureedge.net/release20200709/azcopy_linux_amd64_10.5.0.tar.gz"
        }

        Invoke-WebRequest $azCopyLink -OutFile "azCopy.tar.gz"
        tar -xf "azCopy.tar.gz"
        $azCopyCommand = (Get-ChildItem -Path ".\" -Recurse azcopy).Directory.FullName
        cd $azCopyCommand
        chmod +x azcopy
        cd ..
        $azCopyCommand += "\azcopy"
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
$publicDataUrl = "https://solliancepublicdata.blob.core.windows.net/"
$dataLakeAccountName = "storage$suffix";
$dataLakeStorageUrl = "https://"+ $dataLakeAccountName + ".dfs.core.windows.net/"
$dataLakeStorageBlobUrl = "https://"+ $dataLakeAccountName + ".blob.core.windows.net/"
$dataLakeStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $rsGroupName -AccountName $dataLakeAccountName)[0].Value
$dataLakeContext = New-AzStorageContext -StorageAccountName $dataLakeAccountName -StorageAccountKey $dataLakeStorageAccountKey
$destinationSasKey = New-AzStorageContainerSASToken -Container "wwi-02" -Context $dataLakeContext -Permission rwdl

Write-Information "Copying single files from the public data account..."

$singleFiles = @{
        customer_info = "wwi-02/customer-info/customerinfo.csv"
        products = "wwi-02/data-generators/generator-product/generator-product.csv"
        dates = "wwi-02/data-generators/generator-date.csv"
        customer = "wwi-02/data-generators/generator-customer.csv"
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

#ensure collection admin present
AddRootCollectionAdmin $objectId;

#import all the exported objects
ImportObjects;