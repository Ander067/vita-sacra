<?php
require_once __DIR__ . '/auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: ' . RUTA_WEB . '/Funciones/inicio.php');
    exit;
}

if (!verificarCSRF($_POST['csrf_token'] ?? '')) {
    http_response_code(403);
    exit('Solicitud no valida.');
}

cerrarSesion();

header('Location: ' . RUTA_WEB . '/Funciones/login.php');
exit;
?>
