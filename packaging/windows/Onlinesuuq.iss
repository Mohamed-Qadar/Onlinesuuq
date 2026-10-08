; Inno Setup 6.3+ -- compile AFTER the x64 Flutter release and runtime copy.
; Keep AppId unchanged for future versions to upgrade the same installation.
#ifndef MyAppVersion
  #define MyAppVersion "1.1.1"
#endif
#define MyAppName "Onlinesuuq"
#define MyAppExeName "Onlinesuuq.exe"
#define ReleaseDir SourcePath + "..\..\mobile\build\windows\x64\runner\Release"

#if !FileExists(ReleaseDir + "\" + MyAppExeName)
  #error Build the Windows x64 release before compiling this installer.
#endif
#if !FileExists(ReleaseDir + "\msvcp140.dll") || !FileExists(ReleaseDir + "\vcruntime140.dll") || !FileExists(ReleaseDir + "\vcruntime140_1.dll")
  #error Run Copy-VCRuntime.ps1 before compiling this installer.
#endif

[Setup]
AppId={{B3E95593-F277-4BCD-93F0-A31B18DCC913}
AppName={#MyAppName}
AppPublisher=Eng. Mohamed Ibrahim Abdi
AppContact=mohamedqadar280@gmail.com
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppSupportURL=https://github.com/Mohamed-Qadar/Onlinesuuq/issues
AppUpdatesURL=https://github.com/Mohamed-Qadar/Onlinesuuq/releases
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#SourcePath}..\..\dist
OutputBaseFilename=Onlinesuuq-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartApplications=no
SetupLogging=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; Copy the entire release tree: executable, plugin DLLs, runtime and data assets.
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
