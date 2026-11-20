<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereRol($mysqli, 'administrador');

function escaparModeracionComentarios($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

if (!isset($_SESSION['flash_moderacion_comentarios'])) {
    $_SESSION['flash_moderacion_comentarios'] = null;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $csrf = $_POST['csrf_token'] ?? '';

    if (!verificarCSRF($csrf)) {
        $_SESSION['flash_moderacion_comentarios'] = [
            'tipo' => 'error',
            'mensaje' => 'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/moderar_comentarios.php',
            true,
            303
        );
        exit;
    }

    $accion = $_POST['accion'] ?? '';
    $idRecibido = $_POST['id_com'] ?? null;
    $idComentario = is_scalar($idRecibido)
        ? filter_var(
            $idRecibido,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        )
        : false;

    $estadosPermitidos = [
        'aprobar' => 1,
        'ocultar' => 3
    ];

    if (
        !is_string($accion)
        || !isset($estadosPermitidos[$accion])
        || $idComentario === false
    ) {
        $_SESSION['flash_moderacion_comentarios'] = [
            'tipo' => 'error',
            'mensaje' => 'La acción solicitada no es válida.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/moderar_comentarios.php',
            true,
            303
        );
        exit;
    }

    $nuevoEstado = $estadosPermitidos[$accion];

    $actualizarComentario = $mysqli->prepare(
        "UPDATE comentarios
         SET estatus = ?
         WHERE id_com = ?
           AND estatus = 2"
    );

    $actualizarComentario->bind_param(
        'ii',
        $nuevoEstado,
        $idComentario
    );

    $actualizarComentario->execute();
    $actualizado = $actualizarComentario->affected_rows === 1;
    $actualizarComentario->close();

    if ($actualizado) {
        $mensaje = $accion === 'aprobar'
            ? 'El comentario fue aprobado y ya puede mostrarse públicamente.'
            : 'El comentario fue ocultado.';
        $tipo = 'exito';
    } else {
        $mensaje = 'El comentario ya no está pendiente o no se encontró.';
        $tipo = 'error';
    }

    $_SESSION['flash_moderacion_comentarios'] = [
        'tipo' => $tipo,
        'mensaje' => $mensaje
    ];

    header(
        'Location: ' . RUTA_WEB . '/Funciones/moderar_comentarios.php',
        true,
        303
    );
    exit;
}

$flash = $_SESSION['flash_moderacion_comentarios'];
unset($_SESSION['flash_moderacion_comentarios']);

$consultaPendientes = $mysqli->prepare(
    "SELECT
        c.id_com,
        c.comentario,
        c.fecha,
        u.nom_usr AS usuario,
        b.id_blog,
        b.titulo AS publicacion
     FROM comentarios c
     INNER JOIN usuario u
        ON u.id_usr = c.usr_id
     INNER JOIN blog b
        ON b.id_blog = c.blog_id
     WHERE c.estatus = 2
     ORDER BY c.fecha ASC, c.id_com ASC
     LIMIT 100"
);

$consultaPendientes->execute();
$comentarios = $consultaPendientes
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaPendientes->close();

$csrf = generarCSRF();

require_once __DIR__ . '/componentes/cabecera.php';

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta
        name="description"
        content="Revisa y modera los comentarios de Vita Sacra."
    >
    <title>Moderación de comentarios | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparModeracionComentarios(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        'Administración',
        'administrador',
        'comentarios',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Moderación de comentarios</h1>
                <p>
                    Revisa las participaciones pendientes antes de hacerlas
                    visibles en las publicaciones.
                </p>
            </div>

            <span class="insignia-admin">
                <?php echo count($comentarios); ?> pendientes
            </span>
        </section>

        <?php if (is_array($flash)): ?>
            <div
                class="<?php echo $flash['tipo'] === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>"
                role="status"
            >
                <?php echo escaparModeracionComentarios($flash['mensaje']); ?>
            </div>
        <?php endif; ?>

        <section class="seccion-admin" aria-labelledby="titulo-pendientes">
            <div class="encabezado-seccion-admin">
                <div>
                    <h2 id="titulo-pendientes">Pendientes de revisión</h2>
                    <p>
                        Aprobar muestra el comentario públicamente; ocultar
                        lo mantiene fuera de la publicación.
                    </p>
                </div>
            </div>

            <?php if ($comentarios === []): ?>
                <div class="tarjeta-actividad">
                    <h3>No hay comentarios pendientes</h3>
                    <p>La bandeja de moderación está al día.</p>
                </div>
            <?php else: ?>
                <div class="actividad-admin">
                    <?php foreach ($comentarios as $comentario): ?>
                        <article class="tarjeta-actividad">
                            <p>
                                <span class="estado estado-pendiente">
                                    Pendiente
                                </span>
                            </p>

                            <h3>
                                <?php
                                echo escaparModeracionComentarios(
                                    $comentario['publicacion']
                                );
                                ?>
                            </h3>

                            <p>
                                <strong>
                                    <?php
                                    echo escaparModeracionComentarios(
                                        $comentario['usuario']
                                    );
                                    ?>
                                </strong>
                                ·
                                <?php
                                $marcaTiempo = strtotime($comentario['fecha']);
                                echo $marcaTiempo === false
                                    ? 'Fecha no disponible'
                                    : escaparModeracionComentarios(
                                        date('d/m/Y H:i', $marcaTiempo)
                                    );
                                ?>
                            </p>

                            <p>
                                <?php
                                echo nl2br(
                                    escaparModeracionComentarios(
                                        $comentario['comentario']
                                    )
                                );
                                ?>
                            </p>

                            <p>
                                <a
                                    href="<?php echo escaparModeracionComentarios(RUTA_WEB); ?>/Funciones/ver_publicacion.php?id=<?php echo (int)$comentario['id_blog']; ?>#comentarios"
                                >
                                    Ver publicación
                                </a>
                            </p>

                            <div class="enlaces">
                                <form method="POST">
                                    <input
                                        type="hidden"
                                        name="csrf_token"
                                        value="<?php echo escaparModeracionComentarios($csrf); ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="id_com"
                                        value="<?php echo (int)$comentario['id_com']; ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="accion"
                                        value="aprobar"
                                    >
                                    <p>
                                        <button class="boton" type="submit">
                                            Aprobar
                                        </button>
                                    </p>
                                </form>

                                <form method="POST">
                                    <input
                                        type="hidden"
                                        name="csrf_token"
                                        value="<?php echo escaparModeracionComentarios($csrf); ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="id_com"
                                        value="<?php echo (int)$comentario['id_com']; ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="accion"
                                        value="ocultar"
                                    >
                                    <p>
                                        <button
                                            class="boton boton-secundario"
                                            type="submit"
                                        >
                                            Ocultar
                                        </button>
                                    </p>
                                </form>
                            </div>
                        </article>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
        </section>
    </main>

    <footer class="pie-admin">
        <p>Vita Sacra · Moderación responsable de la comunidad.</p>
    </footer>
    <script
        src="<?php echo htmlspecialchars(RUTA_WEB, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>