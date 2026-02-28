# Release process

## Overview

Pushing a tag like `v1.5.0` triggers `.github/workflows/release.yml`, which:

- Builds `Injector.exe` for `Win32`, `x64`, and `ARM64`
- Creates an unsigned bundle artifact: `Injector_x86_amd64_arm64_unsigned.zip`
- Creates a draft GitHub release for the tag

Final signing and publish are performed locally on the EV-capable machine.

## Prerequisites

1. `gh` CLI installed and authenticated (`gh auth status`)
2. [`wdkwhere`](https://github.com/nefarius/wdkwhere) installed and available in `PATH`
3. EV token/certificate available and unlocked

## Finalize a tagged release

Run from repository root:

```powershell
.\scripts\finalize-release.ps1 -Tag v1.5.0 -CertificateSubjectName "Nefarius Software Solutions e.U."
```

The script will:

- Download `unsigned-release-bundle-v1.5.0` automatically (unless `-UnsignedZipPath` is provided)
- Sign:
  - `ARM64/Injector.exe`
  - `Win32/Injector.exe`
  - `x64/Injector.exe`
- Create `Injector_x86_amd64_arm64.zip`
- Upload it to the draft release and publish it

## Useful options

```powershell
# Upload signed zip but keep release as draft
.\scripts\finalize-release.ps1 -Tag v1.5.0 -CertificateSubjectName "Nefarius Software Solutions e.U." -NoPublish

# Use a manually downloaded unsigned zip
.\scripts\finalize-release.ps1 -Tag v1.5.0 -CertificateSubjectName "Nefarius Software Solutions e.U." -UnsignedZipPath "C:\Temp\Injector_x86_amd64_arm64_unsigned.zip"
```
