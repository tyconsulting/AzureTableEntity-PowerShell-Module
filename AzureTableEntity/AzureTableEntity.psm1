Function Get-ODataType
{
  Param (
    [Parameter(ParameterSetName='ByType', Mandatory = $true)][ValidateNotNullOrEmpty()][System.Reflection.TypeInfo]$PSType,
    [Parameter(ParameterSetName='ByTypeFullName', Mandatory = $true)][ValidateNotNullOrEmpty()][String]$TypeFullName
  )
  If ($PSType)
  {
    $TypeFullName = $PSType.FullName
  }
  Switch ($TypeFullName)
  {
    "System.DateTime" {$ODataType = "Edm.DateTime"}
    "System.Boolean" {$ODataType = "Edm.Boolean"}
    "System.Double" {$ODataType = "Edm.Double"}
    "System.Int32" {$ODataType = "Edm.Int32"}
    "System.Guid" {$ODataType = "Edm.Guid"}
    "System.String" {$ODataType = "Edm.String"}
    "System.DateTimeOffset" {$ODataType = "Edm.DateTimeOffset"}
    "System.Byte" {$ODataType = "Edm.Byte"}
    default {$ODataType = $null}
  }
  $ODataType
}
Function New-SharedKeyLiteAuthorizationHeader
{
  Param (
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify an access key for the Azure Storage account')][ValidateNotNullOrEmpty()][String]$StorageAccountAccessKey,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the relative URL path of the Azure storage REST API call')][ValidateNotNullOrEmpty()][string]$UrlPath,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify formatted UTC time stamp in RFC1123 format')][ValidateNotNullOrEmpty()][String]$TimeStamp
  )

  #build authorization string
  Write-Verbose "Start building authorization string"
  [Byte[]]$StorageAccountAccessKeyByteArray = [System.Convert]::FromBase64String($StorageAccountAccessKey)
  $hasher = New-Object System.Security.Cryptography.HMACSHA256
  $hasher.key = $StorageAccountAccessKeyByteArray
  $strToSign = $RFC1123TimeUTC + "`n" + "/" + $StorageAccountName + "/" + $UrlPath

  $AuthKey = [System.Convert]::ToBase64String($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($strToSign)))
  $SharedKeyLiteAuthorizationHeader = "SharedKeyLite $StorageAccountName`:$AuthKey"
  $SharedKeyLiteAuthorizationHeader
}

Function New-BatchInsertRequestJSONBody
{
  Param (
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the relative URL path of the Azure storage REST API call')][ValidateNotNullOrEmpty()][string]$UrlPath,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the batch name')][ValidateScript({$_ -cmatch '^batch_'})][String]$BatchName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table entities')][ValidateScript({$_.count -le 100})][psobject[]]$Entities
  )
  $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/$UrlPath"
  $ChangeSetName = "changeset_$([Guid]::NewGuid().Tostring())"
  $RequestBody = @"
--$BatchName
Content-Type: multipart/mixed; boundary=$ChangeSetName

"@

  $IndividualEntityTemplate = @'
--{0}
Content-Type: application/http
Content-Transfer-Encoding: binary

POST {1} HTTP/1.1
Content-Type: application/json
Accept: application/json;odata=minimalmetadata
Prefer: return-no-content
DataServiceVersion: 1.0;

{2}
'@

  Foreach ($item in $Entities)
  {
    $JsonPayload = ConvertTo-Json -InputObject $item
    #$JsonPayload = $JsonPayload -replace "\/", "\\/"
    $EntityRequestBody = [String]::Format($IndividualEntityTemplate, $ChangeSetName, $TableStorageUri, $JsonPayload)
    $RequestBody = @"
$Requestbody
$EntityRequestBody
"@
  }

$RequestBody = @"
$Requestbody

--$ChangeSetName--
--$BatchName--
"@
$Requestbody
}

Function New-BatchUpdateRequestJSONBody
{
  Param (
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the relative URL path of the Azure storage REST API call')][ValidateNotNullOrEmpty()][string]$UrlPath,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the batch name')][ValidateScript({$_ -cmatch '^batch_'})][String]$BatchName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table entities')][ValidateScript({$_.count -le 100})][psobject[]]$Entities
  )
  $TableStorageBaseUri = "https://$StorageAccountName.table.core.windows.net/$UrlPath"
  $ChangeSetName = "changeset_$([Guid]::NewGuid().Tostring())"
  $RequestBody = @"
