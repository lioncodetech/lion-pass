param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$WindowsRoot = Split-Path -Parent $PSScriptRoot
$PublishRoot = Join-Path $WindowsRoot "installer\publish-$Architecture"
$Project = Join-Path $WindowsRoot "src\LionPass.App\LionPass.App.csproj"
$RuntimeVersion = "2.3.1"
$RuntimeInstallerRoot = Join-Path $WindowsRoot "installer\runtime-$Architecture"
$RuntimeInstaller = Join-Path $RuntimeInstallerRoot "WindowsAppRuntimeInstall.exe"
$RuntimeInstallerUrls = @{
    x64 = "https://aka.ms/windowsappsdk/2.3/$RuntimeVersion/windowsappruntimeinstall-x64.exe"
    arm64 = "https://aka.ms/windowsappsdk/2.3/$RuntimeVersion/windowsappruntimeinstall-arm64.exe"
}
$RuntimeInstallerHashes = @{
    x64 = "4011748ddf472b7e856d909fdfb4e9b19c3d23fcd8121039ac91f99d5ffa65db"
    arm64 = "cc0070b510610944cb1a68021f3485c14067feae73b0f4aaefbdbe5db33e9f69"
}

if (Test-Path $PublishRoot) {
    Remove-Item -LiteralPath $PublishRoot -Recurse -Force
}

dotnet publish $Project `
    --configuration $Configuration `
    --runtime "win-$Architecture" `
    --self-contained true `
    -p:Platform=$Architecture `
    -p:WindowsAppSDKSelfContained=false `
    -p:PublishSingleFile=false `
    -p:PublishTrimmed=false `
    --output $PublishRoot

if ($LASTEXITCODE -ne 0) {
    throw "A publicação do Lion Pass falhou com o código $LASTEXITCODE."
}

$RequiredFiles = @(
    "LionPass.App.exe",
    "LionPass.App.dll",
    "LionPass.App.deps.json",
    "LionPass.App.runtimeconfig.json",
    "Microsoft.WindowsAppRuntime.Bootstrap.dll"
)

foreach ($RequiredFile in $RequiredFiles) {
    $RequiredPath = Join-Path $PublishRoot $RequiredFile
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Publicação incompleta: o arquivo obrigatório '$RequiredFile' não foi gerado."
    }
}

New-Item -ItemType Directory -Path $RuntimeInstallerRoot -Force | Out-Null
$ExpectedRuntimeHash = $RuntimeInstallerHashes[$Architecture]
$DownloadRuntime = $true
if (Test-Path -LiteralPath $RuntimeInstaller -PathType Leaf) {
    $ExistingHash = (Get-FileHash -Algorithm SHA256 $RuntimeInstaller).Hash.ToLowerInvariant()
    $DownloadRuntime = $ExistingHash -ne $ExpectedRuntimeHash
}

if ($DownloadRuntime) {
    if (Test-Path -LiteralPath $RuntimeInstaller) {
        Remove-Item -LiteralPath $RuntimeInstaller -Force
    }
    Invoke-WebRequest -Uri $RuntimeInstallerUrls[$Architecture] -OutFile $RuntimeInstaller
}

$ActualRuntimeHash = (Get-FileHash -Algorithm SHA256 $RuntimeInstaller).Hash.ToLowerInvariant()
if ($ActualRuntimeHash -ne $ExpectedRuntimeHash) {
    throw "SHA-256 inválido para Windows App Runtime $RuntimeVersion ($Architecture): $ActualRuntimeHash"
}

$RuntimeSignature = Get-AuthenticodeSignature $RuntimeInstaller
if ($RuntimeSignature.Status -ne "Valid" -or
    $RuntimeSignature.SignerCertificate.Subject -notmatch "Microsoft Corporation") {
    throw "Assinatura Authenticode inválida para Windows App Runtime: $($RuntimeSignature.Status)"
}

$Inno = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $Inno)) {
    throw "Instale o Inno Setup 6 para gerar o instalador: https://jrsoftware.org/isinfo.php"
}

& $Inno "/DArchitecture=$Architecture" "/DPublishRoot=$PublishRoot" "/DRuntimeInstaller=$RuntimeInstaller" (Join-Path $WindowsRoot "installer\LionPass.iss")
if ($LASTEXITCODE -ne 0) {
    throw "A geração do instalador falhou com o código $LASTEXITCODE."
}
