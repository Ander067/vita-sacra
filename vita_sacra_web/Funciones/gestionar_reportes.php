<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereRol($mysqli, 'administrador');

function escaparGestionReportes($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

$administradorId = (int)$_SESSION['id_usr'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!verificarCSRF($_POST['csrf_token'] ?? '')) {
        $_SESSION['flash_gestion_reportes'] = [
            'tipo' => 'error',
            'mensaje' => 'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/gestionar_reportes.php',
            true,
            303
        );
        exit;
    }

    $accionRecibida = $_POST['accion'] ?? '';
    $accion = is_string($accionRecibida) ? $accionRecibida : '';

    $idRecibido = $_POST['id_reporte'] ?? null;
    $idReporte = is_scalar($idRecibido)
        ? filter_var(
            $idRecibido,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        )
        : false;

    $estados = [
        'resolver' => 'resuelto',
        'descartar' => 'descartado'
    ];

    if (!isset($estados[$accion]) || $idReporte === false) {
        $_SESSION['flash_gestion_reportes'] = [
            'tipo' => 'error',
            'mensaje' => 'La acción solicitada no es válida.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/gestionar_reportes.php',
            true,
            303
        );
        exit;
    }

    $resolucionRecibida = $_POST['resolucion'] ?? '';
    $resolucion = is_string($resolucionRecibida)
        ? trim($resolucionRecibida)
        : '';

    if (mb_strlen($resolucion, 'UTF-8') > 2000) {
        $_SESSION['flash_gestion_reportes'] = [
            'tipo' => 'error',
            'mensaje' => 'La resolución no puede superar los 2000 caracteres.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/gestionar_reportes.php',
            true,
            303
        );
        exit;
    }

    $nuevoEstado = $estados[$accion];

    $actualizarReporte = $mysqli->prepare(
        "UPDATE reportes
         SET estatus = ?,
             administrador_id = ?,
             resolucion = ?
         WHERE id_reporte = ?
           AND estatus = 'pendiente'"
    );

    $actualizarReporte->bind_param(
        'sisi',
        $nuevoEstado,
        $administradorId,
        $resolucion,
        $idReporte
    );

    $actualizarReporte->execute();
    $actualizado = $actualizarReporte->affected_rows === 1;
    $actualizarReporte->close();

    $_SESSION['flash_gestion_reportes'] = $actualizado
        ? [
            'tipo' => 'exito',
            'mensaje' => $accion === 'resolver'
                ? 'El reporte fue marcado como resuelto.'
                : 'El reporte fue descartado.'
        ]
        : [
            'tipo' => 'error',
            'mensaje' => 'El reporte ya no está pendiente o no se encontró.'
        ];

    header(
        'Location: ' . RUTA_WEB . '/Funciones/gestionar_reportes.php',
        true,
        303
    );
    exit;
}

$flash = $_SESSION['flash_gestion_reportes'] ?? null;
unset($_SESSION['flash_gestion_reportes']);

$consultaReportes = $mysqli->prepare(
    "SELECT
        r.id_reporte,
        r.blog_id,
        r.com_id,
        r.motivo,
        r.fecha,
        u.nom_usr AS reportero,
        b.titulo AS titulo_publicacion,
        c.comentario,
        c.blog_id AS blog_comentario,
        bp.titulo AS titulo_publicacion_comentario
     FROM reportes r
     INNER JOIN usuario u
        ON u.id_usr = r.usr_id
     LEFT JOIN blog b
        ON b.id_blog = r.blog_id
     LEFT JOIN comentarios c
        ON c.id_com = r.com_id
     LEFT JOIN blog bp
        ON bp.id_blog = c.blog_id
     WHERE r.estatus = 'pendiente'
     ORDER BY r.fecha ASC, r.id_reporte ASC
     LIMIT 100"
);

