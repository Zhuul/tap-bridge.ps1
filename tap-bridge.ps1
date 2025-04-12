<#
 -------------------------------------------------------------------------
  tap-bridge.ps1
 -------------------------------------------------------------------------
  Copyright (c) 2024, Armand Delomenie
  Contact: adelomenie@yahoo.com
  GitHub : https://github.com/Zhuul

  ----------------------------------------------------------------------------
  MIT License
  ----------------------------------------------------------------------------
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  ----------------------------------------------------------------------------
  NOTE ABOUT OPTIONAL PAID SUPPORT
  ----------------------------------------------------------------------------
  Commercial or corporate users who wish to receive dedicated support, custom
  features, or other specific assistance may contact Armand Delomenie at
  the email above for paid support arrangements.

 -------------------------------------------------------------------------
#>
#!/usr/bin/env powershell
# ^ Not strictly needed on Windows, but just for clarity.

# Manually parse $args to handle double-dash arguments like --tap, --bridge, etc.
# We'll store them in variables: $action, $tap, $bridge, $external.

# ----------------------------------------------------
# 1) Parse Command Line Manually
# ----------------------------------------------------
$action   = $null
$tap      = $null
$bridge   = $null
$external = $null

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = $args[$i].ToLower()

    switch -Wildcard ($arg) {

        'help' {
            $action = 'help'
            continue
        }
        'install' {
            $action = 'install'
            continue
        }
        'uninstall' {
            $action = 'uninstall'
            continue
        }
        'add' {
            $action = 'add'
            continue
        }
        'remove' {
            $action = 'remove'
            continue
        }
        '--tap' {
            $i++
            if ($i -lt $args.Count) {
                $tap = $args[$i]
            } else {
                Write-Host "Error: Missing TAP name after '--tap'."
                return
            }
            continue
        }
        '--bridge' {
            $i++
            if ($i -lt $args.Count) {
                $bridge = $args[$i]
            } else {
                Write-Host "Error: Missing Bridge name after '--bridge'."
                return
            }
            continue
        }
        '--external' {
            $i++
            if ($i -lt $args.Count) {
                $external = $args[$i]
            } else {
                Write-Host "Error: Missing external NIC name after '--external'."
                return
            }
            continue
        }
        default {
            Write-Host "Warning: Unknown argument '$arg'."
        }
    }
}

# ----------------------------------------------------
# 2) Functions for TAP and Bridge
#    (No suffix logic, exactly named.)
# ----------------------------------------------------

function Download-TAPDrivers {
    Write-Host "Downloading latest TAP drivers from GitHub..."

    $latestUrl = "https://api.github.com/repos/OpenVPN/tap-windows6/releases/latest"
    $response  = Invoke-RestMethod -Uri $latestUrl -UseBasicParsing
    $asset = $response.assets | Where-Object { $_.name -like "*dist.win10.zip" } | Select-Object -First 1
    if (!$asset) {
        Write-Host "Failed to locate dist.win10.zip in the release assets."
        return $null
    }

    $downloadUrl = $asset.browser_download_url

    $tempDir = Join-Path $env:TEMP "tap-windows6"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    $zipFile = Join-Path $tempDir "dist.win10.zip"
    Write-Host "Downloading $downloadUrl ..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile

    $extractDir = Join-Path $tempDir "extracted"
    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force

    Write-Host "TAP drivers downloaded and extracted to: $extractDir"
    return $extractDir
}

