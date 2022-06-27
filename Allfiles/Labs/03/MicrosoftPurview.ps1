#https://docs.microsoft.com/en-us/rest/api/purview/

#https://atlas.apache.org/api/v2/index.html

function SelectSubscription()
{
    #select a subscription
    $subs = Get-AzSubscription | Select-Object
    if($subs.GetType().IsArray -and $subs.length -gt 1){
            Write-Host "You have multiple Azure subscriptions - please select the one you want to use:"
            for($i = 0; $i -lt $subs.length; $i++)
            {
                    Write-Host "[$($i)]: $($subs[$i].Name) (ID = $($subs[$i].Id))"
            }
            $selectedIndex = -1
            $selectedValidIndex = 0
            while ($selectedValidIndex -ne 1)
            {
                    $enteredValue = Read-Host("Enter 0 to $($subs.Length - 1)")
                    if (-not ([string]::IsNullOrEmpty($enteredValue)))
                    {
                        if ([int]$enteredValue -in (0..$($subs.Length - 1)))
                        {
                            $selectedIndex = [int]$enteredValue
                            $selectedValidIndex = 1
                        }
                        else
                        {
                            Write-Output "Please enter a valid subscription number."
                        }
                    }
                    else
                    {
                        Write-Output "Please enter a valid subscription number."
                    }
            }
            $selectedSub = $subs[$selectedIndex].Id
            Select-AzSubscription -SubscriptionId $selectedSub
            az account set --subscription $selectedSub
    }
}

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

function ExportObjects()
{
    $global:headers = @{
        Authorization="Bearer $token"
        "Content-Type"="application/json"
    }

    $global:mgmtheaders = @{
        Authorization="Bearer $mgmttoken"
        "Content-Type"="application/json"
    }

    ExportAccount $subscriptionId $resourceGroupName $purviewName

    ExportClassifications;

    ExportClassificationRules;

    ExportCollections;

    ExportRuleSets;

    ExportCredentials;

    ExportKeyVaultConnections;

    $policies = ExportMetadataPolicy;

    ExportEntities2;

    ExportTypes;

    ExportEntities;

    ExportResourceSets;

    ExportDataSources;

    ExportGlossaries;

    ExportSHIR;

    ExportADF $subscriptionId;
}

function GetAccount($subscriptionId, $resourceGroupName, $accountName)
{
    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Purview/accounts/$($accountName)?api-version=2021-07-01";

    $res = Invoke-RestMethod -Method get -Uri $url -Headers $mgmtheaders

    return $res;
}

function ExportAccount($subscriptionId, $resourceGroupName, $accountName)
{
    $type = "account";

    $account = GetAccount $subscriptionId $resourceGroupName $accountName;

    ExportObject $type $account $account.name;
}

function ExportSHIR()
{
    $type = "runtimes";

    $url = "$rootUrl/proxy/integrationRuntimes?api-version=2020-12-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/proxy/integrationRuntimes/$($name)?api-version=2020-12-01-preview"

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers $headers

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }
    }
}

function ExportADF($subscriptionId)
{
    $type = "adf";

    $url = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.DataFactory/factories?api-version=2018-06-01";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $mgmtheaders

    foreach($item in $data.value)
    {
        $name = $item.name;

        ExportObject $type $item $item.name;
    }
}

function ExportKeyVaultConnections()
{
    $type = "keyvaultconnection";

    $url = "$rootUrl/scan/azureKeyVaults?api-version=2022-02-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/scan/azureKeyVaults/$($name)?api-version=2022-02-01-preview"

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }
    }
}

function ExportCredentials()
{
    $type = "credential";

    $url = "$rootUrl/scan/credentials?api-version=2022-02-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/scan/credentials/$($name)?api-version=2022-02-01-preview"

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }
    }
}

function ExportDataSources()
{
    $type = "datasource";

    $url = "$rootUrl/scan/datasources?api-version=$apiVersion";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/scan/datasources/$($name)?api-version=$apiVersion"   

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }

        ExportDataSourceScans $c.name;
    }
}

function ExportDataSourceScans($id)
{
    $type = "datasourcescan";

    $url = "$rootUrl/scan/datasources/$id/scans?api-version=$apiVersion";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/scan/datasources/$id/scans/$($name)?api-version=$apiVersion";

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }

        ExportDataSourceScanTrigger $Id $name;
    }
}

function ExportDataSourceScanTrigger($dsId, $scanName)
{
    $type = "datasourcescantrigger";

    $url = "$rootUrl/scan/datasources/$dsid/scans/$($scanName)/triggers/default?api-version=$apiVersion";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    ExportObject $type $data $scanName;
}

