<?php

require_once __DIR__ . '/../vendor/autoload.php';

$directorioBackend = dirname(__DIR__, 2)
    . DIRECTORY_SEPARATOR
    . 'backend';

try {
    \Dotenv\Dotenv::createImmutable($directorioBackend)->load();
} catch (\Dotenv\Exception\ExceptionInterface $error) {
    error_log('Vita Sacra: no se pudo cargar la configuración.');
    http_response_code(500);
    exit('El servicio no está disponible en este momento.');
}

$leer = static function (string $nombre): ?string {
    $valor = $_ENV[$nombre] ?? $_SERVER[$nombre] ?? getenv($nombre);
    return is_string($valor) ? $valor : null;
};

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

$host = $leer('DB_HOST');
$baseDatos = $leer('DB_NAME');
$usuario = $leer('DB_USER');
$contrasena = $leer('DB_PASSWORD');

$puerto = filter_var(
    $leer('DB_PORT'),
    FILTER_VALIDATE_INT,
    [
        'options' => [
            'min_range' => 1,
            'max_range' => 65535
        ]
    ]
);

if (
    !is_string($host) ||
    trim($host) === '' ||
    !is_string($baseDatos) ||
    trim($baseDatos) === '' ||
    !is_string($usuario) ||
    trim($usuario) === '' ||
    !is_string($contrasena) ||
    $contrasena === '' ||
    $puerto === false
) {
    error_log('Vita Sacra: falta configurar la conexión MySQL.');
    http_response_code(500);
    exit('El servicio no está disponible en este momento.');
}

try {
    $mysqli = new mysqli(
        trim($host),
        trim($usuario),
        $contrasena,
        trim($baseDatos),
        $puerto
    );

    $mysqli->set_charset('utf8mb4');
} catch (mysqli_sql_exception $error) {
    error_log(
        'Vita Sacra: error de conexión MySQL, código ' .
        $error->getCode()
    );

    http_response_code(500);
    exit('El servicio no está disponible en este momento.');
}