function Install-TAP {
    param([Parameter(Mandatory=$true)][string]$TapName)

    $existing = Get-NetAdapter -Name $TapName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "TAP '$TapName' already exists, skipping driver install."
        return $existing
    }

    $extracted = Download-TAPDrivers
    if (!$extracted) { return $null }

    $infFile    = Get-ChildItem -Path $extracted -Recurse -Filter "OemVista.inf" | Select-Object -First 1
    $devconFile = Get-ChildItem -Path $extracted -Recurse -Filter "devcon.exe"   | Select-Object -First 1

    if (!$infFile -or !$devconFile) {
        Write-Host "Missing OemVista.inf or devcon.exe in $extracted"
        return $null
    }

    Write-Host "Installing TAP driver via devcon..."
    $installCmd = "install `"$($infFile.FullName)`" tap0901"
    $p = Start-Process -FilePath $devconFile.FullName -ArgumentList $installCmd -Wait -NoNewWindow -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Host "devcon.exe failed with exit code $($p.ExitCode)."
        return $null
    }

    Start-Sleep -Seconds 2
    $newTap = Get-NetAdapter | Where-Object {
        $_.InterfaceDescription -Like "*TAP-Windows Adapter V9*"
    } | Select-Object -First 1

    if (!$newTap) {
        Write-Host "TAP adapter not found after devcon install."
        return $null
    }

    Rename-NetAdapter -Name $newTap.Name -NewName $TapName
    Write-Host "Successfully installed TAP '$TapName'."

    # (Optionally set a random MAC if you want each TAP to have a unique LAA)
    # ... your existing code for random MAC here ...

    return (Get-NetAdapter -Name $TapName)
}

#
# UPDATED UNINSTALL THAT USES PNPUtil TO REMOVE THE DEVICE
#
function Uninstall-TAP {
    param([Parameter(Mandatory=$true)][string]$TapName)

    # 1) Confirm the adapter is visible by this name in Get-NetAdapter
    $adapter = Get-NetAdapter -Name $TapName -ErrorAction SilentlyContinue
    if (!$adapter) {
        Write-Host "TAP '$TapName' not found in Get-NetAdapter. Skipping."
        return
    }

    # The user calls it 'qemu-ubuntu', but the PnP device likely has a FriendlyName
    # like "TAP-Windows Adapter V9 #2".
    $realFriendlyName = $adapter.InterfaceDescription
    Write-Host "Removing TAP '$TapName' via pnputil (PnP FriendlyName='$realFriendlyName')..."

    # 2) Get the PnP device by that realFriendlyName (the interface description)
    $pnp = Get-PnpDevice -Class Net -FriendlyName $realFriendlyName -ErrorAction SilentlyContinue

    if (!$pnp) {
        # fallback: maybe the device is "TAP-Windows Adapter V9" or similar
        # and the #2 is not included in the FriendlyName. So let's do partial match:
        $pnp = Get-PnpDevice -Class Net | Where-Object {
            $_.FriendlyName -like "*$realFriendlyName*" -or
            $_.FriendlyName -like "*tap0901*"
        }
    }

    if (!$pnp) {
        Write-Host "PnP device not found for '$TapName' (friendlyName='$realFriendlyName'). Possibly already removed."
        return
    }

    $instanceId = $pnp.InstanceId
    Write-Host "Found device instance ID: $instanceId"

    # 3) Remove the device
    pnputil /remove-device "$instanceId"
    Start-Sleep -Seconds 2

    $stillThere = Get-NetAdapter -Name $TapName -ErrorAction SilentlyContinue
    if ($stillThere) {
        Write-Host "Warning: TAP '$TapName' still present, might need reboot."
    } else {
        Write-Host "TAP '$TapName' removed."
    }
}

function Create-Bridge {
    param(
        [Parameter(Mandatory=$true)][string]$BridgeName,
        [Parameter(Mandatory=$true)][string]$TapName,
        [string]$External
    )

    $tapAdapter = Get-NetAdapter -Name $TapName -ErrorAction SilentlyContinue
    if (!$tapAdapter) {
        Write-Host "Cannot create bridge: TAP '$TapName' not found."
        return
    }

    $extAdapter = $null
    if ($External) {
        $extAdapter = Get-NetAdapter -Name $External -ErrorAction SilentlyContinue
        if (!$extAdapter) {
            Write-Host "External NIC '$External' not found, aborting bridge creation."
            return
        }
    } else {
        $extAdapter = Get-NetAdapter | Where-Object {
            $_.Status -eq 'Up' -and
            $_.Name -ne $TapName -and
            $_.Name -notlike "*vEthernet*"
        } | Select-Object -First 1
        if (!$extAdapter) {
            Write-Host "No suitable external NIC found. Aborting."
            return
        }
    }

    Write-Host "Creating bridge '$BridgeName' with TAP '$TapName' + external NIC '$($extAdapter.Name)'..."

    $tapGuid = $tapAdapter.InterfaceGuid
    $extGuid = $extAdapter.InterfaceGuid
    Start-Process -FilePath "netsh" -ArgumentList "bridge create `"$tapGuid`" `"$extGuid`"" -Wait -NoNewWindow
    Start-Sleep -Seconds 2

    $bridgeAdapter = Get-NetAdapter | Where-Object { $_.Name -like "Network Bridge*" } | Select-Object -First 1
    if (!$bridgeAdapter) {
        Write-Host "Failed to find 'Network Bridge' after creation."
        return
    }
    Rename-NetAdapter -Name $bridgeAdapter.Name -NewName $BridgeName

    Enable-NetAdapter -Name $extAdapter.Name -Confirm:$false
    Start-Sleep -Seconds 1

    $bridgeGuid = (Get-NetAdapter -Name $BridgeName).InterfaceGuid
    Start-Process -FilePath "netsh" -ArgumentList "bridge add `"$extGuid`" to `"$bridgeGuid`"" -Wait -NoNewWindow
    Start-Sleep -Seconds 1

    Write-Host "Bridge '$BridgeName' created."
}