--$BatchName
Content-Type: multipart/mixed; boundary=$ChangeSetName

"@

  $IndividualEntityTemplate = @'
--{0}
Content-Type: application/http
Content-Transfer-Encoding: binary

PUT {1} HTTP/1.1
Content-Type: application/json
Accept: application/json;odata=minimalmetadata
If-Match: *
DataServiceVersion: 1.0;

{2}
'@

  Foreach ($item in $Entities)
  {
    $JsonPayload = ConvertTo-Json -InputObject $item -Compress
    If ($item.PartitionKey -eq $null -or $item.RowKey -eq $null)
    {
      Throw "The Partition Key and/or the Row Key is not defined in the entity '$JsonPayload' to be updated."
      Exit -1
    }
    $TableStorageUri = "$TableStorageBaseUri(PartitionKey='$($item.PartitionKey)',RowKey='$($item.RowKey)')"
    $EntityRequestBody = [String]::Format($IndividualEntityTemplate, $ChangeSetName, $TableStorageUri, $JsonPayload)
    $RequestBody = @"
$Requestbody
$EntityRequestBody
"@
  }

$RequestBody = @"
$Requestbody

--$ChangeSetName--
--$BatchName--
"@
$Requestbody
}

Function New-BatchMergeRequestJSONBody
{
  Param (
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the relative URL path of the Azure storage REST API call')][ValidateNotNullOrEmpty()][string]$UrlPath,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the batch name')][ValidateScript({$_ -cmatch '^batch_'})][String]$BatchName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table entities')][ValidateScript({$_.count -le 100})][psobject[]]$Entities
  )
  $TableStorageBaseUri = "https://$StorageAccountName.table.core.windows.net/$UrlPath"
  $ChangeSetName = "changeset_$([Guid]::NewGuid().Tostring())"
  $RequestBody = @"
--$BatchName
Content-Type: multipart/mixed; boundary=$ChangeSetName

"@

  $IndividualEntityTemplate = @'
--{0}
Content-Type: application/http
Content-Transfer-Encoding: binary

MERGE {1} HTTP/1.1
Content-Type: application/json
Accept: application/json;odata=minimalmetadata
DataServiceVersion: 3.0;

{2}
'@

  Foreach ($item in $Entities)
  {
    $JsonPayload = ConvertTo-Json -InputObject $item -Compress
    If ($item.PartitionKey -eq $null -or $item.RowKey -eq $null)
    {
      Throw "The Partition Key and/or the Row Key is not defined in the entity '$JsonPayload' to be updated."
      Exit -1
    }
    $TableStorageUri = "$TableStorageBaseUri(PartitionKey='$($item.PartitionKey)',RowKey='$($item.RowKey)')"
    $EntityRequestBody = [String]::Format($IndividualEntityTemplate, $ChangeSetName, $TableStorageUri, $JsonPayload)
    $RequestBody = @"
$Requestbody
$EntityRequestBody
"@
  }

$RequestBody = @"
$Requestbody

--$ChangeSetName--
--$BatchName--
"@
$Requestbody
}
Function New-BatchRemoveRequestJSONBody
{
  Param (
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the relative URL path of the Azure storage REST API call')][ValidateNotNullOrEmpty()][string]$UrlPath,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the batch name')][ValidateScript({$_ -cmatch '^batch_'})][String]$BatchName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table entities')][ValidateScript({$_.count -le 100})][psobject[]]$Entities
  )
  $TableStorageBaseUri = "https://$StorageAccountName.table.core.windows.net/$UrlPath"
  $ChangeSetName = "changeset_$([Guid]::NewGuid().Tostring())"
  $RequestBody = @"
--$BatchName
Content-Type: multipart/mixed; boundary=$ChangeSetName

"@

  $IndividualEntityTemplate = @'
--{0}
Content-Type: application/http
Content-Transfer-Encoding: binary

DELETE {1} HTTP/1.1
Content-Type: application/json
Accept: application/json;odata=minimalmetadata
If-Match: *
DataServiceVersion: 1.0;

'@

  Foreach ($item in $Entities)
  {
    If ($item.PartitionKey -eq $null -or $item.RowKey -eq $null)
    {
      Throw "The Partition Key and/or the Row Key is not defined in the entity '$JsonPayload' to be updated."
      Exit -1
    }
    $TableStorageUri = "$TableStorageBaseUri(PartitionKey='$($item.PartitionKey)',RowKey='$($item.RowKey)')"
    $EntityRequestBody = [String]::Format($IndividualEntityTemplate, $ChangeSetName, $TableStorageUri)
    $RequestBody = @"
$Requestbody
$EntityRequestBody
"@
  }

