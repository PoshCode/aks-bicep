# RBAC Resource Role Assignments `[Resources/resourceRoleAssignment]`

This tricky deployment uses an ARM json nested deployment to work around a "scope" requirement in Bicep role assignments,
so we have one resourceRoleAssignment template that works for any resources.

- Supports RBAC for anything
- Supports intellisense for role name

You can update the list of roles by running:

```PowerShell
# Always run in RPRD
$Context = Set-AzContext -Subscription "9168b710-d295-4760-af83-b15a0d16c205"
Write-Warning "AzContext set to $($Context.Name)"

$AllRoles = [System.Collections.Generic.SortedDictionary[string, string]]::new()
Get-AzRoleDefinition | ForEach-Object { $AllRoles.Add($_.Name, $_.Id) }
$AllRoles | ConvertTo-Json -Compress | Set-Content $PSScriptRoot\roles.jsonc
Write-Host "Updated $PSScriptRoot\roles.jsonc with $($AllRoles.Count) roles"
"@allowed([
'$($AllRoles.Keys -join "'`n'")'
])" | Set-Clipboard

Write-Host "Roles added to clipboard for pasting to bicep as @allowed() attribute"
```

