param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$WindowsRoot = Split-Path -Parent $PSScriptRoot
$PublishRoot = Join-Path $WindowsRoot "installer\publish-$Architecture"
$Project = Join-Path $WindowsRoot "src\LionPass.App\LionPass.App.csproj"

if (Test-Path $PublishRoot) {
    Remove-Item -LiteralPath $PublishRoot -Recurse -Force
}

dotnet publish $Project `
    --configuration $Configuration `
    --runtime "win-$Architecture" `
    --self-contained true `
    -p:Platform=$Architecture `
    -p:WindowsAppSDKSelfContained=true `
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
    "Microsoft.WindowsAppRuntime.dll",
    "Microsoft.UI.Xaml.dll"
)

foreach ($RequiredFile in $RequiredFiles) {
    $RequiredPath = Join-Path $PublishRoot $RequiredFile
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Publicação incompleta: o arquivo obrigatório '$RequiredFile' não foi gerado."
    }
}

$Inno = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $Inno)) {
    throw "Instale o Inno Setup 6 para gerar o instalador: https://jrsoftware.org/isinfo.php"
}

& $Inno "/DArchitecture=$Architecture" "/DPublishRoot=$PublishRoot" (Join-Path $WindowsRoot "installer\LionPass.iss")
if ($LASTEXITCODE -ne 0) {
    throw "A geração do instalador falhou com o código $LASTEXITCODE."
}