$RequestBody = @"
$Requestbody

--$ChangeSetName--
--$BatchName--
"@
$Requestbody
}

# .EXTERNALHELP AzureTableEntity.psm1-Help.xml
Function New-AzureTableEntity
{
  Param (
    [Parameter(ParameterSetName = 'AAConnection',Mandatory = $true,HelpMessage = 'Please specify the AzureTable Azure Autoamtion connection object')][Object]$TableConnection,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify an access key for the Azure Storage account')][ValidateNotNullOrEmpty()][String]$StorageAccountAccessKey,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Table name')][ValidateNotNullOrEmpty()][string]$TableName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table entities')][ValidateScript({$_.count -le 100})][psobject[]]$Entities
  )
  If($TableConnection)
  {
    $StorageAccountName = $TableConnection.StorageAccount
    $TableName = $TableConnection.TableName
    $StorageAccountAccessKey = $TableConnection.StorageAccountAccessKey
  }
  $RFC1123TimeUTC  = [datetime]::UtcNow.ToString("R")
  Write-Verbose "Time stamp for authorization header signature: '$RFC1123TimeUTC'"
  $RequestHeaders = @{
    'x-ms-version' = '2015-04-05'
    'x-ms-date' = $RFC1123TimeUTC
    'Accept-Charset' = 'UTF-8'
    'DataServiceVersion' = '1.0;NetFx'
    'MaxDataServiceVersion' = '3.0;NetFx'
  }

  If ($Entities.count -eq 1)
  {
    $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/$TableName"
    Write-Verbose "Inserting a single entity. Table Storage URL: '$TableStorageUri'."
    $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath $TableName -TimeStamp $RFC1123TimeUTC
    $RequestHeaders.Add('Accept', 'application/json;odata=nometadata')
    $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
    $RequestBody = ConvertTo-Json -InputObject $Entities[0] -Depth 2
    $ContentType = "application/json"
    
  } else {
    $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath '$batch' -TimeStamp $RFC1123TimeUTC
    $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
    $RequestHeaders.Add('Prefer', 'return-no-content')
    $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/`$batch"
    $BatchName = "batch_$([guid]::NewGuid().tostring())"
    $ContentType = "multipart/mixed;boundary=$BatchName"

    $RequestBody = New-BatchInsertRequestJSONBody -StorageAccountName $StorageAccountName -UrlPath $TableName -BatchName $BatchName -Entities $Entities

  }
  $RequestHeaders.Add("Content-Length", $requestBody.Length)
  Write-Verbose "Request Content Length: $($requestBody.Length)"
  Write-Verbose "Request Body:"
  Write-Verbose $RequestBody
  #Write-Verbose "Request Headers:"
  Write-Verbose "Content Type: $ContentType"
  $InsertRequest = Invoke-WebRequest -UseBasicParsing -Uri $TableStorageUri -Method Post -Body $RequestBody -ContentType $ContentType -Headers $RequestHeaders
  $InsertRequest
}

# .EXTERNALHELP AzureTableEntity.psm1-Help.xml
Function Get-AzureTableEntity
{
  Param (
    [Parameter(ParameterSetName = 'AAConnection',Mandatory = $true,HelpMessage = 'Please specify the AzureTable Azure Autoamtion connection object')][Object]$TableConnection,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify an access key for the Azure Storage account')][ValidateNotNullOrEmpty()][String]$StorageAccountAccessKey,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Table name')][ValidateNotNullOrEmpty()][string]$TableName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table query string')][ValidateNotNullOrEmpty()][string]$QueryString,
    [Parameter(Mandatory = $false,HelpMessage = 'Please specify if datetime fields should be converted back')][ValidateNotNullOrEmpty()][boolean]$ConvertDateTimeFields = $false,
    [Parameter(Mandatory = $false,HelpMessage = 'Please specify if search should continue beyond 1000 results')][ValidateNotNullOrEmpty()][boolean]$GetAll = $true
  )
  If($TableConnection)
  {
    $StorageAccountName = $TableConnection.StorageAccount
    $TableName = $TableConnection.TableName
    $StorageAccountAccessKey = $TableConnection.StorageAccountAccessKey
  }

  $TableStorageBaseUri = "https://$StorageAccountName.table.core.windows.net/$TableName"
  $RFC1123TimeUTC  = [datetime]::UtcNow.ToString("R")
  #build authorization string
  $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath $TableName -TimeStamp $RFC1123TimeUTC
  $RequestHeaders = @{
    ‘x-ms-version’ = '2015-12-11'
    ‘x-ms-date’ = $RFC1123TimeUTC
    'Authorization' = $AuthorizationHeaderValue
    'Accept' = 'application/json;odata=nometadata'
    'Accept-Charset' = 'UTF-8'
    'DataServiceVersion' = '1.0;NetFx'
    'MaxDataServiceVersion' = '3.0;NetFx'
  }
  if ($ConvertDateTimeFields -eq $true)
  {
    $RequestHeaders.Accept = 'application/json;odata=minimalmetadata'
  }
  $TableStorageSearchUri = "$TableStorageBaseUri`?`$filter=$QueryString"
  Write-Verbose "Table Storage search Uri: '$TableStorageSearchUri'"
  $SearchRequest = Invoke-WebRequest -UseBasicParsing -Uri $TableStorageSearchUri -Method Get -ContentType "application/json" -Headers $RequestHeaders
  $ReturnedEntities = ($SearchRequest.Content | ConvertFrom-JSON).value
  If ($GetAll -eq $true)
  {
    Do 
    {
      If ($SearchRequest.Headers.ContainsKey("x-ms-continuation-NextRowKey") -or $SearchRequest.Headers.ContainsKey("x-ms-continuation-NextPartitionKey"))
      {
        #Continue searching
        Write-Verbose "Query did not return all entities. Continue Querying."
        $SubsequentTableStorageSearchUri ="$TableStorageSearchUri`&NextPartitionKey=$($SearchRequest.Headers."x-ms-continuation-NextPartitionKey")&NextRowKey=$($SearchRequest.Headers."x-ms-continuation-NextRowKey")"
        Write-Verbose "Starting a subsequent query: '$SubsequentTableStorageSearchUri'"
        $SearchRequest = Invoke-WebRequest -UseBasicParsing -Uri $SubsequentTableStorageSearchUri -Method Get -ContentType "application/json" -Headers $RequestHeaders
        $ReturnedEntities += ($SearchRequest.Content | ConvertFrom-JSON).value
        If ($SearchRequest.Headers.ContainsKey("x-ms-continuation-NextRowKey") -or $SearchRequest.Headers.ContainsKey("x-ms-continuation-NextPartitionKey"))
        {
          $finished = $false
        } else {
          $finished = $true
        }
      } else {
        $finished = $true
      }
    } Until ($finished -eq $true)
    Write-Verbose "All entity retrieved. Total number of entities: $($ReturnedEntities.Count)"
  } else {
    If ($SearchRequest.Headers.ContainsKey("x-ms-continuation-NextRowKey") -or $SearchRequest.Headers.ContainsKey("x-ms-continuation-NextPartitionKey"))
    {
      Write-Warning "Not all search results are returned. The search query only returned $($ReturnedEntities.count) entities. In order to return all search results, please set -GetAll parameter to `$true."
    }
  }
  

  If ($ConvertDateTimeFields)
  {
    #Convert Datetime fields from string back to datetime type
    foreach ($item in $ReturnedEntities)
    {
      #remove odata.etag
      $item.psobject.Properties.Remove('odata.etag')
      #Convert the built-in timestamp field
      $item.Timestamp = [datetime]::Parse($item.Timestamp)
      Foreach ($property in $(Get-Member -InputObject $item -Name '*@odata.type' -MemberType NoteProperty))
      {
        $PropertyName = $property.Name
        if ($item.$PropertyName -ieq 'edm.datetime')
        {
          $ActualPropertyName = $PropertyName.split('@')[0]
          $item.$ActualPropertyName = [datetime]::Parse($item.$ActualPropertyName)
          $item.psobject.Properties.remove($PropertyName)
        }
      }
    }
  }
  $ReturnedEntities
}