function ExportResourceSets()
{
    $type = "resourceset";

    $url = "$rootUrl/account/resourceSetRuleConfigs?api-version=2019-11-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/account/resourceSetRuleConfigs/$($name)?api-version=2019-11-01-preview"   

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }
    }
}

function ExportGlossaries()
{
    $type = "glossary";

    $url = "$rootUrl/catalog/api/atlas/v2/glossary";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data)
    {
        $name = $item.guid;

        $url = "$rootUrl/catalog/api/atlas/v2/glossary/$($name)"

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;

            ExportGlossaryTerms $c.guid;
        }
    }
}

function ExportGlossaryTerms($id)
{
    $type = "glossaryterms";

    $url = "$rootUrl/catalog/api/glossary/$($id)/terms/export?api-version=2022-03-01-preview";

    $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

    ExportObject $type $c $c.name;
}

function ExportTypes()
{
    $type = "typedefs";

    $url = "$rootUrl/catalog/api/atlas/v2/types/typedefs";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.entityDefs)
    {
        $name = $item.name;

        ExportObject $type $item $name;
    }
}

function ExportMetadataPolicy()
{
    $type = "metadatapolicy";

    $url = "$rootUrl/policyStore/metadataPolicies?api-version=2021-07-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.values)
    {
        $name = $item.name;

        ExportObject $type $item $name;
    }

    return $data.values;
}

function ExportEntities2()
{
    $type = "entity";

    $url = "$rootUrl/catalog/api/browse?api-version=2022-03-01-preview";

    $post = "{`"entityType`": `"*`"}";

    $data = Invoke-RestMethod -Method post -Uri $url -Headers $headers -Body $post;

    foreach($item in $data.value)
    {
        $name = $item.entityGuid;
        $id = $item.id;

        $url = "$rootUrl/catalog/api/atlas/v2/entity/$($name)?api-version=$apiVersion"

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }

        ExportClassifications $name;
    }
}

function ExportEnum()
{
    ExportTypeDef "enum" "enum";
}

function ExportRelationships()
{
    ExportTypeDef "relationship" "relationship";
}

function ExportEntities($typeName)
{
    ExportTypeDef "entity" "entity";

    return;

    $type = "entity";

    $url = "$rootUrl/catalog/api/atlas/v2/entity/uniqueAttribute/type/$typeName";

    $post = "";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.entities)
    {
        $name = $item.entityGuid;

        $url = "$rootUrl/catalog/api/atlas/v2/entity/$($name)?api-version=$apiVersion"

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }

        ExportClassifications $name;
    }
}

function ExportTypeDef($type, $typeName)
{
    $items = @{};

    $url = "$rootUrl/catalog/api/atlas/v2/types/typedefs?type=$typeName&includeTermTemplate=true";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data."$($typeName)Defs")
    {
        $name = $item.name;

        ExportObject $type $item $item.name;

        $items.Add($item.name, $item);
    }

    return $items;
}

function ExportClassifications($id)
{
    $type = "classifications";

    $items = ExportTypeDef "classifications" "classification";
}

function ExportClassificationRules()
{
    $type = "classificationrules";

    $url = "$rootUrl/scan/classificationrules?api-version=2022-02-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach ($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/scan/classificationrules/$($name)?api-version=2022-02-01-preview"   

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }
    }
}

function ExportRuleSets()
{
    $type = "ruleset";

    $url = "$rootUrl/scan/scanrulesets?api-version=2022-02-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/scan/scanrulesets/$($name)?api-version=2022-02-01-preview"   

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }
    }
}

function ExportCollections()
{
    $type = "collection";

    $url = "$rootUrl/account/collections?api-version=2019-11-01-preview";

    $data = Invoke-RestMethod -Method get -Uri $url -Headers $headers

    foreach($item in $data.value)
    {
        $name = $item.name;

        $url = "$rootUrl/account/collections/$($name)?api-version=2019-11-01-preview"   

        $coll = Invoke-RestMethod -Method get -Uri $url -Headers @{"Authorization"="Bearer $token"}

        foreach($c in $coll)
        {
            ExportObject $type $c $c.name;
        }
    }
}

function ExportObject($type, $obj, $id)
{
    New-Item -path "$exportPath\$type" -ItemType Directory -ea SilentlyContinue;

    $json = ConvertTo-Json $obj -Depth 20;

    remove-item "$exportPath/$type/$($id).json" -ea SilentlyContinue;

    add-content "$exportPath/$type/$($id).json" $json;
}

