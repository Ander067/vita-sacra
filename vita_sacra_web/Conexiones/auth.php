<?php

$directoriosModulo = ['Conexiones', 'Funciones', 'Dashboards'];
$directorioActual = str_replace(
    '\\',
    '/',
    dirname($_SERVER['SCRIPT_NAME'] ?? '/')
);

if (in_array(basename($directorioActual), $directoriosModulo, true)) {
    $directorioActual = dirname($directorioActual);
}

$rutaWeb = rtrim($directorioActual, '/');

if ($rutaWeb === '.') {
    $rutaWeb = '';
}

if (!defined('RUTA_WEB')) {
    define('RUTA_WEB', $rutaWeb);
}

if (!defined('TIEMPO_SESION')) {
    define('TIEMPO_SESION', 1800);
}

$https = !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';

$rutaCookie = RUTA_WEB === ''
    ? '/'
    : rtrim(str_replace(' ', '%20', RUTA_WEB), '/') . '/';

ini_set('session.use_strict_mode', '1');
ini_set('session.use_only_cookies', '1');
ini_set('session.use_trans_sid', '0');

session_name('VitaSacraSession');

session_set_cookie_params([
    'lifetime' => 0,
    'path' => $rutaCookie,
    'domain' => '',
    'secure' => $https,
    'httponly' => true,
    'samesite' => 'Lax'
]);

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

function verificarSesion(): bool
{
    if (
        session_status() !== PHP_SESSION_ACTIVE ||
        !isset($_SESSION['id_usr'])
    ) {
        return false;
    }

    $ultimaActividad = filter_var(
        $_SESSION['ultima_actividad'] ?? null,
        FILTER_VALIDATE_INT
    );

    if (
        $ultimaActividad === false ||
        time() - $ultimaActividad >= TIEMPO_SESION
    ) {
        cerrarSesion();
        return false;
    }

    $_SESSION['ultima_actividad'] = time();

    return true;
}

function requiereLogin(): void
{
    if (!verificarSesion()) {
        header('Location: ' . RUTA_WEB . '/Funciones/login.php');
        exit;
    }
}

function generarCSRF(): string
{
    if (
        !isset($_SESSION['csrf_token']) ||
        !is_string($_SESSION['csrf_token']) ||
        $_SESSION['csrf_token'] === ''
    ) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }

    return $_SESSION['csrf_token'];
}

function regenerarCSRF(): string
{
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));

    return $_SESSION['csrf_token'];
}

function verificarCSRF($token): bool
{
    return isset($_SESSION['csrf_token'])
        && is_string($_SESSION['csrf_token'])
        && is_string($token)
        && hash_equals($_SESSION['csrf_token'], $token);
}

function cerrarSesion(): void
{
    if (session_status() !== PHP_SESSION_ACTIVE) {
        return;
    }

    $_SESSION = [];

    if (ini_get('session.use_cookies')) {
        $parametros = session_get_cookie_params();

        setcookie(session_name(), '', [
            'expires' => time() - 42000,
            'path' => $parametros['path'],
            'domain' => $parametros['domain'],
            'secure' => $parametros['secure'],
            'httponly' => $parametros['httponly'],
            'samesite' => 'Lax'
        ]);
    }

    session_destroy();
}

function verificarUsuarioActual(mysqli $mysqli): bool
{
    if (!verificarSesion()) {
        return false;
    }

    $idUsuario = filter_var(
        $_SESSION['id_usr'],
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );

    if ($idUsuario === false) {
        cerrarSesion();
        return false;
    }

    $consulta = $mysqli->prepare(
        "SELECT estatus, version_sesion
         FROM usuario
         WHERE id_usr = ?
         LIMIT 1"
    );

    $consulta->bind_param('i', $idUsuario);
    $consulta->execute();
    $usuario = $consulta->get_result()->fetch_assoc();
    $consulta->close();

    if (
        !$usuario ||
        $usuario['estatus'] !== 'activo' ||
        !isset($_SESSION['version_sesion']) ||
        (int)$usuario['version_sesion'] !== (int)$_SESSION['version_sesion']
    ) {
        cerrarSesion();
        return false;
    }

    return true;
}

function requiereUsuarioActual(mysqli $mysqli): void
{
    if (!verificarUsuarioActual($mysqli)) {
        header('Location: ' . RUTA_WEB . '/Funciones/login.php');
        exit;
    }
}

function obtenerRolesActuales(mysqli $mysqli): array
{
    $idUsuario = (int)$_SESSION['id_usr'];

    $consulta = $mysqli->prepare(
        "SELECT LOWER(r.nombre) AS nombre
         FROM usuario u
         INNER JOIN roles r ON r.id_rol = u.tip_usu
         WHERE u.id_usr = ?
           AND u.estatus = 'activo'

         UNION

         SELECT LOWER(r.nombre) AS nombre
         FROM usuario_roles ur
         INNER JOIN usuario u ON u.id_usr = ur.usr_id
         INNER JOIN roles r ON r.id_rol = ur.rol_id
         WHERE ur.usr_id = ?
           AND u.estatus = 'activo'"
    );

    $consulta->bind_param('ii', $idUsuario, $idUsuario);
    $consulta->execute();
    $resultado = $consulta->get_result();

    $roles = [];

    while ($fila = $resultado->fetch_assoc()) {
        $roles[] = strtolower(trim($fila['nombre']));
    }

    $consulta->close();

    return array_values(array_unique($roles));
}

function requiereRol(mysqli $mysqli, string ...$rolesPermitidos): void
{
    requiereUsuarioActual($mysqli);

    $rolesPermitidos = array_values(array_filter(
        array_map(
            static fn(string $rol): string => strtolower(trim($rol)),
            $rolesPermitidos
        ),
        static fn(string $rol): bool => $rol !== ''
    ));

    if ($rolesPermitidos === []) {
        throw new InvalidArgumentException(
            'Debes especificar al menos un rol permitido.'
        );
    }

    $rolesActuales = obtenerRolesActuales($mysqli);

    if (array_intersect($rolesActuales, $rolesPermitidos) === []) {
        http_response_code(403);
        exit('No tienes permisos para acceder a esta sección.');
    }
}