function Remove-Bridge {
    param([Parameter(Mandatory=$true)][string]$BridgeName)

    $adapter = Get-NetAdapter -Name $BridgeName -ErrorAction SilentlyContinue
    if (!$adapter) {
        Write-Host "Bridge '$BridgeName' not found, skipping."
        return
    }

    Write-Host "Removing bridge '$BridgeName'..."
    $list = netsh bridge list
    if ($list -match "No bridges are currently configured") {
        Write-Host "No network bridge found to remove."
        return
    }

    $guid = ($list | Select-String -Pattern "\{[^\}]+\}").Matches[0].Value
    if (!$guid) {
        Write-Host "Failed to parse bridge GUID from netsh output."
        return
    }

    Start-Process -FilePath "netsh" -ArgumentList @("bridge","remove","all","from",$guid) -Wait -NoNewWindow
    Start-Sleep -Seconds 1
    Start-Process -FilePath "netsh" -ArgumentList "bridge delete" -Wait -NoNewWindow
    Start-Sleep -Seconds 1

    Write-Host "Bridge '$BridgeName' removed (GUID $guid)."
}

function Add-TapToBridge {
    param(
        [Parameter(Mandatory=$true)][string]$TapName,
        [Parameter(Mandatory=$true)][string]$BridgeName
    )
    $tapAdapter    = Get-NetAdapter -Name $TapName    -ErrorAction SilentlyContinue
    $bridgeAdapter = Get-NetAdapter -Name $BridgeName -ErrorAction SilentlyContinue

    if (!$tapAdapter)    { Write-Host "TAP '$TapName' not found."; return }
    if (!$bridgeAdapter) { Write-Host "Bridge '$BridgeName' not found."; return }

    Write-Host "Adding TAP '$TapName' to Bridge '$BridgeName'..."
    $tapGuid    = $tapAdapter.InterfaceGuid
    $bridgeGuid = $bridgeAdapter.InterfaceGuid
    # netsh "bridge add <TapGuid> to <BridgeGuid>"
    Start-Process -FilePath "netsh" -ArgumentList "bridge add `"$tapGuid`" to `"$bridgeGuid`"" -Wait -NoNewWindow
    Write-Host "Done."
}

