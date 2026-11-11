# ============================================================
# 智慧校园管理平台 V1.0 —— 部署后冒烟测试
#
# 用法（在 project 目录下执行）：
#   powershell -ExecutionPolicy Bypass -File test-e2e.ps1
#
# 前置条件：
#   1. Docker Desktop 已启动，容器组 school-platform 已 up -d
#   2. 初始化脚本已按 01 → 13 顺序执行完毕
#
# 测试内容：
#   登录鉴权 → 会话与角色 → 读取学校 → 新增并删除临时学校 → 人员与学校联查
# 说明：写权限用一所临时学校（学校代码 SCH006）验证，结束时自动删除，不在库中留数据。
# ============================================================
$ErrorActionPreference = 'Continue'

$base = 'http://127.0.0.1:8000'

# ---- anon key：优先环境变量，其次从运行中的 auth 容器读取 ----
# 该密钥是发给浏览器的公开客户端密钥，并非服务端机密。
$apikey = $env:SUPABASE_ANON_KEY
if ([string]::IsNullOrWhiteSpace($apikey)) {
    $apikey = (docker exec supabase-auth printenv GOTRUE_ANON_KEY 2>$null) -join ''
}
$apikey = "$apikey".Trim()
if ([string]::IsNullOrWhiteSpace($apikey)) {
    Write-Host '[FAIL] 未能获取 anon key，请确认容器 supabase-auth 正在运行' -ForegroundColor Red
    exit 1
}

# ---- 请求体写入系统临时目录，不依赖任何固定的开发机路径 ----
$tmp       = [System.IO.Path]::GetTempPath()
$loginBody = Join-Path $tmp 'school-smoke-login.json'
$postBody  = Join-Path $tmp 'school-smoke-post.json'
$utf8      = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($loginBody, '{"email":"admin@demo.com","password":"123456"}', $utf8)
[System.IO.File]::WriteAllText($postBody, '{"school_name":"冒烟测试学校","name":"冒烟测试学校","school_code":"SCH006"}', $utf8)

# ---- 统一发请求：把 curl 输出拼成单个字符串 ----
# PowerShell 捕获外部命令输出会按行拆成数组，某些控制台下还会按窗口宽度硬折行，
# 直接交给 ConvertFrom-Json 会解析失败；这里统一拼回一行，再用正则取值。
function Invoke-Curl([string[]]$curlArgs) {
    return ((& curl.exe @curlArgs) -join '')
}

$pass = 0
$fail = 0
function Check($name, $ok, $detail) {
    if ($ok) { $script:pass++; Write-Host "[PASS] $name  $detail" -ForegroundColor Green }
    else { $script:fail++; Write-Host "[FAIL] $name  $detail" -ForegroundColor Red }
}

Write-Host '=== 1. 登录鉴权 ==='
$loginResp = Invoke-Curl @('-s', '-X', 'POST', "$base/auth/v1/token?grant_type=password",
    '-H', 'Content-Type: application/json', '-H', "apikey: $apikey", '-d', "@$loginBody")
$token = $null
if ($loginResp -match '"access_token"\s*:\s*"([^"]+)"') { $token = $Matches[1] }
$tokenLen = 0
if ($token) { $tokenLen = $token.Length }
Check '管理员登录返回 access_token' ($tokenLen -gt 0) "token 长度=$tokenLen"
if (-not $token) {
    Write-Host '登录失败，后续用例无法继续。原始响应：' -ForegroundColor Red
    Write-Host $loginResp
    Write-Host ''
    Write-Host "结果：$pass 项通过，$fail 项失败"
    exit 1
}
$auth = "Authorization: Bearer $token"
$hdr = @('-H', "apikey: $apikey", '-H', $auth)

Write-Host ''
Write-Host '=== 2. 会话与角色 ==='
$who = Invoke-Curl (@('-s', "$base/auth/v1/user") + $hdr)
Check '会话有效且角色为 sys_admin' ($who -match '"role"\s*:\s*"sys_admin"') "$who"

Write-Host ''
Write-Host '=== 3. 读取业务数据 ==='
$schools = Invoke-Curl (@('-s', "$base/rest/v1/schools?select=school_name&order=school_code") + $hdr)
Check 'schools 表可读' ($schools -match 'school_name') "$schools"

Write-Host ''
Write-Host '=== 4. 写入与删除（临时学校 SCH006） ==='
$created = Invoke-Curl (@('-s', '-X', 'POST', "$base/rest/v1/schools") + $hdr +
    @('-H', 'Content-Type: application/json', '-H', 'Prefer: return=representation', '-d', "@$postBody"))
Check '新增学校成功' ($created -match 'SCH006') "$created"
Invoke-Curl (@('-s', '-X', 'DELETE', "$base/rest/v1/schools?school_code=eq.SCH006") + $hdr) | Out-Null
$left = Invoke-Curl (@('-s', "$base/rest/v1/schools?select=school_code&school_code=eq.SCH006") + $hdr)
Check '删除临时学校成功（复查为空）' ("$left".Trim() -eq '[]') "复查=$left"

Write-Host ''
Write-Host '=== 5. 人员与学校联查 ==='
$profiles = Invoke-Curl (@('-s', "$base/rest/v1/profiles?select=real_name,role,schools(name)&role=eq.sys_admin") + $hdr)
Check 'profiles 外键联查可用' ($profiles -match 'sys_admin') "$profiles"

Write-Host ''
Write-Host '============================================================'
Write-Host " 结果：$pass 项通过，$fail 项失败"
Write-Host '============================================================'
if ($fail -gt 0) { exit 1 }