function GetToken($res, $tokenType, $refresh)
{
    $curToken = get-content "$exportPath\token-$($tokenType).json" -Raw -ea SilentlyContinue;

    if ($curToken)
    {
        $item = ConvertFrom-Json $curToken -ea SilentlyContinue;
    }

    if (!$item -or $item.ExpiresOn -lt [datetime]::utcNow -or $refresh)
    {
        #login
        $context = Get-AzContext;
        $global:loginDomain = $context.Tenant.Id;

        $clientId = "1950a258-227b-4e31-a9cf-717495945fc2";
        $item = Get-AzAccessToken -ResourceUrl $res;

        remove-item "$exportPath\token-$($tokenType).json" -ea SilentlyContinue;

        Add-Content "$exportPath\token-$($tokenType).json" $(ConvertTo-Json $item);
    }
    
    return $item.token;
}

function ImportObjects($path)
{
    $global:headers = @{
        Authorization="Bearer $token"
        "Content-Type"="application/json"
    }

    $global:mgmtheaders = @{
        Authorization="Bearer $mgmttoken"
        "Content-Type"="application/json"
    }

    write-host "Importing classification rules"
    ImportClassificationRules;

    write-host "Importing collections"
    ImportCollections;

    write-host "Importing Rule sets"
    ImportRuleSets;

    write-host "Importing key vaults"
    ImportKeyVaultConnections;

    write-host "Importing metadata policy"
    ImportMetadataPolicy;

    write-host "Importing types"
    #ImportTypes;

    write-host "Importing resource sets"
    ImportResourceSets;

    write-host "Importing data sources"
    ImportDataSources;

    write-host "Importing glossaries"
    ImportGlossaries;

    write-host "Importing SHIR"
    ImportSHIR;

    write-host "Importing ADF"
    ImportADF;
}

function ImportClassificationRules
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/classificationrules");

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        $json = ConvertFrom-Json $body;

        $url = "$rootUrl/scan/classificationrules/$($json.Name)?api-version=2022-02-01-preview";
        
        if (!$json.name.startswith("MICROSOFT."))
        {
            $data = Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body;
        }

    }
}

function GetRootCollection()
{
    #get the current root collection...
    $url = "$rootUrl/account/collections/?api-version=2019-11-01-preview";

    $data = Invoke-RestMethod -Method GET -Uri $url -Headers $headers;

    foreach($item in $data.value)
    {
        if (!$item.parentCollection)
        {
            $parentCollection = $item;
        }
    }

    return $parentCollection;
}

function ImportCollections
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/collection");

    $parentCollection = GetRootCollection;

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        $json = ConvertFrom-Json $body;

        #skip creating the root collection
        if ($json.parentcollection)
        {
            $oldRootCollection = $json.parentCollection.referenceName;

            #replace the root collection
            #send the collection to be created...
            $body = $body.replace("$oldRootCollection",$parentCollection.name);
            $body = $body.replace($oldRootCollection.toLower(),$parentCollection.name);

            $json = ConvertFrom-Json $body;

            $url = "$rootUrl/account/collections/$($json.Name)?api-version=2019-11-01-preview";

            $data = Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body;
        }
        else
        {
            $oldRootCollection = $json.name;
        }
    }

    #import any root collection admins
    ImportRootCollectionAdmins;
}

function GetOldRootCollection()
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/collection");

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        $json = ConvertFrom-Json $body;

        #skip creating the root collection
        if (!$json.parentcollection)
        {
            $oldRootCollection = $json;
        }
    }

    return $oldRootCollection;
}

function ImportRuleSets
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/ruleset");

    #get the current root collection...
    $url = "$rootUrl/scan/scanrulesets/?api-version=2022-02-01-preview";

    $data = Invoke-RestMethod -Method GET -Uri $url -Headers $headers;

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        $json = ConvertFrom-Json $body;

        $files = @{};

        $vals = $json.properties.scanningRule.fileExtensions.split(" ");

        $json.properties.scanningRule.fileExtensions = $vals;

        $url = "$rootUrl/scan/scanrulesets/$($json.Name)?api-version=2022-02-01-preview";

        $data = Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body;

    }
}

function ImportCredentials
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/credential");

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        $json = ConvertFrom-Json $body;

        $url = "$rootUrl/scan/credentials/$($json.Name)?api-version=2022-02-01-preview";

        $data = Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body;

    }
}

