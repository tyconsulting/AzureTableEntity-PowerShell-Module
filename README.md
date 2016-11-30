# AzureTableEntity PowerShell Module
##Description
This repository contains the source code of the AzureTableEntity PowerShell module. AzureTableEntity PS module provides functions for Azure table entity CRUD (Create, Read, Update, Delete) operations using the Azure Storage REST API.

##Install Instruction
###Install from PowerShell Gallery
Install-module AzureTableEntity

###Manually Install
Download this module from github, and place the AzureTableEntity module folder to 'C:\Program Files\WindowsPowerShell\Modules'

###Download from PowerShell Gallery
Find-Module AzureTableEntity | Save-Module -Force -Path 'C:\Temp'

##PowerShell functions
###Get-AzureTableEntity
Search Azure Table entities by specifying a search string.

Use Get-Help Get-AzureTableEntity -Full to access the help file for this function.

###New-AzureTableEntity
Insert one or more entities to Azure table storage.

Use Get-Help New-AzureTableEntity -Full to access the help file for this function.

###Update-AzureTableEntity
Update one or more entities to Azure table storage.

Use Get-Help Update-AzureTableEntity -Full to access the help file for this function.

###Remove-AzureTableEntity
Remove one or more entities to Azure table storage.

Use Get-Help Remove-AzureTableEntity -Full to access the help file for this function.

##Additional information:

###PowerShell Gallery:
https://www.powershellgallery.com/packages/AzureTableEntity

###Sample code on GitHub Gist:
https://gist.github.com/tyconsulting/1ff706181d8e476528c86b8f7ac8af23

###AzureTableEntity PowerShell module Blog Post:
http://blog.tyang.org/2016/11/30/powershell-module-for-managing-azure-table-storage-entities

###Azure Table REST API official documentation:
https://docs.microsoft.com/en-us/rest/api/storageservices/fileservices/table-service-rest-api

### Developer:
Developed by Tao Yang (TY Consulting Pty. Ltd.)
November, 2016
