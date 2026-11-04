# Obtener la IPv4 de la red utilizada para salir a Internet.
$ip = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" |
    Sort-Object RouteMetric |
    ForEach-Object {
        Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 |
            Where-Object {
                $_.IPAddress -notlike "169.254.*" -and
                $_.IPAddress -ne "127.0.0.1"
            }
    } |
    Select-Object -First 1 -ExpandProperty IPAddress

# Comprobar que se encontro una direccion.
if (-not $ip) {
    Write-Host "No se pudo detectar la direccion IPv4."
    exit 1
}

# Construir la direccion del servidor.
$url = "http://${ip}:8000"

Write-Host "IPv4 detectada: $ip"
Write-Host "Servidor FastAPI: $url"

# Ejecutar Flutter con la IP detectada.
flutter run -d 64f4488 --dart-define="API_BASE_URL=$url"

# Cada cambio de red ejecutar.\iniciar_flutter.ps1