$consultaReportes->execute();
$reportes = $consultaReportes
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaReportes->close();

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
        content="Gestiona los reportes de contenido enviados a Vita Sacra."
    >
    <title>Gestión de reportes | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparGestionReportes(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        'Administración',
        'administrador',
        'reportes',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Reportes de la comunidad</h1>
                <p>
                    Revisa el motivo y el contenido señalado antes de resolver
                    o descartar cada reporte.
                </p>
            </div>
            <span class="insignia-admin">
                <?php echo count($reportes); ?> pendientes
            </span>
        </section>

        <?php if (is_array($flash)): ?>
            <div
                class="<?php echo ($flash['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>"
                role="status"
            >
                <?php echo escaparGestionReportes($flash['mensaje'] ?? ''); ?>
            </div>
        <?php endif; ?>

        <section class="seccion-admin">
            <?php if ($reportes === []): ?>
                <div class="tarjeta-actividad">
                    <h2>No hay reportes pendientes</h2>
                    <p>La bandeja de reportes está al día.</p>
                </div>
            <?php else: ?>
                <div class="actividad-admin">
                    <?php foreach ($reportes as $reporte): ?>
                        <?php
                        $esReporteComentario = $reporte['com_id'] !== null;
                        $idBlogDestino = $esReporteComentario
                            ? (int)$reporte['blog_comentario']
                            : (int)$reporte['blog_id'];

                        $tituloDestino = $esReporteComentario
                            ? (
                                $reporte['titulo_publicacion_comentario']
                                    ?? 'Publicación no disponible'
                            )
                            : (
                                $reporte['titulo_publicacion']
                                    ?? 'Publicación no disponible'
                            );
                        ?>
                        <article class="tarjeta-actividad">
                            <p>
                                <span class="estado estado-pendiente">
                                    Pendiente
                                </span>
                                <span class="etiqueta">
                                    <?php
                                    echo $esReporteComentario
                                        ? 'Comentario'
                                        : 'Publicación';
                                    ?>
                                </span>
                            </p>

                            <h2>
                                <?php
                                echo escaparGestionReportes($tituloDestino);
                                ?>
                            </h2>

                            <p>
                                Reportado por
                                <strong>
                                    <?php
                                    echo escaparGestionReportes(
                                        $reporte['reportero']
                                    );
                                    ?>
                                </strong>
                                ·
                                <?php
                                $marcaTiempo = strtotime($reporte['fecha']);
                                echo $marcaTiempo === false
                                    ? 'Fecha no disponible'
                                    : escaparGestionReportes(
                                        date('d/m/Y H:i', $marcaTiempo)
                                    );
                                ?>
                            </p>

                            <h3>Motivo del reporte</h3>
                            <p>
                                <?php
                                echo nl2br(
                                    escaparGestionReportes(
                                        $reporte['motivo']
                                    )
                                );
                                ?>
                            </p>

                            <?php if ($esReporteComentario): ?>
                                <h3>Comentario señalado</h3>
                                <blockquote class="bloque-cita">
                                    <?php
                                    echo nl2br(
                                        escaparGestionReportes(
                                            $reporte['comentario'] ?? ''
                                        )
                                    );
                                    ?>
                                </blockquote>
                            <?php endif; ?>

                            <?php if ($idBlogDestino > 0): ?>
                                <p>
                                    <a
                                        href="<?php echo escaparGestionReportes(RUTA_WEB); ?>/Funciones/ver_publicacion.php?id=<?php echo $idBlogDestino; ?>#comentarios"
                                    >
                                        Ver contenido
                                    </a>
                                    <?php if ($esReporteComentario): ?>
                                        ·
                                        <a
                                            href="<?php echo escaparGestionReportes(RUTA_WEB); ?>/Funciones/moderar_comentarios.php"
                                        >
                                            Abrir moderación de comentarios
                                        </a>
                                    <?php else: ?>
                                        ·
                                        <a
                                            href="<?php echo escaparGestionReportes(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php"
                                        >
                                            Abrir gestión de publicaciones
                                        </a>
                                    <?php endif; ?>
                                </p>
                            <?php endif; ?>

                            <div class="enlaces">
                                <form method="POST">
                                    <input
                                        type="hidden"
                                        name="csrf_token"
                                        value="<?php echo escaparGestionReportes($csrf); ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="id_reporte"
                                        value="<?php echo (int)$reporte['id_reporte']; ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="accion"
                                        value="resolver"
                                    >

                                    <label
                                        for="resolucion-<?php echo (int)$reporte['id_reporte']; ?>"
                                    >
                                        Nota de resolución (opcional)
                                    </label>
                                    <textarea
                                        id="resolucion-<?php echo (int)$reporte['id_reporte']; ?>"
                                        name="resolucion"
                                        rows="2"
                                        maxlength="2000"
                                    ></textarea>
                                    <p>
                                        <button class="boton" type="submit">
                                            Marcar resuelto
                                        </button>
                                    </p>
                                </form>

                                <form method="POST">
                                    <input
                                        type="hidden"
                                        name="csrf_token"
                                        value="<?php echo escaparGestionReportes($csrf); ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="id_reporte"
                                        value="<?php echo (int)$reporte['id_reporte']; ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="accion"
                                        value="descartar"
                                    >
                                    <p>
                                        <button
                                            class="boton boton-secundario"
                                            type="submit"
                                        >
                                            Descartar reporte
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