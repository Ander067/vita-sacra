<?php

require_once __DIR__ . '/Conexiones/auth.php';
require_once __DIR__ . '/Conexiones/conexion.php';

if (isset($_SESSION['id_usr'])) {
    requiereUsuarioActual($mysqli);

    header('Location: ' . RUTA_WEB . '/Funciones/inicio.php');
    exit;
}

header('Location: ' . RUTA_WEB . '/Funciones/login.php');
exit;

?>
