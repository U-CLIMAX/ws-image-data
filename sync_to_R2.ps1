# ============================================
# WS Image Sync Script with User Controls
# ============================================

$localFolder = "E:\CF_R2\ws-image-data"
$localBlurFolder = "E:\CF_R2\ws-blur-image-data"
$bucket = "ws-image-data"
$bucketBlur = "ws-blur-image-data"

function Ask($question) {
    Write-Host "$question (Y/N): " -NoNewline -ForegroundColor Yellow
    return Read-Host
}

function Info($msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Success($msg) {
    Write-Host "[OK]   $msg" -ForegroundColor Green
}

function ErrorMsg($msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

# ====== User Inputs ======
$uploadMain = Ask "是否上傳原圖到 S3（bucket: $bucket）？"
$uploadBlur = Ask "是否上傳模糊圖到 S3（bucket: $bucketBlur）？"
$pushGit = Ask "是否執行 Git 推送？"

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


# ===== Step 1. Sync Main Images =====
if ($uploadMain -match "^[Yy]$") {
    Info "開始同步原圖到 S3..."
    aws s3 sync $localFolder s3://$bucket/ --cache-control "public, max-age=31536000, immutable" --delete
    if ($LASTEXITCODE -eq 0) { Success "原圖同步完成。" } else { ErrorMsg "原圖同步失敗！"; exit 1 }
} else {
    Info "跳過原圖同步。"
}

# ===== Step 2. Sync Blur Images =====
if ($uploadBlur -match "^[Yy]$") {
    Info "開始同步縮圖到 S3..."
    aws s3 sync $localBlurFolder  s3://$bucketBlur/ --cache-control "public, max-age=31536000, immutable" --delete
    if ($LASTEXITCODE -eq 0) { Success "模糊圖同步完成。" } else { ErrorMsg "模糊圖同步失敗！"; exit 1 }
} else {
    Info "跳過模糊圖同步。"
}

# ===== Step 3. Git Push =====
if ($pushGit -match "^[Yy]$") {
    Info "開始 Git 提交與推送..."
    git add .
    git commit -m "chore: update image"
    git push

    if ($LASTEXITCODE -eq 0) { Success "Git 推送完成。" } else { ErrorMsg "Git 推送失敗！"; exit 1 }
} else {
    Info "跳過 Git 推送。"
}

Success "全部作業流程完成!"
