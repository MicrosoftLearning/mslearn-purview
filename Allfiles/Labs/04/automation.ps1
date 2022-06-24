function Check-HttpRedirect($uri)
{
    $httpReq = [system.net.HttpWebRequest]::Create($uri)
    $httpReq.Accept = "text/html, application/xhtml+xml, */*"
    $httpReq.method = "GET"   
    $httpReq.AllowAutoRedirect = $false;
    
    #use them all...
    #[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls;

    $global:httpCode = -1;
    
    $response = "";            

    try
    {
        $res = $httpReq.GetResponse();

        $statusCode = $res.StatusCode.ToString();
        $global:httpCode = [int]$res.StatusCode;
        $cookieC = $res.Cookies;
        $resHeaders = $res.Headers;  
        $global:rescontentLength = $res.ContentLength;
        $global:location = $null;
                                
        try
        {
            $global:location = $res.Headers["Location"].ToString();
            return $global:location;
        }
        catch
        {
        }

        return $null;

    }
    catch
    {
        $res2 = $_.Exception.InnerException.Response;
        $global:httpCode = $_.Exception.InnerException.HResult;
        $global:httperror = $_.exception.message;

        try
        {
            $global:location = $res2.Headers["Location"].ToString();
            return $global:location;
        }
        catch
        {
        }
    } 

    return $null;
}

function GetRandomString() {
    param (
        [parameter(Mandatory=$true)]
        $Length,

        [parameter(Mandatory=$false)]
        [switch]$IncludeCaps
    )

    $source = (48..57) + (97..122)
    if ($IncludeCaps) {
        $source = $source + (65..90)
    }

    return (-join ($source | Get-Random -Count $Length | % {[char]$_}));
}

function GetToken($res, $tokenType)
{
    $context = Get-AzContext;
    $global:loginDomain = $context.Tenant.Id;
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2";
    $item = Get-AzAccessToken -ResourceUrl $res;
    
    return $item.token;
}

function Wait-ForOperation {
    
    param(

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$false)]
    [String]
    $OperationId
    )

    if ([string]::IsNullOrWhiteSpace($OperationId)) {
        Write-Information "Cannot wait on an empty operation id."
        return
    }

    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/operationResults/$($OperationId)?api-version=2019-06-01-preview"
    $result = Invoke-RestMethod  -Uri $uri -Method GET -Headers @{ Authorization="Bearer $synapseToken" }

    while ($result.status -ne $null) {
        
        if ($result.status -eq "Failed") {
            throw $result.error
        }

        Write-Information "Waiting for operation to complete (status is $($result.status))..."
        Start-Sleep -Seconds 10
        $result = Invoke-RestMethod  -Uri $uri -Method GET -Headers @{ Authorization="Bearer $synapseToken" }
    }

    return $result
}

