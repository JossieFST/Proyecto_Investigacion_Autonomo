# Envía un POST con JSON; usuario y clave son para la autenticación básica
function Probar($url, $json, $usuario, $clave) {
  $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${usuario}:${clave}"))
  $cuerpo = [Text.Encoding]::UTF8.GetBytes($json)
  try {
    $r = Invoke-WebRequest -Method Post -Uri $url -ContentType "application/json; charset=utf-8" `
         -Body $cuerpo -Headers @{Authorization="Basic $auth"} -UseBasicParsing
    $codigo = $r.StatusCode
    $texto = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  } catch {
    $resp = $_.Exception.Response
    $codigo = [int]$resp.StatusCode
    $texto = (New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd()
  }
  "$codigo $texto"
}

# Envía un GET con autenticación básica
function Consultar($url, $usuario, $clave) {
  $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${usuario}:${clave}"))
  try {
    $r = Invoke-WebRequest -Uri $url -Headers @{Authorization="Basic $auth"} -UseBasicParsing
    "$($r.StatusCode) " + [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  } catch {
    "$([int]$_.Exception.Response.StatusCode)"
  }
}
