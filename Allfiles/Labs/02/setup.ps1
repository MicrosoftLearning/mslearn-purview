. .\automation.ps1

$location = "eastus";
$suffix = GetRandomString -Length 10
$sqlAdminPassword = (GetRandomString -Length 10) + "!123"

$resourceGroupName = "msftpurview-$suffix"
$aadUserName = (Get-AzContext).Account.Id
$aadUserId = (Get-AzADUser -UserPrincipalName (Get-AzContext).Account).Id

$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id
$global:logindomain = (Get-AzContext).Tenant.Id;

$reportsPath = ".\reports"
$templatesPath = ".\templates"
$datasetsPath = ".\datasets"
$dataflowsPath = ".\dataflows"
$pipelinesPath = ".\pipelines"
$sqlScriptsPath = ".\sql"

#create the resource group
New-AzResourceGroup -Name $resourceGroupName -Location $location;

#run the deployment...
$templateFileTemplate = "template.json"
$templateFile = "template-final.json"
$parametersFileTemplate = "template-parameters.json"
$parametersFile = "template-parameters-final.json"

$templateContent = Get-Content -Path $templateFileTemplate -Raw
$templateContent = $templateContent.Replace("##SIGNED_IN_USER_ID##", $aadUserId)
Set-Content -Path $templateFile -Value $templateContent
$parametersContent = Get-Content -Path $parametersFileTemplate -Raw
$parametersContent = $parametersContent.Replace("##UNIQUE_SUFFIX##", $suffix).Replace("##SQL_ADMINISTRATOR_LOGIN_PASSWORD##", $sqlAdminPassword)
Set-Content -Path $parametersFile -Value $parametersContent

New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile "$parametersFile";

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

# Get authentication tokens for Azure Management and Microsoft Purview REST APIs
$global:managementToken = GetToken "https://management.azure.com" "mgmt"
$global:purviewToken = GetToken "https://purview.azure.net" "purview"
$global:synapseToken = GetToken "https://dev.azuresynapse.net" "synapse"

$uniqueId =  (Get-AzResourceGroup -Name $resourceGroupName).Tags["DeploymentId"]
$resourceGroupLocation = (Get-AzResourceGroup -Name $resourceGroupName).Location
$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id
$global:logindomain = (Get-AzContext).Tenant.Id;
$global:sqlEndpoint = "$($synapseWorkspaceName).sql.azuresynapse.net"
$global:sqlUser = "asa.sql.admin"
$global:sqlPassword = $sqlAdminPassword

$synapseWorkspaceName = "asaworkspace$($uniqueId)"
$purviewAccountName = "asapurview$($uniqueId)"
$dataLakeAccountName = "asadatalake$($uniqueId)"
$blobStorageAccountName = "asastore$($uniqueId)"
$keyVaultName = "asakeyvault$($uniqueId)"
$keyVaultSQLUserSecretName = "SQL-USER-ASA"
$sqlPoolName = "SQLPool01"
$integrationRuntimeName = "AzureIntegrationRuntime01"

$publicDataUrl = "https://solliancepublicdata.blob.core.windows.net/"
$dataLakeStorageUrl = "https://"+ $dataLakeAccountName + ".dfs.core.windows.net/"
$dataLakeStorageBlobUrl = "https://"+ $dataLakeAccountName + ".blob.core.windows.net/"
$dataLakeStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $dataLakeAccountName)[0].Value
$dataLakeContext = New-AzStorageContext -StorageAccountName $dataLakeAccountName -StorageAccountKey $dataLakeStorageAccountKey
$destinationSasKey = New-AzStorageContainerSASToken -Container "wwi-02" -Context $dataLakeContext -Permission rwdl
$blobStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $blobStorageAccountName)[0].Value

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

Write-Information "Copying sample sales raw data directories from the public data account..."

$dataDirectories = @{
        salesmall = "wwi-02/sale-small/Year=2019,wwi-02/sale-small/Year=2019/Quarter=Q4"
}

foreach ($dataDirectory in $dataDirectories.Keys) {

        $vals = $dataDirectories[$dataDirectory].tostring().split(",");

        $source = $publicDataUrl + $vals[1];

        $path = $vals[0];

        $destination = $dataLakeStorageBlobUrl + $path + $destinationSasKey
        Write-Information "Copying directory $($source) to $($destination)"
        & $azCopyCommand copy $source $destination --recursive=true
}


Write-Information "Start the $($sqlPoolName) SQL pool if needed."

$result = Get-SQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $synapseWorkspaceName -SQLPoolName $sqlPoolName
if ($result.properties.status -ne "Online") {
    Control-SQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $synapseWorkspaceName -SQLPoolName $sqlPoolName -Action resume
    Wait-ForSQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $synapseWorkspaceName -SQLPoolName $sqlPoolName -TargetStatus Online
}

Write-Information "Create SQL logins in master SQL pool"

$params = @{ PASSWORD = $sqlAdminPassword }
$result = Execute-SQLScriptFile -SQLScriptsPath $sqlScriptsPath -WorkspaceName $synapseWorkspaceName -SQLPoolName "master" -FileName "01-create-logins" -Parameters $params
$result

Write-Information "Create SQL users and role assignments in $($sqlPoolName)"