function Remove-TapFromBridge {
    param(
        [Parameter(Mandatory=$true)][string]$TapName,
        [Parameter(Mandatory=$true)][string]$BridgeName
    )
    $tapAdapter    = Get-NetAdapter -Name $TapName    -ErrorAction SilentlyContinue
    $bridgeAdapter = Get-NetAdapter -Name $BridgeName -ErrorAction SilentlyContinue

    if (!$tapAdapter -or !$bridgeAdapter) {
        Write-Host "Either TAP '$TapName' or Bridge '$BridgeName' not found."
        return
    }

    Write-Host "Removing TAP '$TapName' from Bridge '$BridgeName'..."
    $tapGuid    = $tapAdapter.InterfaceGuid
    $bridgeGuid = $bridgeAdapter.InterfaceGuid

    # netsh "bridge remove <TapGuid> from <BridgeGuid>"
    # This un-bridges the TAP from the specified bridge
    $removeCmd = "bridge remove `"$tapGuid`" from `"$bridgeGuid`""
    Start-Process -FilePath "netsh" -ArgumentList $removeCmd -Wait -NoNewWindow
    Write-Host "Done."
}

# ----------------------------------------------------
# 3) Main Execution Logic
# ----------------------------------------------------
switch ($action) {
    'help' {
        Write-Host "Usage:"
        Write-Host "  .\tap-bridge.ps1 install --tap <TapName>"
        Write-Host "     Installs a TAP named <TapName>."
        Write-Host ""
        Write-Host "  .\tap-bridge.ps1 install --tap <TapName> --bridge <BridgeName> [--external <NetAdapter>]"
        Write-Host "     Also creates a bridge <BridgeName>, bridging <TapName> + <NetAdapter> (or first found NIC)."
        Write-Host ""
        Write-Host "  .\tap-bridge.ps1 uninstall --tap <TapName>"
        Write-Host "     Removes a TAP named <TapName> via pnputil."
        Write-Host ""
        Write-Host "  .\tap-bridge.ps1 uninstall --bridge <BridgeName>"
        Write-Host "     Removes a Bridge named <BridgeName>."
        Write-Host ""
        Write-Host "  .\tap-bridge.ps1 add --tap <TapName> --bridge <BridgeName>"
        Write-Host "     Adds an existing TAP <TapName> to an existing Bridge <BridgeName>."
        Write-Host ""
        Write-Host "  .\tap-bridge.ps1 remove --tap <TapName> --bridge <BridgeName>"
        Write-Host "     Removes an existing TAP <TapName> from an existing Bridge <BridgeName>."
        return
    }

    'install' {
        if (-not $tap) {
            Write-Host "Error: 'install' requires --tap <TapName>."
            return
        }
        $tapAdapter = Install-TAP -TapName $tap
        if ($bridge -and $tapAdapter) {
            Create-Bridge -BridgeName $bridge -TapName $tap -External $external
        }
    }

    'uninstall' {
        if ($tap) {
            Uninstall-TAP -TapName $tap
        }
        if ($bridge) {
            Remove-Bridge -BridgeName $bridge
        }
        if (-not $tap -and -not $bridge) {
            Write-Host "Nothing to uninstall. Please specify --tap or --bridge."
        }
    }

    'add' {
        if ($tap -and $bridge) {
            Add-TapToBridge -TapName $tap -BridgeName $bridge
        }
        else {
            Write-Host "Usage: .\tap-bridge.ps1 add --tap <TapName> --bridge <BridgeName>"
        }
    }

    'remove' {
        if ($tap -and $bridge) {
            Remove-TapFromBridge -TapName $tap -BridgeName $bridge
        }
        else {
            Write-Host "Usage: .\tap-bridge.ps1 remove --tap <TapName> --bridge <BridgeName>"
        }
    }

    default {
        if ($action) {
            Write-Host "Unknown action '$action'. Type .\tap-bridge.ps1 help"
        } else {
            Write-Host "No action specified. Type .\tap-bridge.ps1 help"
        }
    }
}

Write-Host "Done."
