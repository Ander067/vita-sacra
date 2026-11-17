<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereUsuarioActual($mysqli);

$idUsuario = (int)$_SESSION['id_usr'];

$consulta = $mysqli->prepare(
    "SELECT id_usr, nom_usr, mail, tip_usu, version_sesion
     FROM usuario
     WHERE id_usr = ?
       AND estatus = 'activo'
     LIMIT 1"
);

$consulta->bind_param('i', $idUsuario);
$consulta->execute();
$usuario = $consulta->get_result()->fetch_assoc();
$consulta->close();

if (
    !$usuario ||
    (int)$usuario['version_sesion'] !== (int)$_SESSION['version_sesion']
) {
    cerrarSesion();

    header('Location: ' . RUTA_WEB . '/Funciones/login.php');
    exit;
}

$_SESSION['nom_usr'] = $usuario['nom_usr'];
$_SESSION['mail'] = $usuario['mail'];
$_SESSION['tip_usu'] = (int)$usuario['tip_usu'];

$rolesActuales = obtenerRolesActuales($mysqli);
$_SESSION['roles_actuales'] = $rolesActuales;

if (in_array('administrador', $rolesActuales, true)) {
    header(
        'Location: ' . RUTA_WEB . '/Dashboards/dashboard_admin.php',
        true,
        303
    );
    exit;
}

if (in_array('autor', $rolesActuales, true)) {
    header(
        'Location: ' . RUTA_WEB . '/Dashboards/dashboard_autor.php',
        true,
        303
    );
    exit;
}

header(
    'Location: ' . RUTA_WEB . '/Dashboards/dashboard_visor.php',
    true,
    303
);
exit;
