' Windows Script Host launches one verified job in the user's interactive desktop.
' Background jobs remain hidden; terminal jobs inherit a real console for
' native Codex questions and approvals. Both wait for PowerShell to exit.
Option Explicit
Dim shell, files, folder, script, jobFile, command, status, pwsh, visibility
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
If WScript.Arguments.Count < 1 Or WScript.Arguments.Count > 3 Then WScript.Quit 2
visibility = 0
pwsh = ""
If WScript.Arguments.Count >= 2 Then
    If WScript.Arguments(1) = "terminal" Then
        If WScript.Arguments.Count <> 2 Then WScript.Quit 2
        visibility = 1
    Else
        pwsh = WScript.Arguments(1)
    End If
End If
If WScript.Arguments.Count = 3 Then
    If WScript.Arguments(2) <> "terminal" Then WScript.Quit 2
    visibility = 1
End If
folder = files.GetParentFolderName(WScript.ScriptFullName)
script = files.BuildPath(folder, "Invoke-CodexJob.ps1")
jobFile = WScript.Arguments(0)
If Not files.FileExists(script) Or Not files.FileExists(jobFile) Then WScript.Quit 2
' New tasks carry the absolute host verified when they were registered.
' Never search PATH or the repository working directory at execution time.
' Retain the former default only for legacy one/two-argument invocations.
If pwsh = "" Then pwsh = files.BuildPath(shell.ExpandEnvironmentStrings("%ProgramFiles%"), "PowerShell\7\pwsh.exe")
If InStr(pwsh, Chr(34)) > 0 Or InStr(pwsh, vbCr) > 0 Or InStr(pwsh, vbLf) > 0 Then WScript.Quit 2
If LCase(files.GetFileName(pwsh)) <> "pwsh.exe" Then WScript.Quit 2
If LCase(files.GetAbsolutePathName(pwsh)) <> LCase(pwsh) Then WScript.Quit 2
If Not files.FileExists(pwsh) Then WScript.Quit 2
command = Chr(34) & pwsh & Chr(34) & " -NoLogo -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34) & _
          " -JobFile " & Chr(34) & jobFile & Chr(34)
On Error Resume Next
status = shell.Run(command, visibility, True)
If Err.Number <> 0 Then
    Dim errorPath, errFile
    ' Launcher diagnostics must remain with the scheduled job, including QA.
    errorPath = files.GetParentFolderName(jobFile)
    If Not files.FolderExists(errorPath) Then files.CreateFolder(errorPath)
    Set errFile = files.OpenTextFile(files.BuildPath(errorPath, "runner-launch-errors.log"), 8, True)
    errFile.WriteLine Now & " " & Err.Description
    errFile.Close
    WScript.Quit 1
End If
On Error GoTo 0
WScript.Quit status
