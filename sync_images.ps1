# ============================================
# WS Image Sync Script with User Controls
# ============================================
$localFolder     = "E:\CF_R2\ws-image-data"
$localBlurFolder = "E:\CF_R2\ws-blur-image-data"
$remoteR2        = "ws-r2"
$remoteOSS       = "ws-oss"
$bucket          = "ws-image-data"
$bucketBlur      = "ws-blur-image-data"

# rclone 共用參數
$rcloneFlags = @(
    "--transfers", "32",
    "--checkers", "20",
    "--header-upload", "Cache-Control: public, max-age=31536000, immutable",
    "--progress"
)

function Ask($question) {
    Write-Host "$question (Y/N): " -NoNewline -ForegroundColor Yellow
    return Read-Host
}
function Info($msg)    { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Success($msg) { Write-Host "[OK]   $msg" -ForegroundColor Green }
function ErrorMsg($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

# ====== User Inputs ======
$pushGit       = Ask "是否執行 Git 推送？"
$uploadR2Main  = Ask "是否上傳原圖到 R2（${remoteR2}:${bucket}）？"
$uploadR2Blur  = Ask "是否上傳模糊圖到 R2（${remoteR2}:${bucketBlur}）？"
$uploadOSSMain = Ask "是否上傳原圖到阿里雲 OSS（${remoteOSS}:${bucket}）？"
$uploadOSSBlur = Ask "是否上傳模糊圖到阿里雲 OSS（${remoteOSS}:${bucketBlur}）？"

# 上傳模式選擇
$uploadMode = ""
$needUpload = ($uploadR2Main -match "^[Yy]$") -or
              ($uploadR2Blur -match "^[Yy]$") -or
              ($uploadOSSMain -match "^[Yy]$") -or
              ($uploadOSSBlur -match "^[Yy]$")

if ($needUpload) {
    Write-Host "選擇上傳模式：" -ForegroundColor Yellow
    Write-Host "  [1] 快速模式 - 只傳新增檔案，忽略遠端已存在的（ignore-existing）" -ForegroundColor White
    Write-Host "  [2] 完整同步 - 同步本地與遠端，刪除遠端多餘檔案（sync）" -ForegroundColor White
    Write-Host "請輸入 1 或 2: " -NoNewline -ForegroundColor Yellow
    $uploadMode = Read-Host
}

# ===== Step 0. Check WebP Count =====
function Get-WebpCount($path) {
    if (-not (Test-Path $path)) {
        ErrorMsg "資料夾不存在: $path"
        exit 1
    }
    return (Get-ChildItem -Path $path -Recurse -Filter *.webp -File | Measure-Object).Count
}

Info "檢查 webp 圖片數量是否一致..."
$mainCount = Get-WebpCount $localFolder
$blurCount = Get-WebpCount $localBlurFolder
Info "原圖數量: $mainCount"
Info "模糊圖數量: $blurCount"

if ($mainCount -ne $blurCount) {
    ErrorMsg "webp 數量不一致，開始執行 generate_blur.py..."
    uv run generate_blur.py
    if ($LASTEXITCODE -ne 0) {
        ErrorMsg "generate_blur.py 執行失敗，中斷流程"
        exit 1
    }
    Info "重新檢查 webp 圖片數量..."
    $mainCountAfter = Get-WebpCount $localFolder
    $blurCountAfter = Get-WebpCount $localBlurFolder
    Info "原圖數量（after）: $mainCountAfter"
    Info "模糊圖數量（after）: $blurCountAfter"
    if ($mainCountAfter -ne $blurCountAfter) {
        ErrorMsg "webp 數量仍不一致，流程中斷"
        exit 1
    }
    Success "webp 數量已一致，繼續執行後續流程"
} else {
    Success "webp 數量一致，跳過 generate_blur.py"
}

# ===== Step 1. Git Push =====
if ($pushGit -match "^[Yy]$") {
    Info "開始 Git 提交與推送..."
    git add .
    git commit -m "chore: update image"
    git push
    if ($LASTEXITCODE -eq 0) { Success "Git 推送完成。" } else { ErrorMsg "Git 推送失敗！"; exit 1 }
} else {
    Info "跳過 Git 推送。"
}

# ===== 上傳函式 =====
function Invoke-Upload($label, $localPath, $remotePath) {
    if ($uploadMode -eq "1") {
        Info "[$label] 快速模式：只上傳新增檔案..."
        rclone copy $localPath $remotePath --ignore-existing @rcloneFlags
    } else {
        Info "[$label] 完整同步：同步並刪除遠端多餘檔案..."
        rclone sync $localPath $remotePath @rcloneFlags
    }

    if ($LASTEXITCODE -eq 0) {
        Success "[$label] 上傳完成。"
    } else {
        ErrorMsg "[$label] 上傳失敗！"
        exit 1
    }
}

# ===== Step 2. Upload Main Images to R2 =====
if ($uploadR2Main -match "^[Yy]$") {
    Invoke-Upload "R2 原圖" $localFolder "${remoteR2}:${bucket}"
} else {
    Info "跳過 R2 原圖上傳。"
}

# ===== Step 3. Upload Blur Images to R2 =====
if ($uploadR2Blur -match "^[Yy]$") {
    Invoke-Upload "R2 模糊圖" $localBlurFolder "${remoteR2}:${bucketBlur}"
} else {
    Info "跳過 R2 模糊圖上傳。"
}

# ===== Step 4. Upload Main Images to OSS =====
if ($uploadOSSMain -match "^[Yy]$") {
    Invoke-Upload "OSS 原圖" $localFolder "${remoteOSS}:${bucket}"
} else {
    Info "跳過 OSS 原圖上傳。"
}

# ===== Step 5. Upload Blur Images to OSS =====
if ($uploadOSSBlur -match "^[Yy]$") {
    Invoke-Upload "OSS 模糊圖" $localBlurFolder "${remoteOSS}:${bucketBlur}"
} else {
    Info "跳過 OSS 模糊圖上傳。"
}

Success "全部作業流程完成!"