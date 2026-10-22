# 红树下胶片（桌面版 RetroFilmCam）· 一键云端编译未签名 IPA
# 用法（Windows PowerShell，全程不需要 Mac）：
#   powershell -ExecutionPolicy Bypass -File tools\push_and_build.ps1 -Token ghp_xxxxxxxx
# 脚本自动完成：建私有仓库 → 推代码 → 触发 macOS 云编译 → 把 ipa 下到桌面
#
# 参数：
#   -Token      GitHub Personal Access Token（必填，勾 repo + workflow 即可）
#   -RepoName   仓库名，默认 retro-film-cam
#   -Owner      GitHub 用户名（默认自动读 Token 所属账号）

param(
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$RepoName = "retro-film-cam",
    [string]$Owner = ""
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Api = "https://api.github.com"
$Headers = @{
    "Authorization"        = "token $Token"
    "Accept"               = "application/vnd.github+json"
    "User-Agent"           = "hongsx-ipa-builder"
    "X-GitHub-Api-Version" = "2022-11-28"
}

function Step($msg) { Write-Host "`n==== $msg ====" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  !   $msg" -ForegroundColor Yellow }

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot
Write-Host "工程目录: $RepoRoot"

# ---------- 1. 校验 Token ----------
Step "校验 GitHub Token"
$me = Invoke-RestMethod -Uri "$Api/user" -Headers $Headers -Method Get
if (-not $Owner) { $Owner = $me.login }
Ok "登录账号: $Owner"

# ---------- 2. 私有仓库 ----------
Step "准备私有仓库 $Owner/$RepoName"
$repoExists = $true
try { Invoke-RestMethod -Uri "$Api/repos/$Owner/$RepoName" -Headers $Headers -Method Get | Out-Null }
catch { $repoExists = $false }

if (-not $repoExists) {
    $body = @{ name = $RepoName; private = $true; description = "红树下胶片 · RetroFilmCam (Desktop edition)" } | ConvertTo-Json
    Invoke-RestMethod -Uri "$Api/user/repos" -Headers $Headers -Method Post -Body $body -ContentType "application/json" | Out-Null
    Ok "已创建私有仓库"
} else {
    Ok "仓库已存在，直接复用"
}

# ---------- 3. 推送代码 ----------
Step "推送代码"
if (-not (Test-Path ".git")) {
    git init | Out-Null
    git branch -M main
}
git config user.name  "hongsx-builder" | Out-Null
git config user.email "$Owner@users.noreply.github.com" | Out-Null
git add -A
$status = git status --porcelain
if ($status) {
    git commit -m "build: 更新红树下胶片工程 ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" | Out-Null
    Ok "已提交改动"
} else {
    Warn "没有新改动，沿用已有提交"
}
$remoteUrl = "https://x-access-token:$Token@github.com/$Owner/$RepoName.git"
git remote remove origin 2>$null
git remote add origin $remoteUrl
git push -u origin main --force 2>&1 | Tee-Object -Variable pushOut | Out-Null
if ($LASTEXITCODE -ne 0) { throw "推送失败：$pushOut" }
git remote remove origin 2>$null   # 不在本地残留 Token
Ok "已推送到 $Owner/$RepoName (main)"

# ---------- 4. 等待云编译 ----------
Step "触发 macOS 云编译"
Start-Sleep -Seconds 6
$runs = Invoke-RestMethod -Uri "$Api/repos/$Owner/$RepoName/actions/runs?per_page=5" -Headers $Headers -Method Get
$run = $runs.workflow_runs | Where-Object { $_.name -like "*Film Camera*" } | Select-Object -First 1
if (-not $run) {
    $wf = (Invoke-RestMethod -Uri "$Api/repos/$Owner/$RepoName/actions/workflows" -Headers $Headers -Method Get).workflows |
          Where-Object { $_.path -like "*build.yml*" } | Select-Object -First 1
    if (-not $wf) { throw "仓库里没找到 workflow，确认 .github/workflows/build.yml 已提交" }
    Invoke-RestMethod -Uri "$Api/repos/$Owner/$RepoName/actions/workflows/$($wf.id)/dispatches" -Headers $Headers -Method Post -Body (@{ ref = "main" } | ConvertTo-Json) -ContentType "application/json" | Out-Null
    Start-Sleep -Seconds 8
    $runs = Invoke-RestMethod -Uri "$Api/repos/$Owner/$RepoName/actions/runs?per_page=5" -Headers $Headers -Method Get
    $run = $runs.workflow_runs | Select-Object -First 1
}
Ok "任务 #$($run.run_number)  $($run.html_url)"

Write-Host "  云端正在装 XcodeGen + 编译，通常 3~6 分钟..." -ForegroundColor DarkGray
$deadline = (Get-Date).AddMinutes(30)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    $r = Invoke-RestMethod -Uri "$Api/repos/$Owner/$RepoName/actions/runs/$($run.id)" -Headers $Headers -Method Get
    Write-Host ("  状态: {0,-12} {1}" -f $r.status, $r.conclusion) -ForegroundColor DarkGray
    if ($r.status -eq "completed") { $run = $r; break }
}
if ($run.status -ne "completed") { throw "等待超时，请打开 $($run.html_url) 手动查看" }

function Save-Artifact($runId, $artifactName, $outFile) {
    $arts = (Invoke-RestMethod -Uri "$Api/repos/$Owner/$RepoName/actions/runs/$runId/artifacts" -Headers $Headers -Method Get).artifacts
    $art = $arts | Where-Object { $_.name -eq $artifactName } | Select-Object -First 1
    if (-not $art) { return $false }
    $resp = Invoke-WebRequest -Uri $art.archive_download_url -Headers $Headers -Method Get -MaximumRedirection 0 -ErrorAction SilentlyContinue
    $loc = $resp.Headers.Location
    if (-not $loc) { $loc = $art.archive_download_url; $tmpH = $Headers } else { $tmpH = @{} }
    Invoke-WebRequest -Uri $loc -Headers $tmpH -OutFile $outFile -UseBasicParsing
    return (Test-Path $outFile)
}

# ---------- 5. 取产物 ----------
if ($run.conclusion -ne "success") {
    Step "编译失败，拉取日志"
    $logZip = Join-Path $env:TEMP "hongsx-desk-xcodebuild-log.zip"
    if (Save-Artifact $run.id "RetroFilmCam-BuildLog" $logZip) {
        $logDir = Join-Path $env:TEMP "hongsx-desk-log"
        Remove-Item $logDir -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive $logZip -DestinationPath $logDir -Force
        $logFile = Get-ChildItem $logDir -Filter *.log -Recurse | Select-Object -First 1
        Write-Host "`n----- 编译错误 -----" -ForegroundColor Red
        Select-String -Path $logFile.FullName -Pattern "error:" | Select-Object -First 40 | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
        Write-Host "`n完整日志: $($logFile.FullName)" -ForegroundColor Yellow
    }
    throw "云端编译失败，把上面的 error 行发我。任务页: $($run.html_url)"
}

Step "下载 ipa"
$zipPath = Join-Path $env:TEMP "hongsx-desk-ipa.zip"
if (-not (Save-Artifact $run.id "RetroFilmCam-IPA" $zipPath)) { throw "没找到 ipa 产物" }
$outDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "RetroFilmCam-IPA"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Expand-Archive $zipPath -DestinationPath $outDir -Force
$ipa = Get-ChildItem $outDir -Filter *.ipa | Select-Object -First 1
if (-not $ipa) { throw "解压后没找到 .ipa" }

Ok "已生成: $($ipa.FullName)  ($([math]::Round($ipa.Length/1MB,1)) MB)"
Write-Host @"

下一步（签名安装）：
  1. 爱思助手 → 工具箱 → IPA 签名 → 使用证书签名
  2. 导入 .p12（含密码）+ .mobileprovision
  3. 添加 $($ipa.Name)，点「开始签名」
  4. 连手机 → 点「安装」
  或直接把 ipa 传手机，用万能签 / 轻松签签。
"@ -ForegroundColor Green
