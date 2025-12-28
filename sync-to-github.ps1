# Mass AI Docs - GitHub Auto Sync Script
# 사용법: .\sync-to-github.ps1 [-Message "커밋 메시지"]

param(
    [string]$Message = "Update Mass AI documentation"
)

$DocsPath = "C:\Users\RussellMainV3\Perforce\RussellV3_ProjectRYU\Docs\MassAI"

Set-Location $DocsPath

# 변경사항 확인
$status = git status --porcelain
if (-not $status) {
    Write-Host "No changes to commit." -ForegroundColor Yellow
    exit 0
}

# 변경된 파일 목록
Write-Host "Changed files:" -ForegroundColor Cyan
git status --short

# 스테이징
git add .

# 커밋
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$fullMessage = "$Message`n`nUpdated: $timestamp`nGenerated with Claude Code"

git commit -m $fullMessage

# 푸시
Write-Host "`nPushing to GitHub..." -ForegroundColor Green
git push origin main

Write-Host "`nSync complete!" -ForegroundColor Green
