param([string]$File = "$PSScriptRoot/../requests.http")

# PowerShell 7: додаткова автоматична перевірка тих самих 10 блоків requests.http.
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $File -Raw
$baseMatch = [regex]::Match($source, '(?m)^@baseUrl\s*=\s*(\S+)')
if (-not $baseMatch.Success) { throw 'Не задано @baseUrl.' }
$baseUrl = $baseMatch.Groups[1].Value
$responses = @{}
$report = [Collections.Generic.List[string]]::new()
$report.Add("Час: $([DateTimeOffset]::Now.ToString('O'))")
$report.Add('Автоматичне виконання запитів саме з requests.http; окремо від інтерфейсу REST Client.')
$count = 0

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) { throw "$Message. Очікується $Expected, отримано $Actual" }
}

foreach ($block in [regex]::Split($source, '(?m)^###')) {
    $requestMatch = [regex]::Match($block, '(?m)^(GET|POST|PUT|DELETE)\s+(\S+)\s*$')
    if (-not $requestMatch.Success) { continue }
    $nameMatch = [regex]::Match($block, '(?m)^# @name\s+(\w+)')
    if (-not $nameMatch.Success) { throw 'У запиту немає імені.' }
    $name = $nameMatch.Groups[1].Value
    $method = $requestMatch.Groups[1].Value
    $uri = $requestMatch.Groups[2].Value.Replace('{{baseUrl}}', $baseUrl)
    if ($uri.Contains('{{createPosting.response.body.$.id}}')) {
        if (-not $responses.ContainsKey('createPosting')) { throw 'Спочатку потрібен POST createPosting.' }
        $uri = $uri.Replace('{{createPosting.response.body.$.id}}', [string]$responses['createPosting'].Json.id)
    }
    $afterRequest = $block.Substring($requestMatch.Index + $requestMatch.Length).TrimStart("`r", "`n")
    $bodyMatch = [regex]::Match($afterRequest, '(?s)\r?\n\s*\r?\n(.*)$')
    $body = if ($bodyMatch.Success) { $bodyMatch.Groups[1].Value.Trim() } else { '' }
    $parameters = @{ Uri = $uri; Method = $method; SkipHttpErrorCheck = $true }
    if ($method -in @('POST','PUT')) {
        if ($afterRequest -notmatch '(?im)^Content-Type:\s*application/json') { throw 'Для тіла потрібен Content-Type.' }
        $parameters.ContentType = 'application/json; charset=utf-8'
        $parameters.Body = [Text.Encoding]::UTF8.GetBytes($body)
    }
    $response = Invoke-WebRequest @parameters
    $text = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
    $json = if ($text.Length -gt 0) { $text | ConvertFrom-Json } else { $null }
    $status = [int]$response.StatusCode
    $responses[$name] = [pscustomobject]@{ Status = $status; Json = $json; Text = $text }
    $expected = switch ($name) {
        'getMissing' { 404 }
        'createPosting' { 201 }
        'deletePosting' { 204 }
        'getAfterDelete' { 404 }
        default { 200 }
    }
    Assert-Equal $expected $status "Статус $name"
    if ($status -in @(200,201) -and [string]$response.Headers['Content-Type'] -notmatch '^application/json') { throw 'Очікується JSON.' }
    switch ($name) {
        'listBefore' { if (@($json).Count -lt 3) { throw 'Очікується початковий список.' } }
        'getExisting' { Assert-Equal 1 $json.id 'Існуючий Id' }
        'createPosting' {
            Assert-Equal ("/postings/" + $json.id) ([string]$response.Headers['Location']) 'Location'
            Assert-Equal 'Department' $json.deliveryType 'Тип доставки після POST'
        }
        'listAfterCreate' {
            Assert-Equal (@($responses['listBefore'].Json).Count + 1) @($json).Count 'Розмір списку після POST'
            $found = @($json | Where-Object id -eq $responses['createPosting'].Json.id)
            Assert-Equal 1 $found.Count 'Новий запис у списку'
        }
        'getBeforeUpdate' { Assert-Equal 'Documents' $json.content 'Початковий вміст' }
        'updatePosting' {
            Assert-Equal 'Documents (updated)' $json.content 'Змінений вміст'
            Assert-Equal 'Courier' $json.deliveryType 'Змінений спосіб доставки'
            Assert-Equal 0.6 $json.weight 'Змінена вага'
            Assert-Equal 120 $json.value 'Змінена цінність'
            Assert-Equal 20 $json.price 'Змінена ціна'
            Assert-Equal $responses['createPosting'].Json.id $json.id 'Незмінний Id'
            Assert-Equal $responses['createPosting'].Json.createdAt $json.createdAt 'Незмінний час створення'
        }
        'getAfterUpdate' { Assert-Equal $responses['updatePosting'].Text $text 'Збережені зміни після PUT' }
        'deletePosting' { Assert-Equal '' $text 'Порожнє тіло відповіді 204' }
    }
    $count++
    $report.Add("`n$('{0:D2}' -f $count). $name — $method $uri")
    $report.Add("HTTP $status")
    if ($response.Headers['Location']) { $report.Add("Location: $($response.Headers['Location'] -join ', ')") }
    if ($response.Headers['Content-Type']) { $report.Add("Content-Type: $($response.Headers['Content-Type'] -join ', ')") }
    if ($text.Length -gt 0) { $report.Add($text) }
    $report.Add("PASS: $name")
}
Assert-Equal 10 $count 'Кількість виконаних запитів'
$report.Add("`nУспішно: $count/10 запитів із requests.http.")
$reportFolder = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../reports'))
New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null
$report | Set-Content -LiteralPath (Join-Path $reportFolder 'http-results.txt') -Encoding utf8
$report | Where-Object { $_ -match '^PASS|^Успішно' }
