$ResourceGroup = "MyResourceGroup"
$NicName = "MyNic"
$action = "Add" # or "Remove"


function Set-NicIpConfigurations {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Add','Remove')]
        [string]  $Action,

        [Parameter(Mandatory = $true)]
        [string[]]$IpAddresses,

        [Parameter(Mandatory = $true)]
        [string]  $NicName,

        [Parameter(Mandatory = $true)]
        [string]  $ResourceGroup
    )

    foreach ($ip in $IpAddresses) {
        $nic = Get-AzNetworkInterface -Name $NicName -ResourceGroupName $ResourceGroup

        if ($Action -eq 'Add') {
            if ($nic.IpConfigurations.PrivateIpAddress -contains $ip) {
                Write-Verbose "$ip already present on $NicName – skipping."
                continue
            }

            $ipConfigName = "$ip-nic"
            $subnet       = $nic.IpConfigurations[0].Subnet

            $nic | Add-AzNetworkInterfaceIpConfig `
                    -Name                 $ipConfigName `
                    -Subnet               $subnet `
                    -PrivateIpAddress     $ip `
                    -PrivateIpAddressVersion 'IPv4'  |
                  Set-AzNetworkInterface

            Write-Host "Added $ip to $NicName."
        }
        else { # Remove
            $ipConfig = $nic.IpConfigurations |
                        Where-Object { $_.PrivateIpAddress -eq $ip }

            if (-not $ipConfig) {
                Write-Verbose "$ip not found on $NicName – skipping."
                continue
            }

            if ($ipConfig.Primary) {
                Write-Warning "Cannot remove primary IP configuration ($ip)."
                continue
            }

            $nic | Remove-AzNetworkInterfaceIpConfig -Name $ipConfig.Name |
                  Set-AzNetworkInterface

            Write-Host "Removed $ip from $NicName."
        }
    }

    # Post-operation verification
    $nic       = Get-AzNetworkInterface -Name $NicName -ResourceGroupName $ResourceGroup
    $actualIps = $nic.IpConfigurations | Select-Object -ExpandProperty PrivateIpAddress

    if ($Action -eq 'Add') {
        $missing = $IpAddresses | Where-Object { $_ -notin $actualIps }
        if ($missing) {
            Write-Error "Missing IPs on ${NicName}: $($missing -join ', ')"
        } else {
            Write-Host "All IP addresses were successfully added to $NicName."
        }
    }
    else {
        $stillPresent = $IpAddresses | Where-Object { $_ -in $actualIps }
        if ($stillPresent) {
            Write-Error "Failed to remove IPs from ${NicName}: $($stillPresent -join ', ')"
        } else {
            Write-Host "All specified IP addresses were successfully removed from $NicName."
        }
    }
}

# Verify that all requested IPs are now configured on the NIC
function Test-NicIpConfigurations {
    param(
        [string[]]$ExpectedIpAddresses,
        [string]  $NicName,
        [string]  $ResourceGroup
    )

    $nic       = Get-AzNetworkInterface -Name $NicName -ResourceGroupName $ResourceGroup
    $actualIps = $nic.IpConfigurations | Select-Object -ExpandProperty PrivateIpAddress

    $missing = $ExpectedIpAddresses | Where-Object { $_ -notin $actualIps }
    if ($missing) {
        Write-Error "Missing IPs on ${NicName}: $($missing -join ', ')"
    } else {
        Write-Host "All IP addresses were successfully configured on $NicName."
    }
}


# Example usage
$ipAddresses = @('10.0.0.10', '10.0.0.11', '10.0.0.12', '10.0.0.13', '10.0.0.14', '10.0.0.15', '10.0.0.16')
Set-NicIpConfigurations -IpAddresses $ipAddresses -NicName $NicName -ResourceGroup $ResourceGroup -Action $action
# This script will remove multiple IP configurations from the specified NIC in the specified resource group.
