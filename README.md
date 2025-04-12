# tap-bridge.ps1

## Overview

`tap-bridge.ps1` is a PowerShell script designed to manage TAP adapters and network bridges. It provides functions for installing, uninstalling, creating, and removing TAP adapters and network bridges. The script also includes command-line parsing to handle various actions like `install`, `uninstall`, `add`, and `remove`.

## Table of Contents

- [Overview](#overview)
- [Functionality](#functionality)
- [Usage Examples](#usage-examples)
  - [Install TAP Adapter](#install-tap-adapter)
  - [Uninstall TAP Adapter](#uninstall-tap-adapter)
  - [Create Network Bridge](#create-network-bridge)
  - [Remove Network Bridge](#remove-network-bridge)
  - [Add TAP to Bridge](#add-tap-to-bridge)
  - [Remove TAP from Bridge](#remove-tap-from-bridge)
- [Optional Paid Support](#optional-paid-support)

## Functionality

The `tap-bridge.ps1` script includes the following functions:

- `Download-TAPDrivers`: Downloads the latest TAP drivers from GitHub.
- `Install-TAP`: Installs a TAP adapter with a specified name.
- `Uninstall-TAP`: Uninstalls a TAP adapter with a specified name.
- `Create-Bridge`: Creates a network bridge with a specified name, TAP adapter, and optional external network adapter.
- `Remove-Bridge`: Removes a network bridge with a specified name.
- `Add-TapToBridge`: Adds an existing TAP adapter to an existing network bridge.
- `Remove-TapFromBridge`: Removes an existing TAP adapter from an existing network bridge.

## Usage Examples

### Install TAP Adapter

To install a TAP adapter with a specified name:

```powershell
.\tap-bridge.ps1 install --tap <TapName>
```

### Uninstall TAP Adapter

To uninstall a TAP adapter with a specified name:

```powershell
.\tap-bridge.ps1 uninstall --tap <TapName>
```

### Create Network Bridge

To create a network bridge with a specified name, TAP adapter, and optional external network adapter:

```powershell
.\tap-bridge.ps1 install --tap <TapName> --bridge <BridgeName> [--external <NetAdapter>]
```

### Remove Network Bridge

To remove a network bridge with a specified name:

```powershell
.\tap-bridge.ps1 uninstall --bridge <BridgeName>
```

### Add TAP to Bridge

To add an existing TAP adapter to an existing network bridge:

```powershell
.\tap-bridge.ps1 add --tap <TapName> --bridge <BridgeName>
```

### Remove TAP from Bridge

To remove an existing TAP adapter from an existing network bridge:

```powershell
.\tap-bridge.ps1 remove --tap <TapName> --bridge <BridgeName>
```
