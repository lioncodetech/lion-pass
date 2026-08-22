#ifndef Architecture
  #define Architecture "x64"
#endif
#ifndef PublishRoot
  #define PublishRoot "publish-x64"
#endif
#ifndef RuntimeInstaller
  #define RuntimeInstaller "runtime-x64\WindowsAppRuntimeInstall.exe"
#endif

#define AppName "Lion Pass"
#define AppVersion "1.0.0"
#define AppPublisher "Lion Code Technology"
#define AppURL "https://lioncodetech.com.br/"
#define AppExeName "LionPass.App.exe"

[Setup]
AppId={{CC5B9F04-8BF2-4ACE-A45D-A2540618B388}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
MinVersion=10.0.19041
DefaultDirName={autopf}\Lion Pass
DefaultGroupName=Lion Pass
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=LionPass-Windows-{#Architecture}-Setup
SetupIconFile=..\src\LionPass.App\Assets\LionPass.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
#if Architecture == "arm64"
  ArchitecturesAllowed=arm64
  ArchitecturesInstallIn64BitMode=arm64
#else
  ArchitecturesAllowed=x64compatible
  ArchitecturesInstallIn64BitMode=x64compatible
#endif
UninstallDisplayIcon={app}\{#AppExeName}

[Files]
Source: "{#PublishRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RuntimeInstaller}"; DestName: "WindowsAppRuntimeInstall.exe"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\Lion Pass"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Lion Pass"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos adicionais:"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Abrir Lion Pass"; Flags: nowait postinstall skipifsilent

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  InstallerPath: String;
begin
  Result := '';
  ExtractTemporaryFile('WindowsAppRuntimeInstall.exe');
  InstallerPath := ExpandConstant('{tmp}\WindowsAppRuntimeInstall.exe');

  if not Exec(InstallerPath, '--quiet', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := 'Não foi possível iniciar a instalação dos componentes do Windows necessários para o Lion Pass.';
    Exit;
  end;

  if ResultCode = 3010 then
    NeedsRestart := True
  else if ResultCode <> 0 then
    Result := Format('A instalação do Windows App Runtime falhou com o código %d. O Lion Pass não foi instalado.', [ResultCode]);
end;