function ImportKeyVaultConnections
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/keyvaultconnection");

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        $json = ConvertFrom-Json $body;

        $url = "$rootUrl/scan/azureKeyVaults/$($json.Name)?api-version=2022-02-01-preview";

        $data = Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body -ea SilentlyContinue;

    }

    ImportCredentials;
}

function ImportMetadataPolicy
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/metadatapolicy");

    $policies = ExportMetadataPolicy;

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        
        $json = ConvertFrom-Json $body;

        #get the current collection policies

        $url = "$rootUrl/policyStore/metadataPolicies/$($json.id)?api-version=2021-07-01-preview";
        
        $data = Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body -ea SilentlyContinue;

        #for each policy, ensure that the root collection admin has been added..
        foreach($ar in $json.properties.attributeRules)
        {
            if ($ar.dnfCondition.name.contains("purviewmetadatarole_builtin_collection-administrator"))
            {
                
            }
        }
    }
}

function ImportTypes
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/typedefs");

    foreach($item in $items)
    {
        write-host "importing $item"

        $body = get-content $item -raw;
        
        $json = ConvertFrom-Json $body;

        $url = "$rootUrl/catalog/api/atlas/v2/types/typedefs";
        
        $data = Invoke-RestMethod -Method POST -Uri $url -Headers $headers -Body $body;
    }
}

function ImportResourceSets
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/resourceset");

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        
        $json = ConvertFrom-Json $body;

        $url = "$rootUrl/resourceSetRuleConfigs/defaultResourceSetRuleConfig?api-version=2019-11-01-preview";
        
        $data = Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body;
    }
}

function ImportDataSources
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/datasource");

    $oldRootCollection = GetOldRootCollection;

    $parentColleciton = GetRootCollection;

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        
        $json = ConvertFrom-Json $body;

        if ($json.properties.collection.referenceName -eq $oldRootCollection.Name)
        {
            $json.properties.collection.referenceName = $parentColleciton.name;
        }

        $body = ConvertTo-json $json -Depth 10;

        $url = "$rootUrl/scan/datasources/$($json.name)?api-version=2022-02-01-preview";
        
        $data = Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body;
    }
}

function ImportGlossaries
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/glossary");

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        
        $json = ConvertFrom-Json $body;

        $url = "$rootUrl/catalog/api/atlas/v2/glossary";
        
        $data = Invoke-RestMethod -Method POST -Uri $url -Headers $headers -Body $body;

        ImportGlossaryTerms $data;
    }
}

function ImportGlossaryTerms($item)
{
    if ($item)
    {
        $type = "glossaryterms";

        $body = get-content "$exportPath/glossaryterms/$($item.id)" -raw;

        if ($body)
        {
            $url = "$rootUrl/catalog/api/v2/glossary/$($item.id)/terms/import?api-version=2022-03-01-preview";

            $coll = Invoke-RestMethod -Method POST -Uri $url -Headers @{"Authorization"="Bearer $token"} -body $body
        }
    }
}

function ImportSHIR
{
    $items = [System.Io.Directory]::GetFiles("$exportPath/runtimes");

    foreach($item in $items)
    {
        $body = get-content $item -raw;
        
        $json = ConvertFrom-Json $body;

        $post = @{};
        $post.name = $json.name;
        $post.properties = @{};
        $post.properties.type = $json.properties.type;

        $url = "$rootUrl/proxy/integrationRuntimes/$($json.name)?api-version=2020-12-01-preview"

        $coll = Invoke-RestMethod -Method put -Uri $url -Headers $headers -body $(ConvertTo-Json $post);
    }
}

function ImportADF
{
    $account = GetAccount $subscriptionId $resourceGroupName $purviewName;

    $items = [System.Io.Directory]::GetFiles("$exportPath/adf");

    foreach($item in $items)
    {
        $body = get-content $item -raw;

        $json = ConvertFrom-Json $body;

        $datafactoryname = $json.name;

        $datafactoryResourceGroupName = ParseValue $body "resourceGroups/" "/";

        ImportADF_DoWork $datafactoryResourceGroupName $datafactoryname;
    }

    #import the one from the deployment...
    ImportADF_DoWork $resourceGroupName "main$suffix";
}

function ImportADF_DoWork($resourceGroupName, $datafactoryname)
{
    $resourcePath = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.DataFactory/factories/$datafactoryname";
    
    $url = "https://management.azure.com/$($resourcePath)?api-version=2018-06-01";

    $post = @{};
    $post.id = $resourcePath;
    $post.tags = @{};
    $post.tags.catalogUri = "https://$purviewName.purview.azure.com/catalog";
    $post.properties = @{};
    $post.properties.purviewConfiguration = @{};
    $post.properties.purviewConfiguration.pruviewResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Purview/accounts/$purviewName";

    $data = Invoke-RestMethod -Method PATCH -Uri $url -Headers $mgmtheaders -Body $(ConvertTo-Json $post);

}

