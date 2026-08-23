#ifndef Architecture
  #define Architecture "x64"
#endif
#ifndef PublishRoot
  #define PublishRoot "publish-x64"
#endif
#ifndef RuntimeInstaller
  #define RuntimeInstaller "runtime-x64\WindowsAppRuntimeInstall.exe"
#endif

#ifndef AppVersion
  #define AppVersion "1.0.1"
#endif

#define AppName "Lion Pass"
#define AppPublisher "Lion Code Technology"
#define AppURL "https://lioncodetech.com.br/"
#define AppExeName "LionPass.App.exe"

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[CustomMessages]
brazilianportuguese.DesktopIcon=Criar atalho na área de trabalho
english.DesktopIcon=Create a desktop shortcut
spanish.DesktopIcon=Crear un acceso directo en el escritorio
brazilianportuguese.AdditionalShortcuts=Atalhos adicionais:
english.AdditionalShortcuts=Additional shortcuts:
spanish.AdditionalShortcuts=Accesos directos adicionales:
brazilianportuguese.OpenApp=Abrir Lion Pass
english.OpenApp=Open Lion Pass
spanish.OpenApp=Abrir Lion Pass

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
OutputBaseFilename=LionPass-Windows-{#Architecture}-{#AppVersion}-Setup
SetupIconFile=..\src\LionPass.Client.noindex\Assets\LionPass.ico
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

[InstallDelete]
; Remove componentes locais deixados pelas versões autocontidas antigas.
; Os cofres e as configurações ficam em %LOCALAPPDATA% e não são afetados.
Type: files; Name: "{app}\Microsoft.UI*.dll"
Type: files; Name: "{app}\Microsoft.UI*.pri"
Type: files; Name: "{app}\Microsoft.Windows*.dll"
Type: files; Name: "{app}\Microsoft.Windows*.pri"
Type: files; Name: "{app}\Microsoft.Graphics*.dll"
Type: files; Name: "{app}\Microsoft.*.winmd"
Type: files; Name: "{app}\DWriteCore.dll"
Type: files; Name: "{app}\WinUIEdit.dll"
Type: files; Name: "{app}\CoreMessagingXP.dll"
Type: files; Name: "{app}\dcompi.dll"
Type: files; Name: "{app}\dwmcorei.dll"
Type: files; Name: "{app}\DwmSceneI.dll"
Type: files; Name: "{app}\wuceffectsi.dll"
Type: files; Name: "{app}\marshal.dll"
Type: files; Name: "{app}\MRM.dll"
Type: files; Name: "{app}\resources.pri"
Type: filesandordirs; Name: "{app}\Microsoft.UI.Xaml"

[Files]
Source: "{#PublishRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RuntimeInstaller}"; DestName: "WindowsAppRuntimeInstall.exe"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\Lion Pass"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Lion Pass"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; GroupDescription: "{cm:AdditionalShortcuts}"

[Registry]
Root: HKCU; Subkey: "Software\Lion Code Technology\Lion Pass"; ValueType: string; ValueName: "Language"; ValueData: "{code:GetSelectedAppLanguage}"; Flags: createvalueifdoesntexist uninsdeletevalue
Root: HKCU; Subkey: "Software\Lion Code Technology\Lion Pass"; ValueType: string; ValueName: "LanguageChosen"; ValueData: "1"; Flags: createvalueifdoesntexist uninsdeletevalue

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:OpenApp}"; Flags: nowait postinstall skipifsilent

[Code]
function GetSelectedAppLanguage(Param: String): String;
begin
  if ActiveLanguage = 'english' then
    Result := 'en-US'
  else if ActiveLanguage = 'spanish' then
    Result := 'es-ES'
  else
    Result := 'pt-BR';
end;

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
