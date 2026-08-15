; Mise Windows installer built with Inno Setup 6.
; Paths are relative to this file (scripts/).
; Version is passed via /DMyAppVersion on the ISCC command line.

#ifndef MyAppVersion
  #define MyAppVersion "2.1.0"
#endif

#define MyAppName "Mise"
#define MyAppPublisher "Bezaleel Paul"
#define MyAppExeName "file_organizer.exe"
#define MyAppIcon "..\windows\runner\resources\app_icon.ico"
#define MyAppSourceDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{7E2B0A9C-2A63-4E58-9C7E-B6D4F1C8A3D5}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\installer
OutputBaseFilename=mise-setup-{#MyAppVersion}
SetupIconFile={#MyAppIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
