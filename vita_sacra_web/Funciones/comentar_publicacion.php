<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    exit('Método no permitido.');
}

$idRecibido = $_POST['id_blog'] ?? null;
$idBlog = is_scalar($idRecibido)
    ? filter_var(
        $idRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

if ($idBlog === false) {
    http_response_code(400);
    exit('La publicación indicada no es válida.');
}

$destino = RUTA_WEB
    . '/Funciones/ver_publicacion.php?id='
    . (int)$idBlog
    . '#comentarios';

if (!verificarUsuarioActual($mysqli)) {
    $_SESSION['flash_comentario'] = [
        'tipo' => 'error',
        'mensaje' => 'Inicia sesión para publicar un comentario.'
    ];

    header(
        'Location: ' . RUTA_WEB . '/Funciones/login.php',
        true,
        303
    );
    exit;
}

$csrf = $_POST['csrf_token'] ?? '';

if (!verificarCSRF($csrf)) {
    $_SESSION['flash_comentario'] = [
        'tipo' => 'error',
        'mensaje' => 'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
    ];

    header('Location: ' . $destino, true, 303);
    exit;
}

$comentarioRecibido = $_POST['comentario'] ?? '';
$comentario = is_string($comentarioRecibido)
    ? trim($comentarioRecibido)
    : '';

if ($comentario === '') {
    $_SESSION['flash_comentario'] = [
        'tipo' => 'error',
        'mensaje' => 'Escribe un comentario antes de enviarlo.'
    ];

    header('Location: ' . $destino, true, 303);
    exit;
}

if (mb_strlen($comentario, 'UTF-8') > 3000) {
    $_SESSION['flash_comentario'] = [
        'tipo' => 'error',
        'mensaje' => 'El comentario no puede superar los 3000 caracteres.'
    ];

    header('Location: ' . $destino, true, 303);
    exit;
}

$idUsuario = (int)$_SESSION['id_usr'];

$insertarComentario = $mysqli->prepare(
    "INSERT INTO comentarios (comentario, estatus, usr_id, blog_id)
     SELECT ?, 2, ?, bp.id_blog
     FROM blog_publico bp
     WHERE bp.id_blog = ?
     LIMIT 1"
);

$insertarComentario->bind_param(
    'sii',
    $comentario,
    $idUsuario,
    $idBlog
);

$insertarComentario->execute();
$insertado = $insertarComentario->affected_rows === 1;
$insertarComentario->close();

if (!$insertado) {
    $_SESSION['flash_comentario'] = [
        'tipo' => 'error',
        'mensaje' => 'La publicación ya no está disponible para comentar.'
    ];
} else {
    $_SESSION['flash_comentario'] = [
        'tipo' => 'exito',
        'mensaje' => 'Tu comentario fue enviado y está pendiente de revisión.'
    ];
}

header('Location: ' . $destino, true, 303);
exit;