$params = @{ USER_NAME = $aadUserName }
$result = Execute-SQLScriptFile -SQLScriptsPath $sqlScriptsPath -WorkspaceName $synapseWorkspaceName -SQLPoolName $sqlPoolName -FileName "02-create-users" -Parameters $params
$result

Write-Information "Create schemas in $($sqlPoolName)"

$params = @{}
$result = Execute-SQLScriptFile -SQLScriptsPath $sqlScriptsPath -WorkspaceName $synapseWorkspaceName -SQLPoolName $sqlPoolName -FileName "03-create-schemas" -Parameters $params
$result

Write-Information "Create tables in the [wwi] schema in $($sqlPoolName)"

$params = @{}
$result = Execute-SQLScriptFile -SQLScriptsPath $sqlScriptsPath -WorkspaceName $synapseWorkspaceName -SQLPoolName $sqlPoolName -FileName "04-create-tables-in-wwi-schema" -Parameters $params
$result


Write-Information "Create KeyVault linked service $($keyVaultName)"

$result = Create-KeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $synapseWorkspaceName -Name $keyVaultName
Wait-ForOperation -WorkspaceName $synapseWorkspaceName -OperationId $result.operationId

Write-Information "Create Integration Runtime $($integrationRuntimeName)"

$result = Create-IntegrationRuntime -TemplatesPath $templatesPath -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $synapseWorkspaceName -Name $integrationRuntimeName -CoreCount 16 -TimeToLive 60
Wait-ForOperation -WorkspaceName $synapseWorkspaceName -OperationId $result.operationId

Write-Information "Create Data Lake linked service $($dataLakeAccountName)"

$result = Create-DataLakeLinkedService -TemplatesPath $templatesPath -WorkspaceName $synapseWorkspaceName -Name $dataLakeAccountName  -Key $dataLakeStorageAccountKey
Wait-ForOperation -WorkspaceName $synapseWorkspaceName -OperationId $result.operationId

Write-Information "Create Blob Storage linked service $($blobStorageAccountName)"

$result = Create-BlobStorageLinkedService -TemplatesPath $templatesPath -WorkspaceName $synapseWorkspaceName -Name $blobStorageAccountName  -Key $blobStorageAccountKey
Wait-ForOperation -WorkspaceName $synapseWorkspaceName -OperationId $result.operationId

Write-Information "Create linked service for SQL pool $($sqlPoolName) with user asa.sql.admin"

$linkedServiceName = $sqlPoolName.ToLower()
$result = Create-SQLPoolKeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $synapseWorkspaceName -Name $linkedServiceName -DatabaseName $sqlPoolName `
                 -UserName "asa.sql.admin" -KeyVaultLinkedServiceName $keyVaultName -SecretName $keyVaultSQLUserSecretName
Wait-ForOperation -WorkspaceName $synapseWorkspaceName -OperationId $result.operationId

Write-Information "Create linked service for SQL pool $($sqlPoolName) with user asa.sql.highperf"

$linkedServiceName = "$($sqlPoolName.ToLower())_highperf"
$result = Create-SQLPoolKeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $synapseWorkspaceName -Name $linkedServiceName -DatabaseName $sqlPoolName `
                 -UserName "asa.sql.highperf" -KeyVaultLinkedServiceName $keyVaultName -SecretName $keyVaultSQLUserSecretName
Wait-ForOperation -WorkspaceName $synapseWorkspaceName -OperationId $result.operationId

Write-Information "Create data sets for data load in SQL pool $($sqlPoolName)"

$loadingDatasets = @{
        wwi02_date_adls = $dataLakeAccountName
        wwi02_product_adls = $dataLakeAccountName
        wwi02_sale_small_adls = $dataLakeAccountName
        wwi02_date_asa = $sqlPoolName.ToLower()
        wwi02_product_asa = $sqlPoolName.ToLower()
        wwi02_sale_small_asa = "$($sqlPoolName.ToLower())_highperf"
}

foreach ($dataset in $loadingDatasets.Keys) {
        Write-Information "Creating dataset $($dataset)"
        $result = Create-Dataset -DatasetsPath $datasetsPath -WorkspaceName $synapseWorkspaceName -Name $dataset -LinkedServiceName $loadingDatasets[$dataset]
        Wait-ForOperation -WorkspaceName $synapseWorkspaceName -OperationId $result.operationId
}

Write-Information "Create pipeline to load the SQL pool"

$params = @{
        BLOB_STORAGE_LINKED_SERVICE_NAME = $blobStorageAccountName
}
$loadingPipelineName = "Import data from data lake"
$fileName = "load_sql_pool_from_data_lake"

Write-Information "Creating pipeline $($loadingPipelineName)"

$result = Create-Pipeline -PipelinesPath $pipelinesPath -WorkspaceName $synapseWorkspaceName -Name $loadingPipelineName -FileName $fileName -Parameters $params
Wait-ForOperation -WorkspaceName $synapseWorkspaceName -OperationId $result.operationId

Write-Information "Running pipeline $($loadingPipelineName)"

$result = Run-Pipeline -WorkspaceName $synapseWorkspaceName -Name $loadingPipelineName
$result = Wait-ForPipelineRun -WorkspaceName $synapseWorkspaceName -RunId $result.runId
$result

Add-PurviewRoleMember -AccountName $purviewAccountName -RoleName "Data curators" -ServicePrincipalId "96fe3d5c-08da-42cc-b36d-c52cc87fcd13"
