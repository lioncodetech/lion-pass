param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$WindowsRoot = Split-Path -Parent $PSScriptRoot
$PublishRoot = Join-Path $WindowsRoot "installer\publish-$Architecture"
$Project = Join-Path $WindowsRoot "src\LionPass.App\LionPass.App.csproj"

dotnet publish $Project `
    --configuration $Configuration `
    --runtime "win-$Architecture" `
    --self-contained true `
    -p:Platform=$Architecture `
    -p:PublishSingleFile=false `
    --output $PublishRoot

$Inno = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $Inno)) {
    throw "Instale o Inno Setup 6 para gerar o instalador: https://jrsoftware.org/isinfo.php"
}

& $Inno "/DArchitecture=$Architecture" "/DPublishRoot=$PublishRoot" (Join-Path $WindowsRoot "installer\LionPass.iss")