# .EXTERNALHELP AzureTableEntity.psm1-Help.xml
Function Update-AzureTableEntity
{
  Param (
    [Parameter(ParameterSetName = 'AAConnection',Mandatory = $true,HelpMessage = 'Please specify the AzureTable Azure Autoamtion connection object')][Object]$TableConnection,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify an access key for the Azure Storage account')][ValidateNotNullOrEmpty()][String]$StorageAccountAccessKey,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Table name')][ValidateNotNullOrEmpty()][string]$TableName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table entities')][ValidateScript({$_.count -le 100})][psobject[]]$Entities
  )
  If($TableConnection)
  {
    $StorageAccountName = $TableConnection.StorageAccount
    $TableName = $TableConnection.TableName
    $StorageAccountAccessKey = $TableConnection.StorageAccountAccessKey
  }

  $RFC1123TimeUTC  = [datetime]::UtcNow.ToString("R")
  Write-Verbose "Time stamp for authorization header signature: '$RFC1123TimeUTC'"
  $RequestHeaders = @{
    'x-ms-version' = '2015-04-05'
    'x-ms-date' = $RFC1123TimeUTC
    'Accept-Charset' = 'UTF-8'
    'DataServiceVersion' = '1.0;NetFx'
    'MaxDataServiceVersion' = '3.0;NetFx'
  }

  If ($Entities.count -eq 1)
  {
    If ($Entities[0].PartitionKey -eq $null -or $Entities[0].RowKey -eq $null)
    {
      Throw "The Partition Key and/or the Row Key is not defined in the entity to be updated."
      Exit -1
    }
    $urlPath = "$TableName(PartitionKey='$($Entities[0].PartitionKey)',RowKey='$($Entities[0].RowKey)')"
    $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/$urlPath"
    Write-Verbose "Updating a single entity. Table Storage URL: '$TableStorageUri'."
    $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath $urlPath -TimeStamp $RFC1123TimeUTC
    $RequestHeaders.Add('Accept', 'application/json;odata=nometadata')
    $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
    $RequestHeaders.Add('If-Match', "*")
    $RequestBody = ConvertTo-Json -InputObject $Entities[0] -Depth 2
    $ContentType = "application/json"
    $HttpMethod = "Put"
    
  } else {
    $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath '$batch' -TimeStamp $RFC1123TimeUTC
    $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
    $RequestHeaders.Add('Prefer', 'return-no-content')
    $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/`$batch"
    $BatchName = "batch_$([guid]::NewGuid().tostring())"
    $ContentType = "multipart/mixed;boundary=$BatchName"

    $RequestBody = New-BatchUpdateRequestJSONBody -StorageAccountName $StorageAccountName -UrlPath $TableName -BatchName $BatchName -Entities $Entities
    $HttpMethod = "Post"
  }
  $RequestHeaders.Add("Content-Length", $requestBody.Length)
  Write-Verbose "Request Content Length: $($requestBody.Length)"
  Write-Verbose "Request Body:"
  Write-Verbose $RequestBody
  #Write-Verbose "Request Headers:"
  Write-Verbose "Content Type: $ContentType"
  $UpdateRequest = Invoke-WebRequest -UseBasicParsing -Uri $TableStorageUri -Method $HttpMethod -Body $RequestBody -ContentType $ContentType -Headers $RequestHeaders
  $UpdateRequest
}

# .EXTERNALHELP AzureTableEntity.psm1-Help.xml
Function Remove-AzureTableEntity
{
  Param (
    [Parameter(ParameterSetName = 'AAConnection',Mandatory = $true,HelpMessage = 'Please specify the AzureTable Azure Autoamtion connection object')][Object]$TableConnection,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify an access key for the Azure Storage account')][ValidateNotNullOrEmpty()][String]$StorageAccountAccessKey,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Table name')][ValidateNotNullOrEmpty()][string]$TableName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table entities')][ValidateScript({$_.count -le 100})][psobject[]]$Entities
  )
  If($TableConnection)
  {
    $StorageAccountName = $TableConnection.StorageAccount
    $TableName = $TableConnection.TableName
    $StorageAccountAccessKey = $TableConnection.StorageAccountAccessKey
  }

  $RFC1123TimeUTC  = [datetime]::UtcNow.ToString("R")
  Write-Verbose "Time stamp for authorization header signature: '$RFC1123TimeUTC'"
  $RequestHeaders = @{
    'x-ms-version' = '2015-04-05'
    'x-ms-date' = $RFC1123TimeUTC
    'Accept-Charset' = 'UTF-8'
    'DataServiceVersion' = '1.0;NetFx'
    'MaxDataServiceVersion' = '3.0;NetFx'
  }

  If ($Entities.count -eq 1)
  {
    If ($Entities[0].PartitionKey -eq $null -or $Entities[0].RowKey -eq $null)
    {
      Throw "The Partition Key and/or the Row Key is not defined in the entity to be removed."
      Exit -1
    }
    $urlPath = "$TableName(PartitionKey='$($Entities[0].PartitionKey)',RowKey='$($Entities[0].RowKey)')"
    $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/$urlPath"
    Write-Verbose "Updating a single entity. Table Storage URL: '$TableStorageUri'."
    $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath $urlPath -TimeStamp $RFC1123TimeUTC
    $RequestHeaders.Add('Accept', 'application/json;odata=nometadata')
    $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
    $RequestHeaders.Add('If-Match', "*")
    $ContentType = "application/json"
    $HttpMethod = "Delete"
    $RequestBody = $null
    
  } else {
    $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath '$batch' -TimeStamp $RFC1123TimeUTC
    $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
    $RequestHeaders.Add('Prefer', 'return-no-content')
    $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/`$batch"
    $BatchName = "batch_$([guid]::NewGuid().tostring())"
    $ContentType = "multipart/mixed;boundary=$BatchName"

    $RequestBody = New-BatchRemoveRequestJSONBody -StorageAccountName $StorageAccountName -UrlPath $TableName -BatchName $BatchName -Entities $Entities
    $RequestHeaders.Add("Content-Length", $requestBody.Length)
    Write-Verbose "Request Content Length: $($requestBody.Length)"
    Write-Verbose "Request Body:"
    Write-Verbose $RequestBody
    $HttpMethod = "Post"
  }
  $RemoveRequest = Invoke-WebRequest -UseBasicParsing -Uri $TableStorageUri -Method $HttpMethod -Body $RequestBody -ContentType $ContentType -Headers $RequestHeaders
  $RemoveRequest
}

