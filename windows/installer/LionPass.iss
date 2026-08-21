#ifndef Architecture
  #define Architecture "x64"
#endif
#ifndef PublishRoot
  #define PublishRoot "publish-x64"
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
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}

[Files]
Source: "{#PublishRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Lion Pass"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Lion Pass"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos adicionais:"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Abrir Lion Pass"; Flags: nowait postinstall skipifsilent
