# push-to-github.ps1 — 一键把本目录推上 GitHub 并触发云端编译
#
# 用法：
#   1. 先在 https://github.com/new 新建一个【空仓库】（Public，不勾选任何初始化选项）
#   2. 把下面 $GITHUB_REPO 改成你的仓库地址
#   3. 在本目录终端执行：  .\push-to-github.ps1
#   （首次 push 会弹出 GitHub 登录窗口，用浏览器登录授权即可）

$GITHUB_REPO = "https://github.com/13388451099j-coder/MIAOYU.git"   # ← 改这里
$GIT = "D:\Program Files\Git\cmd\git.exe"

Set-Location $PSScriptRoot

& $GIT init
& $GIT add .
& $GIT commit -m "Miaoyu iOS: initial commit"
& $GIT branch -M main
if (-not (& $GIT remote)) {
    & $GIT remote add origin $GITHUB_REPO
} else {
    & $GIT remote set-url origin $GITHUB_REPO
}
& $GIT push -u origin main

if ($LASTEXITCODE -eq 0) {
    $actionsUrl = ($GITHUB_REPO -replace '\.git$', '') + "/actions"
    Write-Host ""
    Write-Host "✅ 推送成功！云端编译已自动开始，打开下面页面看进度和下载产物：" -ForegroundColor Green
    Write-Host "   $actionsUrl" -ForegroundColor Cyan
    Write-Host "   构建约 5-10 分钟，绿勾后在该次运行页面底部 Artifacts 下载 MiaoyuApp-unsigned-ipa"
} else {
    Write-Host "`n❌ 推送失败：确认仓库地址正确、已在 GitHub 登录授权。详见 GITHUB_BUILD.md" -ForegroundColor Red
}
pause