function ImportRootCollectionAdmins()
{
    #get each admin in the metadata policy..
    $items = [System.Io.Directory]::GetFiles("$exportPath/metadatapolicy");

    $oldRootCollection = GetOldRootCollection;

    foreach($item in $items)
    {
        $body = get-content $item -raw;

        $json = ConvertFrom-Json $body;

        if ($json.name.tolower() -eq "policy_$($oldRootCollection.name.tolower())")
        {
            foreach($ar in $json.properties.attributeRules)
            {
                if ($ar.name.contains("purviewmetadatarole_builtin_collection-administrator"))
                {
                    foreach($cond in $ar.dnfCondition[0])
                    {
                        if ($cond.attributeName -eq "principal.microsoft.id")
                        {
                            foreach($id in $cond.attributeValueIncludedIn)
                            {
                                AddRootCollectionAdmin $id        
                            }
                        }
                    }
                }
            }
            
        }
    }
}

#unless this works via import of metadatapolicy?
function AddRootCollectionAdmin($objectId)
{
    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Purview/accounts/$purviewName/addRootCollectionAdmin?api-version=2021-12-01"

    $post = @{};
    $post.objectid = $objectId;

    $data = Invoke-RestMethod -Method POST -Uri $url -Headers $mgmtheaders  -Body $(ConvertTo-Json $post);
}

function GetSuffix()
{
    $suffix = get-content "$labPath\purviewsuffix.txt" -ea SilentlyContinue;

    if (!$suffix)
    {
        $suffix = -join ((65..90) + (97..122) | Get-Random -Count 5 | % {[char]$_});

        add-content "$labPath\purviewsuffix.txt" $suffix;
    }

    return $suffix.tolower();
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

    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.DataFactory/factories/${"main$suffix"}/linkedservices/$($name)?api-version=2018-06-01";
    
    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $item -Headers @{ Authorization="Bearer $mgmtToken" } -ContentType "application/json"
    
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

    $itemTemplate = Get-Content -Path "$($TemplatesPath)/blob_storage_linked_service.json"
    $item = $itemTemplate.Replace("#LINKED_SERVICE_NAME#", $Name).Replace("#STORAGE_ACCOUNT_NAME#", $Name).Replace("#STORAGE_ACCOUNT_KEY#", $Key)

    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.DataFactory/factories/$workspaceName/linkedservices/$($name)?api-version=2018-06-01";
    
    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $item -Headers @{ Authorization="Bearer $mgmtToken" } -ContentType "application/json"
    
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
    $FileName,

    [parameter(Mandatory=$true)]
    [String]
    $TemplateFileName,

    [parameter(Mandatory=$true)]
    [String]
    $Name,

    [parameter(Mandatory=$true)]
    [String]
    $LinkedServiceName
    )

    $itemTemplate = Get-Content -Path "$($DatasetsPath)/$($TemplateFileName).json"
    $item = $itemTemplate.Replace("#LINKED_SERVICE_NAME#", $LinkedServiceName).Replace("#FILE_NAME#", $filename).Replace("#DATASET_NAME#", $name)
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.DataFactory/factories/$workspaceName/datasets/$($Name)?api-version=2018-06-01"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $item -Headers @{ Authorization="Bearer $mgmtToken" } -ContentType "application/json"
    
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

    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.DataFactory/factories/$workspaceName/pipelines/$($Name)?api-version=2018-06-01"

    $result = Invoke-RestMethod  -Uri $uri -Method PUT -Body $item -Headers @{ Authorization="Bearer $mgmtToken" } -ContentType "application/json"
    
    return $result
}

function ParseValue($line, $startToken, $endToken)
{
    if ($startToken -eq $null)
    {
        return "";
    }

    if ($startToken -eq "")
    {
        return $line.substring(0, $line.indexof($endtoken));
    }
    else
    {
        try
        {
            $rtn = $line.substring($line.indexof($starttoken));
            return $rtn.substring($startToken.length, $rtn.indexof($endToken, $startToken.length) - $startToken.length).replace("`n","").replace("`t","");
        }
        catch [System.Exception]
        {
            $message = "Could not find $starttoken"
            #write-host $message -ForegroundColor Yellow
        }
    }

}