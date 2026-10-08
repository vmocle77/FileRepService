@echo off
setlocal

echo Removing the File Repository Service scheduled task and application files...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; try { $task = Get-ScheduledTask -TaskName 'FileRepositoryService' -ErrorAction Stop; $action = @($task.Actions | Where-Object { $_.Execute } )[0]; if (-not $action) { throw 'The scheduled task has no executable Action.' }; $actionPath = [Environment]::ExpandEnvironmentVariables($action.Execute.Trim([char]34)); if ([IO.Path]::GetFileName($actionPath) -ine 'Run_FileRepository.cmd') { throw ('Unexpected scheduled-task Action: ' + $action.Execute + '. Refusing to delete files.'); }; $repositoryRoot = Split-Path -Parent $actionPath; if (-not [IO.Path]::IsPathRooted($repositoryRoot)) { throw ('The task Action does not contain an absolute repository path: ' + $action.Execute); }; Unregister-ScheduledTask -InputObject $task -Confirm:$false; foreach ($name in @('FileServerApp.py', 'index.html')) { $filePath = Join-Path $repositoryRoot $name; if (Test-Path -LiteralPath $filePath -PathType Leaf) { Remove-Item -LiteralPath $filePath -Force -ErrorAction Stop; Write-Host ('Removed ' + $filePath); } else { Write-Host ('Not found; skipped ' + $filePath); } }; Write-Host ('Removed scheduled task FileRepositoryService.'); Write-Host ('Other files and folders were left untouched in ' + $repositoryRoot + '.'); Write-Host 'If you no longer need the repository structure or its data, remove it manually.' } catch { Write-Error ('Uninstall failed: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 (
    echo.
    echo Uninstall failed. Review the error above and resolve it before retrying.
    pause
    exit /b 1
)

echo.
echo Uninstall completed. The repository folder and its remaining contents were not removed.
pause
exit /b 0