# .EXTERNALHELP AzureTableEntity.psm1-Help.xml
Function Merge-AzureTableEntity
{
  Param (
    [Parameter(ParameterSetName = 'AAConnection',Mandatory = $true,HelpMessage = 'Please specify the AzureTable Azure Autoamtion connection object')][Object]$TableConnection,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify an access key for the Azure Storage account')][ValidateNotNullOrEmpty()][String]$StorageAccountAccessKey,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Table name')][ValidateNotNullOrEmpty()][string]$TableName,
    [Parameter(Mandatory = $true,HelpMessage = 'Please specify the Azure Table entities')][ValidateScript({$_.count -le 100})][psobject[]]$Entities
  )
  If($TableConnection)
  {
    $StorageAccountName = $TableConnection.StorageAccount
    $TableName = $TableConnection.TableName
    $StorageAccountAccessKey = $TableConnection.StorageAccountAccessKey
  }

  $RFC1123TimeUTC  = [datetime]::UtcNow.ToString("R")
  Write-Verbose "Time stamp for authorization header signature: '$RFC1123TimeUTC'"
  $RequestHeaders = @{
    'x-ms-version' = '2015-04-05'
    'x-ms-date' = $RFC1123TimeUTC
    'Accept-Charset' = 'UTF-8'
    'DataServiceVersion' = '1.0;NetFx'
    'MaxDataServiceVersion' = '3.0;NetFx'
  }

  If ($Entities.count -eq 1)
  {
    If ($Entities[0].PartitionKey -eq $null -or $Entities[0].RowKey -eq $null)
    {
      Throw "The Partition Key and/or the Row Key is not defined in the entity to be merged."
      Exit -1
    }
    $urlPath = "$TableName(PartitionKey='$($Entities[0].PartitionKey)',RowKey='$($Entities[0].RowKey)')"
    $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/$urlPath"
    Write-Verbose "Merging a single entity. Table Storage URL: '$TableStorageUri'."
    $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath $urlPath -TimeStamp $RFC1123TimeUTC
    $RequestHeaders.Add('Accept', 'application/json;odata=nometadata')
    $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
    $RequestHeaders.Add('If-Match', "*")
    $RequestBody = ConvertTo-Json -InputObject $Entities[0] -Depth 2
    $ContentType = "application/json"
    $HttpMethod = "Merge"
    
  } else {
    Write-Verbose "Merging a multiple entities. Table Storage URL: '$TableStorageUri'."
    $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath '$batch' -TimeStamp $RFC1123TimeUTC
    $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
    $RequestHeaders.Add('Prefer', 'return-no-content')
    $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/`$batch"
    $BatchName = "batch_$([guid]::NewGuid().tostring())"
    $ContentType = "multipart/mixed;boundary=$BatchName"

    $RequestBody = New-BatchMergeRequestJSONBody -StorageAccountName $StorageAccountName -UrlPath $TableName -BatchName $BatchName -Entities $Entities
    $HttpMethod = "Post"
  }
  $RequestHeaders.Add("Content-Length", $requestBody.Length)
  Write-Verbose "Request Content Length: $($requestBody.Length)"
  Write-Verbose "Request Body:"
  Write-Verbose $RequestBody
  #Write-Verbose "Request Headers:"
  Write-Verbose "Content Type: $ContentType"
  $UpdateRequest = Invoke-WebRequest -UseBasicParsing -Uri $TableStorageUri -Method $HttpMethod -Body $RequestBody -ContentType $ContentType -Headers $RequestHeaders
  $UpdateRequest
}

# .EXTERNALHELP AzureTableEntity.psm1-Help.xml
Function Test-AzureTableConnection
{
  Param (
    [Parameter(ParameterSetName = 'AAConnection',Mandatory = $true,HelpMessage = 'Please specify the AzureTable Azure Autoamtion connection object')][Object]$TableConnection,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Storage account name')][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify an access key for the Azure Storage account')][ValidateNotNullOrEmpty()][String]$StorageAccountAccessKey,
    [Parameter(ParameterSetName = 'IndividualParameter',Mandatory = $true,HelpMessage = 'Please specify the Azure Table name')][ValidateNotNullOrEmpty()][string]$TableName
  )
  If($TableConnection)
  {
    $StorageAccountName = $TableConnection.StorageAccount
    $TableName = $TableConnection.TableName
    $StorageAccountAccessKey = $TableConnection.StorageAccountAccessKey
  }

  $RFC1123TimeUTC  = [datetime]::UtcNow.ToString("R")
  Write-Verbose "Time stamp for authorization header signature: '$RFC1123TimeUTC'"
  $RequestHeaders = @{
    'x-ms-version' = '2015-04-05'
    'x-ms-date' = $RFC1123TimeUTC
    'DataServiceVersion' = '1.0;NetFx'
    'MaxDataServiceVersion' = '3.0;NetFx'
  }
  $urlPath = "Tables('$TableName')"
  $TableStorageUri = "https://$StorageAccountName.table.core.windows.net/$urlPath"
  $AuthorizationHeaderValue = New-SharedKeyLiteAuthorizationHeader -StorageAccountName $StorageAccountName -StorageAccountAccessKey $StorageAccountAccessKey -UrlPath $urlPath -TimeStamp $RFC1123TimeUTC
  $RequestHeaders.Add('Accept', 'application/json;odata=nometadata')
  $RequestHeaders.Add('Authorization', $AuthorizationHeaderValue)
  $ContentType = "application/json"
  $HttpMethod = "GET"
  Try {
    $GetTableRequest = Invoke-WebRequest -UseBasicParsing -Uri $TableStorageUri -Method $HttpMethod -ContentType $ContentType -Headers $RequestHeaders -ErrorAction Continue
    $TestResult = $false
    If ($GetTableRequest.StatusCode -ge 200 -and $GetTableRequest.StatusCode -le 299)
    {
      $RequestContent = ConvertFrom-Json -InputObject $GetTableRequest.Content
      If ($RequestContent.TableName -ieq $TableName)
      {
        $TestResult = $true
      }
    }
    $Status = $GetTableRequest.StatusDescription
    $Messages = $null
  } Catch {
    $TestResult = $false
    $FailureResponse = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($FailureResponse)
    $FailureResponseBody = $reader.ReadToEnd();
    $FailureResponseBody = ConvertFrom-Json -InputObject $FailureResponseBody
    $Status = $FailureResponseBody.'odata.error'.code
    $Messages =  $FailureResponseBody.'odata.error'.message.value
    Write-Verbose "Failed to get the table. HTTP Response code: $Status. Message: '$Messages'"
  }
  $ReturnObjProperties = @{
    Connected = $TestResult
    Status = $Status
    Messages = $Messages
  }
  $objReturn = new-object psobject -Property $ReturnObjProperties
  $objReturn
}