param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^v\d+\.\d+\.\d+$")]
    [string]$Tag,

    [Parameter(Mandatory = $true)]
    [string]$CertificateSubjectName,

    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [string]$UnsignedZipPath,
    [string]$WorkspaceRoot = (Join-Path $PSScriptRoot ".."),
    [string]$OutputDir = (Join-Path $PSScriptRoot "../.release-local"),
    [switch]$NoPublish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-WdkWhere {
    $command = Get-Command wdkwhere -ErrorAction SilentlyContinue
    if (!$command) {
        throw "wdkwhere was not found in PATH. Install it first (dotnet tool install --global Nefarius.Tools.WDKWhere)."
    }

    return $command.Source
}

function Resolve-UnsignedZip {
    param(
        [string]$TagValue,
        [string]$ExplicitZipPath,
        [string]$DestinationDir
    )

    if ($ExplicitZipPath) {
        if (!(Test-Path $ExplicitZipPath)) {
            throw "Unsigned zip path not found: $ExplicitZipPath"
        }

        return (Resolve-Path $ExplicitZipPath).Path
    }

    $workflowName = "release.yml"
    $artifactName = "unsigned-release-bundle-$TagValue"
    $runRows = gh run list --workflow $workflowName --limit 100 --json databaseId,headBranch,displayTitle,status,conclusion,event | ConvertFrom-Json
    if (!$runRows) {
        throw "No workflow runs found for '$workflowName'."
    }

    $run = $runRows |
        Where-Object {
            $_.event -eq "push" -and
            $_.status -eq "completed" -and
            $_.conclusion -eq "success" -and
            ($_.headBranch -eq $TagValue -or $_.displayTitle -eq $TagValue)
        } |
        Select-Object -First 1

    if (!$run) {
        throw "No successful '$workflowName' run found for tag '$TagValue'."
    }

    $downloadDir = Join-Path $DestinationDir "downloaded"
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

    gh run download $run.databaseId -n $artifactName -D $downloadDir | Out-Null

    $zip = Get-ChildItem -Path $downloadDir -Filter "Injector_x86_amd64_arm64_unsigned.zip" -File -Recurse | Select-Object -First 1
    if (!$zip) {
        throw "Downloaded artifact '$artifactName' did not contain Injector_x86_amd64_arm64_unsigned.zip."
    }

    return $zip.FullName
}

function Sign-Binary {
    param(
        [string]$WdkWherePath,
        [string]$CertSubjectName,
        [string]$Timestamp,
        [string]$FilePath
    )

    if (!(Test-Path $FilePath)) {
        throw "Expected binary missing: $FilePath"
    }

    & $WdkWherePath run signtool sign /n $CertSubjectName /a /fd SHA256 /td SHA256 /tr $Timestamp $FilePath
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed for '$FilePath' with exit code $LASTEXITCODE."
    }
}

Push-Location $WorkspaceRoot
try {
    # Validate GH auth early because this script relies on release + artifact APIs.
    gh auth status | Out-Null

    $wdkWhere = Ensure-WdkWhere
    Write-Host "Using wdkwhere: $wdkWhere"

    $resolvedOutputDir = Resolve-Path (New-Item -ItemType Directory -Path $OutputDir -Force)
    $workRoot = Join-Path $resolvedOutputDir ".work-$Tag"
    if (Test-Path $workRoot) {
        Remove-Item -Path $workRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    $unsignedZip = Resolve-UnsignedZip -TagValue $Tag -ExplicitZipPath $UnsignedZipPath -DestinationDir $workRoot
    Write-Host "Using unsigned zip: $unsignedZip"

    $unsignedExtract = Join-Path $workRoot "unsigned"
    Expand-Archive -Path $unsignedZip -DestinationPath $unsignedExtract -Force

    $targets = @(
        (Join-Path $unsignedExtract "ARM64/Injector.exe"),
        (Join-Path $unsignedExtract "Win32/Injector.exe"),
        (Join-Path $unsignedExtract "x64/Injector.exe")
    )

    foreach ($file in $targets) {
        Write-Host "Signing $file"
        Sign-Binary -WdkWherePath $wdkWhere -CertSubjectName $CertificateSubjectName -Timestamp $TimestampUrl -FilePath $file
    }

    $finalZip = Join-Path $resolvedOutputDir "Injector_x86_amd64_arm64.zip"
    if (Test-Path $finalZip) {
        Remove-Item -Path $finalZip -Force
    }
    Compress-Archive -Path (Join-Path $unsignedExtract "*") -DestinationPath $finalZip
    Write-Host "Created signed zip: $finalZip"

    gh release view $Tag --json tagName,isDraft | Out-Null
    gh release upload $Tag $finalZip --clobber | Out-Null
    Write-Host "Uploaded asset to release '$Tag'."

    if (-not $NoPublish) {
        gh release edit $Tag --draft=false | Out-Null
        Write-Host "Published release '$Tag'."
    }
    else {
        Write-Host "Draft release left unpublished due to -NoPublish."
    }
}
finally {
    Pop-Location
}