function Control-SQLPool {

    param(
    [parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    [parameter(Mandatory=$true)]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $SQLPoolName,

    [parameter(Mandatory=$true)]
    [String]
    $Action,

    [parameter(Mandatory=$false)]
    [String]
    $SKU
    )

    $uri = "https://management.azure.com/subscriptions/$($SubscriptionId)/resourcegroups/$($ResourceGroupName)/providers/Microsoft.Synapse/workspaces/$($WorkspaceName)/sqlPools/$($SQLPoolName)#ACTION#?api-version=2019-06-01-preview"
    $method = "POST"
    $body = $null

    if (($Action.ToLowerInvariant() -eq "pause") -or ($Action.ToLowerInvariant() -eq "resume")) {

        $uri = $uri.Replace("#ACTION#", "/$($Action)")

    } elseif ($Action.ToLowerInvariant() -eq "scale") {
        
        $uri = $uri.Replace("#ACTION#", "")
        $method = "PATCH"
        $body = "{""sku"":{""name"":""$($SKU)""}}"

    } else {
        
        throw "The $($Action) control action is not supported."

    }

    $result = Invoke-RestMethod  -Uri $uri -Method $method -Body $body -Headers @{ Authorization="Bearer $managementToken" } -ContentType "application/json"

    return $result
}

function Get-SQLPool {

    param(
    [parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    [parameter(Mandatory=$true)]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $SQLPoolName
    )

    $uri = "https://management.azure.com/subscriptions/$($SubscriptionId)/resourcegroups/$($ResourceGroupName)/providers/Microsoft.Synapse/workspaces/$($WorkspaceName)/sqlPools/$($SQLPoolName)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method GET -Headers @{ Authorization="Bearer $managementToken" } -ContentType "application/json"

    return $result
}

function Wait-ForSQLPool {

    param(
    [parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    [parameter(Mandatory=$true)]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $SQLPoolName,

    [parameter(Mandatory=$false)]
    [String]
    $TargetStatus
    )

    Write-Information "Waiting for any pending operation to be properly triggered..."
    Start-Sleep -Seconds 20

    $result = Get-SQLPool -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -SQLPoolName $SQLPoolName

    if ($TargetStatus) {
        while ($result.properties.status -ne $TargetStatus) {
            Write-Information "Current status is $($result.properties.status). Waiting for $($TargetStatus) status..."
            Start-Sleep -Seconds 10
            $result = Get-SQLPool -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -SQLPoolName $SQLPoolName
        }
    }

    Write-Information "The SQL pool has now the $($TargetStatus) status."
    return $result
}


function Execute-SQLScriptFile {

    param(
    [parameter(Mandatory=$true)]
    [String]
    $SQLScriptsPath,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $SQLPoolName,

    [parameter(Mandatory=$true)]
    [String]
    $FileName,

    [parameter(Mandatory=$false)]
    [Hashtable]
    $Parameters,

    [parameter(Mandatory=$false)]
    [Boolean]
    $ForceReturn,

    [parameter(Mandatory=$false)]
    [Boolean]
    $UseAPI = $false
    )

    $sqlQuery = Get-Content -Raw -Path "$($SQLScriptsPath)/$($FileName).sql"

    if ($Parameters) {
        foreach ($key in $Parameters.Keys) {
            $sqlQuery = $sqlQuery.Replace("#$($key)#", $Parameters[$key])
        }
    }

    #https://aka.ms/vs/15/release/vc_redist.x64.exe 
    #https://www.microsoft.com/en-us/download/confirmation.aspx?id=56567
    #https://go.microsoft.com/fwlink/?linkid=2082790

    if ($UseAPI) {
        Execute-SQLQuery -WorkspaceName $WorkspaceName -SQLPoolName $SQLPoolName -SQLQuery $sqlQuery -ForceReturn $ForceReturn
    } else {
        if ($ForceReturn) {
            Invoke-SqlCmd -Query $sqlQuery -ServerInstance $sqlEndpoint -Database $sqlPoolName -Username $sqlUser -Password $global:sqlPassword
            #& sqlcmd -S $sqlEndpoint -d $sqlPoolName -U $userName -P $password -G -I -Q $sqlQuery
        } else {
            Invoke-SqlCmd -Query $sqlQuery -ServerInstance $sqlEndpoint -Database $sqlPoolName -Username $sqlUser -Password $global:sqlPassword
            #& sqlcmd -S $sqlEndpoint -d $sqlPoolName -U $userName -P $password -G -I -Q $sqlQuery
        }
    }
}

function Create-KeyVaultLinkedService {
    
    param(
    [parameter(Mandatory=$true)]
    [String]
    $TemplatesPath,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $Name
    )

    $keyVaultTemplate = Get-Content -Path "$($TemplatesPath)/key_vault_linked_service.json"
    $keyVault = $keyVaultTemplate.Replace("#LINKED_SERVICE_NAME#", $Name).Replace("#KEY_VAULT_NAME#", $Name)
    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/linkedservices/$($Name)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $keyVault -Headers @{ Authorization="Bearer $synapseToken" } -ContentType "application/json"
 
    return $result
}

function Create-IntegrationRuntime {
    
    param(
    [parameter(Mandatory=$true)]
    [String]
    $TemplatesPath,

    [parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    [parameter(Mandatory=$true)]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $Name,

    [parameter(Mandatory=$true)]
    [Int32]
    $CoreCount,

    [parameter(Mandatory=$true)]
    [Int32]
    $TimeToLive
    )

    $integrationRuntimeTemplate = Get-Content -Path "$($TemplatesPath)/integration_runtime.json"
    $integrationRuntime = $integrationRuntimeTemplate.Replace("#INTEGRATION_RUNTIME_NAME#", $Name).Replace("#CORE_COUNT#", $CoreCount).Replace("#TIME_TO_LIVE#", $TimeToLive)
    $uri = "https://management.azure.com/subscriptions/$($SubscriptionId)/resourcegroups/$($ResourceGroupName)/providers/Microsoft.Synapse/workspaces/$($WorkspaceName)/integrationruntimes/$($Name)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $integrationRuntime -Headers @{ Authorization="Bearer $managementToken" } -ContentType "application/json"
 
    return $result
}

function Create-DataLakeLinkedService {
    
    param(
    [parameter(Mandatory=$true)]
    [String]
    $TemplatesPath,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $Name,

    [parameter(Mandatory=$true)]
    [String]
    $Key
    )

    $itemTemplate = Get-Content -Path "$($TemplatesPath)/data_lake_linked_service.json"
    $item = $itemTemplate.Replace("#LINKED_SERVICE_NAME#", $Name).Replace("#STORAGE_ACCOUNT_NAME#", $Name).Replace("#STORAGE_ACCOUNT_KEY#", $Key)
    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/linkedservices/$($Name)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $item -Headers @{ Authorization="Bearer $synapseToken" } -ContentType "application/json"
    
    return $result
}

function Create-BlobStorageLinkedService {
    
    param(
    [parameter(Mandatory=$true)]
    [String]
    $TemplatesPath,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $Name,

    [parameter(Mandatory=$true)]
    [String]
    $Key
    )

    $keyVaultTemplate = Get-Content -Path "$($TemplatesPath)/blob_storage_linked_service.json"
    $keyVault = $keyVaultTemplate.Replace("#LINKED_SERVICE_NAME#", $Name).Replace("#STORAGE_ACCOUNT_NAME#", $Name).Replace("#STORAGE_ACCOUNT_KEY#", $Key)
    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/linkedservices/$($Name)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $keyVault -Headers @{ Authorization="Bearer $synapseToken" } -ContentType "application/json"
 
    return $result
}

function Create-SQLPoolKeyVaultLinkedService {
    
    param(
    [parameter(Mandatory=$true)]
    [String]
    $TemplatesPath,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $Name,

    [parameter(Mandatory=$true)]
    [String]
    $DatabaseName,

    [parameter(Mandatory=$true)]
    [String]
    $UserName,

    [parameter(Mandatory=$true)]
    [String]
    $KeyVaultLinkedServiceName,

    [parameter(Mandatory=$true)]
    [String]
    $SecretName
    )

    $itemTemplate = Get-Content -Path "$($TemplatesPath)/sql_pool_key_vault_linked_service.json"
    $item = $itemTemplate.Replace("#LINKED_SERVICE_NAME#", $Name).Replace("#WORKSPACE_NAME#", $WorkspaceName).Replace("#DATABASE_NAME#", $DatabaseName).Replace("#USER_NAME#", $UserName).Replace("#KEY_VAULT_LINKED_SERVICE_NAME#", $KeyVaultLinkedServiceName).Replace("#SECRET_NAME#", $SecretName)
    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/linkedServices/$($Name)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $item -Headers @{ Authorization="Bearer $synapseToken" } -ContentType "application/json"

    return $result
}

function Create-Dataset {
    
    param(
    [parameter(Mandatory=$true)]
    [String]
    $DatasetsPath,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $Name,

    [parameter(Mandatory=$true)]
    [String]
    $LinkedServiceName
    )

    $itemTemplate = Get-Content -Path "$($DatasetsPath)/$($Name).json"
    $item = $itemTemplate.Replace("#LINKED_SERVICE_NAME#", $LinkedServiceName)
    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/datasets/$($Name)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $item -Headers @{ Authorization="Bearer $synapseToken" } -ContentType "application/json"
    
    return $result
}

function Create-Pipeline {
    
    param(
    [parameter(Mandatory=$true)]
    [String]
    $PipelinesPath,

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $Name,

    [parameter(Mandatory=$true)]
    [String]
    $FileName,

    [parameter(Mandatory=$false)]
    [Hashtable]
    $Parameters = $null
    )

    $item = Get-Content -Path "$($PipelinesPath)/$($FileName).json"
    
    if ($Parameters -ne $null) {
        foreach ($key in $Parameters.Keys) {
            $item = $item.Replace("#$($key)#", $Parameters[$key])
        }
    }

    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/pipelines/$($Name)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $item -Headers @{ Authorization="Bearer $synapseToken" } -ContentType "application/json"
    
    return $result
}

function Run-Pipeline {
    
    param(

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $Name
    )

    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/pipelines/$($Name)/createRun?api-version=2018-06-01"

    $result = Invoke-RestMethod  -Uri $uri -Method POST -Headers @{ Authorization="Bearer $synapseToken" } -ContentType "application/json"
    
    return $result
}

function Get-PipelineRun {
    
    param(

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $RunId
    )

    $uri = "https://$($WorkspaceName).dev.azuresynapse.net/pipelineruns/$($RunId)?api-version=2019-06-01-preview"

    $result = Invoke-RestMethod  -Uri $uri -Method GET -Headers @{ Authorization="Bearer $synapseToken" }
    
    return $result
}

function Wait-ForPipelineRun {
    
    param(

    [parameter(Mandatory=$true)]
    [String]
    $WorkspaceName,

    [parameter(Mandatory=$true)]
    [String]
    $RunId
    )

    Write-Information "Waiting for any pending operation to be properly triggered..."
    Start-Sleep -Seconds 20

    $result = Get-PipelineRun -WorkspaceName $WorkspaceName -RunId $RunId

    while ($result.status -eq "InProgress") {
        
        Write-Information "Waiting for operation to complete..."
        Start-Sleep -Seconds 10
        $result = Get-PipelineRun -WorkspaceName $WorkspaceName -RunId $RunId
    }

    return $result
}

function Get-PurviewMetadataPolicy()
{
    param(

    [parameter(Mandatory=$true)]
    [String]
    $AccountName

    )

    $type = "metadatapolicy";
    $rootUrl = "https://$AccountName.purview.azure.com";

    $url = "$rootUrl/policyStore/metadataPolicies?api-version=2021-07-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $global:purviewToken"}

    return $data.values;
}

function Add-PurviewRoleMember()
{
    param(

    [parameter(Mandatory=$true)]
    [String]
    $AccountName,

    [parameter(Mandatory=$true)]
    [String]
    $RoleName,

    [parameter(Mandatory=$true)]
    [String]
    $ServicePrincipalId

    )
    $purviewRoles = @{
        "Collection admins" = "purviewmetadatarole_builtin_collection-administrator:$($purviewAccountName)"
        "Data readers" = "purviewmetadatarole_builtin_purview-reader:$($purviewAccountName)"
        "Data curators" = "purviewmetadatarole_builtin_data-curator:$($purviewAccountName)"
        "Data source admins" = "purviewmetadatarole_builtin_data-source-administrator:$($purviewAccountName)"
        "Insights readers" = "purviewmetadatarole_builtin_insights-reader:$($purviewAccountName)"
        "Policy authors" = "purviewmetadatarole_builtin_policy-author:$($purviewAccountName)"
        "Workflow admins" = "purviewmetadatarole_builtin_workflow-administrator:$($purviewAccountName)"
    }

    $purviewPolicy = Get-MetadataPolicy -AccountName $AccountName
    
    foreach ($attributeRule in $purviewPolicy.properties.attributeRules) {
        if ($attributeRule.name -eq $purviewRoles[$RoleName]) {
                $attributeRule.dnfCondition[0][0].attributeValueIncludedIn += $ServicePrincipalId
        }
    }

    $url = "$rootUrl/policyStore/metadataPolicies/$($purviewPolicy.id)?api-version=2021-07-01-preview"
        
    Invoke-RestMethod -Method PUT -Uri $url -Headers @{"Authorization"="Bearer $global:purviewToken"} -Body (ConvertTo-Json $purviewPolicy -Depth 20) -ContentType "application/json"
}