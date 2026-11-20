<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';
require_once __DIR__ . '/componentes/cabecera.php';

date_default_timezone_set('America/Mexico_City');
requiereRol($mysqli, 'administrador');

$idAdministrador = (int)$_SESSION['id_usr'];

function escaparRevisionAdmin($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postRevisionAdmin(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';
    return is_string($valor) ? $valor : '';
}

function volverRevisionAdmin(string $mensaje = ''): void
{
    $destino = RUTA_WEB . '/Funciones/revisar_publicaciones.php';

    if ($mensaje !== '') {
        $destino .= '?mensaje=' . rawurlencode($mensaje);
    }

    header('Location: ' . $destino, true, 303);
    exit;
}

function rutaRevisionAdmin($ruta): string
{
    if (!is_string($ruta) || trim($ruta) === '') {
        return '';
    }

    $ruta = trim($ruta);

    if (filter_var($ruta, FILTER_VALIDATE_URL)) {
        $esquema = strtolower((string)parse_url($ruta, PHP_URL_SCHEME));
        return in_array($esquema, ['http', 'https'], true) ? $ruta : '';
    }

    $ruta = str_replace('\\', '/', $ruta);

    if (str_contains($ruta, '..')) {
        return '';
    }

    return rtrim(RUTA_WEB, '/') . '/' . ltrim($ruta, '/');
}

function cargarBloquesRevisionAdmin(
    mysqli $mysqli,
    int $idVersion
): array {
    $consulta = $mysqli->prepare(
        "SELECT
            b.orden,
            b.tipo,
            b.contenido,
            b.recurso_id,
            r.tipo AS tipo_recurso,
            r.url AS recurso_url,
            r.titulo AS recurso_titulo,
            r.estatus AS estatus_recurso
         FROM bloques_version b
         LEFT JOIN recursos r
            ON r.id_recurso = b.recurso_id
         WHERE b.version_id = ?
         ORDER BY b.orden ASC"
    );

    $consulta->bind_param('i', $idVersion);
    $consulta->execute();
    $bloques = $consulta
        ->get_result()
        ->fetch_all(MYSQLI_ASSOC);
    $consulta->close();

    return $bloques;
}

function validarBloquesRevisionAdmin(array $bloques): void
{
    if ($bloques === [] || count($bloques) > 50) {
        throw new DomainException(
            'La versión debe tener entre 1 y 50 bloques.'
        );
    }

    $tiposTexto = ['titulo', 'parrafo', 'lista', 'cita'];
    $tiposRecurso = [
        'imagen' => 'imagen',
        'pdf' => 'pdf',
        'video' => 'video',
        'modelo_3d' => 'modelo_3d'
    ];
    $hayContenido = false;

    foreach ($bloques as $bloque) {
        $tipo = (string)$bloque['tipo'];
        $contenido = trim((string)($bloque['contenido'] ?? ''));

        if (in_array($tipo, $tiposTexto, true)) {
            if ($contenido === '' || mb_strlen($contenido, 'UTF-8') > 10000) {
                throw new DomainException(
                    'Hay un bloque de texto vacío o demasiado extenso.'
                );
            }

            $hayContenido = true;
            continue;
        }

        if ($tipo === 'enlace') {
            if (
                strlen($contenido) > 1000
                || !filter_var($contenido, FILTER_VALIDATE_URL)
                || !in_array(
                    strtolower((string)parse_url($contenido, PHP_URL_SCHEME)),
                    ['http', 'https'],
                    true
                )
            ) {
                throw new DomainException(
                    'La versión contiene un enlace que no es HTTP o HTTPS válido.'
                );
            }

            $hayContenido = true;
            continue;
        }

        if (!isset($tiposRecurso[$tipo])) {
            throw new DomainException(
                'La versión contiene un tipo de bloque no permitido.'
            );
        }

        if (
            $bloque['recurso_id'] === null
            || $bloque['estatus_recurso'] !== 'aprobado'
            || $bloque['tipo_recurso'] !== $tiposRecurso[$tipo]
            || !is_string($bloque['recurso_url'])
            || trim($bloque['recurso_url']) === ''
        ) {
            throw new DomainException(
                'La versión contiene un recurso que no está aprobado o no coincide con su bloque.'
            );
        }
    }

    if (!$hayContenido) {
        throw new DomainException(
            'La versión debe incluir al menos un bloque de texto o enlace.'
        );
    }
}

function nombreDecisionRevision(string $decision): string
{
    $nombres = [
        'aprobada' => 'Aprobada',
        'correccion' => 'Corrección solicitada',
        'rechazada' => 'Rechazada'
    ];

    return $nombres[$decision] ?? 'Decisión no reconocida';
}

function fechaRevisionAdmin($fecha): string
{
    if (!is_string($fecha) || $fecha === '') {
        return 'No disponible';
    }

    $marcaTiempo = strtotime($fecha);

    return $marcaTiempo === false
        ? 'No disponible'
        : date('d/m/Y H:i', $marcaTiempo);
}

$idRecibido = $_SERVER['REQUEST_METHOD'] === 'POST'
    ? postRevisionAdmin('id_blog')
    : ($_GET['id'] ?? '');

$idBlog = is_scalar($idRecibido)
    ? filter_var(
        $idRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

$idBlog = $idBlog === false ? null : (int)$idBlog;
$mensaje = '';
$tipoMensaje = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $csrfRecibido = postRevisionAdmin('csrf_token');
    $idDecision = filter_var(
        postRevisionAdmin('id_blog'),
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );
    $idVersionDecision = filter_var(
        postRevisionAdmin('id_version'),
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );
    $decision = postRevisionAdmin('decision');
    $observacion = trim(postRevisionAdmin('observacion'));

    if (!verificarCSRF($csrfRecibido)) {
        $mensaje = 'La solicitud no es válida. Actualiza la página e intenta nuevamente.';
        $tipoMensaje = 'mensaje-error';
    } elseif ($idDecision === false || $idVersionDecision === false) {
        $mensaje = 'La publicación o versión seleccionada no es válida.';
        $tipoMensaje = 'mensaje-error';
    } elseif (!in_array($decision, ['aprobada', 'correccion', 'rechazada'], true)) {
        $mensaje = 'Selecciona una decisión editorial válida.';
        $tipoMensaje = 'mensaje-error';
    } elseif (
        $decision !== 'aprobada'
        && mb_strlen($observacion, 'UTF-8') < 5
    ) {
        $mensaje = 'Escribe una observación de al menos 5 caracteres para solicitar correcciones o rechazar.';
        $tipoMensaje = 'mensaje-error';
    } elseif (mb_strlen($observacion, 'UTF-8') > 5000) {
        $mensaje = 'La observación no puede superar los 5,000 caracteres.';
        $tipoMensaje = 'mensaje-error';
    } else {
        $idBlog = (int)$idDecision;
        $idVersionDecision = (int)$idVersionDecision;
        $mysqli->begin_transaction();

        try {
            $bloqueoPublicacion = $mysqli->prepare(
                "SELECT id_blog, estatus, version_publica
                 FROM blog
                 WHERE id_blog = ?
                 LIMIT 1
                 FOR UPDATE"
            );
            $bloqueoPublicacion->bind_param('i', $idBlog);
            $bloqueoPublicacion->execute();
            $publicacion = $bloqueoPublicacion
                ->get_result()
                ->fetch_assoc();
            $bloqueoPublicacion->close();

            $tieneVersionPublica = $publicacion
                && $publicacion['version_publica'] !== null;

            $publicacionPendiente = $publicacion
                && (
                    (
                        !$tieneVersionPublica
                        && $publicacion['estatus'] === 'revision'
                    )
                    || (
                        $tieneVersionPublica
                        && $publicacion['estatus'] === 'publicado'
                    )
                );

            if (!$publicacionPendiente) {
                throw new DomainException(
                    'La publicación ya no tiene una versión pendiente de revisión.'
                );
            }

            $consultaVersion = $mysqli->prepare(
                "SELECT
                    id_version,
                    numero,
                    estatus,
                    titulo_snapshot,
                    descripcion_snapshot,
                    categoria_id_snapshot,
                    imagen_snapshot,
                    tipo_snapshot,
                    plantilla_id_snapshot,
                    advertencia
                 FROM versiones_blog
                 WHERE blog_id = ?
                 ORDER BY numero DESC
                 LIMIT 1
                 FOR UPDATE"
            );
            $consultaVersion->bind_param('i', $idBlog);
            $consultaVersion->execute();
            $version = $consultaVersion
                ->get_result()
                ->fetch_assoc();
            $consultaVersion->close();

            if (
                !$version
                || (int)$version['id_version'] !== $idVersionDecision
                || $version['estatus'] !== 'revision'
            ) {
                throw new DomainException(
                    'La versión enviada ya no está pendiente. Actualiza la página.'
                );
            }

            $idVersion = (int)$version['id_version'];
            $numeroVersion = (int)$version['numero'];
            $observacionDB = $observacion !== '' ? $observacion : null;
            $bloquesDecision = cargarBloquesRevisionAdmin($mysqli, $idVersion);

            if ($decision === 'aprobada') {
                if (
                    trim((string)$version['titulo_snapshot']) === ''
                    || trim((string)($version['descripcion_snapshot'] ?? '')) === ''
                    || (int)$version['categoria_id_snapshot'] < 1
                    || trim((string)$version['tipo_snapshot']) === ''
                ) {
                    throw new DomainException(
                        'La versión no tiene completos sus datos editoriales.'
                    );
                }

                $categoriaId = (int)$version['categoria_id_snapshot'];
                $validarCategoria = $mysqli->prepare(
                    "SELECT id_categoria
                     FROM categorias
                     WHERE id_categoria = ?
                       AND activa = 1
                     LIMIT 1"
                );
                $validarCategoria->bind_param('i', $categoriaId);
                $validarCategoria->execute();
                $categoriaActiva = $validarCategoria
                    ->get_result()
                    ->fetch_assoc();
                $validarCategoria->close();

                if (!$categoriaActiva) {
                    throw new DomainException(
                        'La categoría de la versión está inactiva y no puede publicarse.'
                    );
                }

                $plantillaId = (int)$version['plantilla_id_snapshot'];
                $validarPlantilla = $mysqli->prepare(
                    "SELECT id_plantilla
                     FROM plantillas
                     WHERE id_plantilla = ?
                       AND nombre IN ('clasica', 'divulgativa', 'visual')
                     LIMIT 1"
                );
                $validarPlantilla->bind_param('i', $plantillaId);
                $validarPlantilla->execute();
                $plantillaValida = $validarPlantilla
                    ->get_result()
                    ->fetch_assoc();
                $validarPlantilla->close();

                if (!$plantillaValida) {
                    throw new DomainException(
                        'La plantilla de la versión no está disponible.'
                    );
                }

                validarBloquesRevisionAdmin($bloquesDecision);
            }

            $insertarRevision = $mysqli->prepare(
                "INSERT INTO revisiones_blog
                    (version_id, administrador_id, decision, observacion)
                 VALUES (?, ?, ?, ?)"
            );
            $insertarRevision->bind_param(
                'iiss',
                $idVersion,
                $idAdministrador,
                $decision,
                $observacionDB
            );
            $insertarRevision->execute();
            $insertarRevision->close();

            $nuevoEstadoVersion = $decision === 'aprobada'
                ? 'publicado'
                : ($decision === 'correccion' ? 'correccion' : 'rechazado');

            $actualizarVersion = $mysqli->prepare(
                "UPDATE versiones_blog
                 SET estatus = ?
                 WHERE id_version = ?
                   AND blog_id = ?
                   AND estatus = 'revision'"
            );
            $actualizarVersion->bind_param(
                'sii',
                $nuevoEstadoVersion,
                $idVersion,
                $idBlog
            );
            $actualizarVersion->execute();
            $versionesActualizadas = $actualizarVersion->affected_rows;
            $actualizarVersion->close();

            if ($versionesActualizadas !== 1) {
                throw new DomainException(
                    'No se pudo actualizar el estado de la versión.'
                );
            }

            if ($decision === 'aprobada') {
                $titulo = (string)$version['titulo_snapshot'];
                $descripcion = (string)$version['descripcion_snapshot'];
                $categoriaId = (int)$version['categoria_id_snapshot'];
                $imagen = $version['imagen_snapshot'];
                $tipo = (string)$version['tipo_snapshot'];
                $plantillaId = (int)$version['plantilla_id_snapshot'];

                $actualizarPublicacion = $mysqli->prepare(
                    "UPDATE blog
                     SET estatus = 'publicado',
                         categoria_id = ?,
                         plantilla_id = ?,
                         titulo = ?,
                         `desc` = ?,
                         img = ?,
                         tipo = ?,
                         version_publica = ?,
                         fecha_publicacion = COALESCE(fecha_publicacion, NOW())
                     WHERE id_blog = ?"
                );
                $actualizarPublicacion->bind_param(
                    'iissssii',
                    $categoriaId,
                    $plantillaId,
                    $titulo,
                    $descripcion,
                    $imagen,
                    $tipo,
                    $numeroVersion,
                    $idBlog
                );
                $actualizarPublicacion->execute();
                $filasActualizadas = $actualizarPublicacion->affected_rows;
                $actualizarPublicacion->close();

                if ($filasActualizadas < 1) {
                    throw new DomainException(
                        'No se pudo publicar la versión aprobada.'
                    );
                }
            } elseif (!$tieneVersionPublica) {
                $nuevoEstadoPublicacion = $decision === 'correccion'
                    ? 'correccion'
                    : 'rechazado';

                $actualizarPublicacion = $mysqli->prepare(
                    "UPDATE blog
                     SET estatus = ?
                     WHERE id_blog = ?
                       AND estatus = 'revision'
                       AND version_publica IS NULL"
                );
                $actualizarPublicacion->bind_param(
                    'si',
                    $nuevoEstadoPublicacion,
                    $idBlog
                );
                $actualizarPublicacion->execute();
                $filasActualizadas = $actualizarPublicacion->affected_rows;
                $actualizarPublicacion->close();

                if ($filasActualizadas !== 1) {
                    throw new DomainException(
                        'No se pudo aplicar la decisión editorial.'
                    );
                }
            }

            $mysqli->commit();

            volverRevisionAdmin(
                $decision === 'aprobada'
                    ? 'aprobada'
                    : (
                        $decision === 'correccion'
                            ? ($tieneVersionPublica
                                ? 'correccion_publicada'
                                : 'correccion')
                            : ($tieneVersionPublica
                                ? 'rechazada_publicada'
                                : 'rechazada')
                    )
            );
        } catch (DomainException $error) {
            $mysqli->rollback();
            $mensaje = $error->getMessage();
            $tipoMensaje = 'mensaje-error';
        } catch (Throwable $error) {
            $mysqli->rollback();
            error_log(
                'Vita Sacra: error al registrar decisión editorial: '
                . $error->getMessage()
            );
            $mensaje = 'No fue posible registrar la decisión. Intenta nuevamente.';
            $tipoMensaje = 'mensaje-error';
        }
    }
}

$mensajes = [
    'aprobada' => 'La versión fue aprobada y ahora está disponible públicamente.',
    'correccion' => 'La propuesta fue devuelta al autor para correcciones.',
    'rechazada' => 'La propuesta fue rechazada y no está disponible públicamente.',
    'correccion_publicada' => 'La versión enviada requiere correcciones; la versión pública anterior sigue visible.',
    'rechazada_publicada' => 'La versión enviada fue rechazada; la versión pública anterior sigue visible.'
];

$mensajeRecibido = $_GET['mensaje'] ?? '';
if (
    $mensaje === ''
    && is_string($mensajeRecibido)
    && isset($mensajes[$mensajeRecibido])
) {
    $mensaje = $mensajes[$mensajeRecibido];
    $tipoMensaje = 'mensaje-exito';
}

$consultaPendientes = $mysqli->prepare(
    "SELECT
        b.id_blog,
        b.version_publica,
        v.id_version,
        v.titulo_snapshot AS titulo,
        v.tipo_snapshot AS tipo,
        v.plantilla_id_snapshot,
        p.nombre AS plantilla,
        u.nom_usr AS autor,
        c.nombre AS categoria,
        v.numero AS numero_version,
        v.fecha AS fecha_version
     FROM blog b
     INNER JOIN usuario u ON u.id_usr = b.usr_id
     INNER JOIN versiones_blog v
        ON v.blog_id = b.id_blog
       AND v.numero = (
            SELECT MAX(v2.numero)
            FROM versiones_blog v2
            WHERE v2.blog_id = b.id_blog
       )
     LEFT JOIN categorias c
        ON c.id_categoria = v.categoria_id_snapshot
     LEFT JOIN plantillas p
        ON p.id_plantilla = v.plantilla_id_snapshot
     WHERE v.estatus = 'revision'
       AND (
            (b.estatus = 'revision' AND b.version_publica IS NULL)
            OR
            (b.estatus = 'publicado' AND b.version_publica IS NOT NULL)
       )
     ORDER BY v.fecha ASC"
);
$consultaPendientes->execute();
$pendientes = $consultaPendientes
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaPendientes->close();

$publicacionSeleccionada = null;
$bloques = [];
$fuentes = [];
$historial = [];

if ($idBlog !== null) {
    $consultaDetalle = $mysqli->prepare(
        "SELECT
            b.id_blog,
            b.estatus,
            b.version_publica,
            u.nom_usr AS autor,
            c.nombre AS categoria,
            v.id_version,
            v.numero AS numero_version,
            v.titulo_snapshot AS titulo,
            v.descripcion_snapshot AS `desc`,
            v.imagen_snapshot AS img,
            v.tipo_snapshot AS tipo,
            v.plantilla_id_snapshot,
            p.nombre AS plantilla,
            v.advertencia,
            v.estatus AS estatus_version,
            v.fecha AS fecha_version
         FROM blog b
         INNER JOIN usuario u ON u.id_usr = b.usr_id
         INNER JOIN versiones_blog v
            ON v.blog_id = b.id_blog
           AND v.numero = (
                SELECT MAX(v2.numero)
                FROM versiones_blog v2
                WHERE v2.blog_id = b.id_blog
           )
         LEFT JOIN categorias c
            ON c.id_categoria = v.categoria_id_snapshot
         LEFT JOIN plantillas p
            ON p.id_plantilla = v.plantilla_id_snapshot
         WHERE b.id_blog = ?
           AND v.estatus = 'revision'
           AND (
                (b.estatus = 'revision' AND b.version_publica IS NULL)
                OR (b.estatus = 'publicado' AND b.version_publica IS NOT NULL)
           )
         LIMIT 1"
    );
    $consultaDetalle->bind_param('i', $idBlog);
    $consultaDetalle->execute();
    $publicacionSeleccionada = $consultaDetalle
        ->get_result()
        ->fetch_assoc();
    $consultaDetalle->close();

    if ($publicacionSeleccionada) {
        $idVersionDetalle = (int)$publicacionSeleccionada['id_version'];
        $bloques = cargarBloquesRevisionAdmin($mysqli, $idVersionDetalle);

        $consultaFuentes = $mysqli->prepare(
            "SELECT f.titulo, f.autor, f.url, f.anio
             FROM version_fuentes vf
             INNER JOIN fuentes f ON f.id_fuente = vf.fuente_id
             WHERE vf.version_id = ?
             ORDER BY f.titulo"
        );
        $consultaFuentes->bind_param('i', $idVersionDetalle);
        $consultaFuentes->execute();
        $fuentes = $consultaFuentes
            ->get_result()
            ->fetch_all(MYSQLI_ASSOC);
        $consultaFuentes->close();

        $consultaHistorial = $mysqli->prepare(
            "SELECT
                r.decision,
                r.observacion,
                r.fecha,
                u.nom_usr AS administrador,
                v.numero AS numero_version
             FROM revisiones_blog r
             INNER JOIN versiones_blog v ON v.id_version = r.version_id
             INNER JOIN usuario u ON u.id_usr = r.administrador_id
             WHERE v.blog_id = ?
             ORDER BY r.fecha DESC"
        );
        $consultaHistorial->bind_param('i', $idBlog);
        $consultaHistorial->execute();
        $historial = $consultaHistorial
            ->get_result()
            ->fetch_all(MYSQLI_ASSOC);
        $consultaHistorial->close();
    } elseif ($mensaje === '') {
        http_response_code(404);
        $mensaje = 'La publicación no está pendiente de revisión.';
        $tipoMensaje = 'mensaje-error';
    }
}

$csrf = generarCSRF();
$nombreNav = $_SESSION['nom_usr'] ?? 'Mi cuenta';
$nombreNav = is_string($nombreNav) ? $nombreNav : 'Mi cuenta';
$nombreAdministrador = escaparRevisionAdmin($nombreNav);
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Revisión editorial | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
    <style>
        .vista-revision { padding: 22px; border: 1px solid var(--bordes); border-radius: var(--radio); background: var(--superficie); }
        .vista-revision.plantilla-divulgativa { border-top: 5px solid var(--azul); }
        .vista-revision.plantilla-visual { background: var(--azul-claro); }
        .bloque-revision { margin: 18px 0; }
    </style>
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreNav,
        'administrador',
        'revision',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Revisión editorial</h1>
                <p>Revisa la versión, sus bloques y la plantilla antes de decidir.</p>
            </div>
        </section>

        <nav class="enlaces" aria-label="Navegación">
            <a class="boton boton-secundario" href="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Dashboards/dashboard_admin.php">
                Volver al panel administrativo
            </a>
        </nav>

        <?php if ($mensaje !== ''): ?>
            <div class="<?php echo escaparRevisionAdmin($tipoMensaje); ?>" role="status" aria-live="polite">
                <?php echo escaparRevisionAdmin($mensaje); ?>
            </div>
        <?php endif; ?>

        <?php if ($publicacionSeleccionada): ?>
            <?php
            $nombrePlantilla = $publicacionSeleccionada['plantilla']
                ?? 'clasica';
            $plantillaCss = in_array(
                $nombrePlantilla,
                ['clasica', 'divulgativa', 'visual'],
                true
            ) ? $nombrePlantilla : 'clasica';
            ?>
            <article class="tarjeta">
                <h2><?php echo escaparRevisionAdmin($publicacionSeleccionada['titulo']); ?></h2>
                <p><strong>Autor:</strong> <?php echo escaparRevisionAdmin($publicacionSeleccionada['autor']); ?></p>
                <p><strong>Categoría:</strong> <?php echo escaparRevisionAdmin($publicacionSeleccionada['categoria'] ?? 'Sin categoría'); ?></p>
                <p><strong>Tipo:</strong> <?php echo escaparRevisionAdmin($publicacionSeleccionada['tipo']); ?></p>
                <p><strong>Versión:</strong> <?php echo (int)$publicacionSeleccionada['numero_version']; ?></p>
                <p><strong>Plantilla:</strong> <?php echo escaparRevisionAdmin(ucfirst($plantillaCss)); ?></p>

                <?php if ($publicacionSeleccionada['version_publica'] !== null): ?>
                    <p>La versión pública anterior seguirá visible si esta actualización requiere correcciones o es rechazada.</p>
                <?php endif; ?>

                <p>
                    <strong>Descripción:</strong><br>
                    <?php echo nl2br(escaparRevisionAdmin($publicacionSeleccionada['desc'] ?? '')); ?>
                </p>

                <?php if (!empty($publicacionSeleccionada['img'])): ?>
                    <img
                        src="<?php echo escaparRevisionAdmin(rutaRevisionAdmin($publicacionSeleccionada['img'])); ?>"
                        alt="Imagen de la publicación"
                        style="max-width:100%;height:auto"
                    >
                <?php endif; ?>

                <?php if (!empty($publicacionSeleccionada['advertencia'])): ?>
                    <aside class="mensaje">
                        <strong>Advertencia informativa</strong>
                        <p><?php echo nl2br(escaparRevisionAdmin($publicacionSeleccionada['advertencia'])); ?></p>
                    </aside>
                <?php endif; ?>

                <h3>Vista previa de la versión</h3>
                <section class="vista-revision plantilla-<?php echo escaparRevisionAdmin($plantillaCss); ?>">
                    <?php foreach ($bloques as $bloque): ?>
                        <?php
                        $tipo = (string)$bloque['tipo'];
                        $contenido = (string)($bloque['contenido'] ?? '');
                        $urlRecurso = rutaRevisionAdmin($bloque['recurso_url'] ?? '');
                        $recursoAprobado =
                            ($bloque['estatus_recurso'] ?? '') === 'aprobado';
                        ?>
                        <div class="bloque-revision">
                            <?php if ($tipo === 'titulo'): ?>
                                <h2><?php echo escaparRevisionAdmin($contenido); ?></h2>
                            <?php elseif ($tipo === 'parrafo'): ?>
                                <p><?php echo nl2br(escaparRevisionAdmin($contenido)); ?></p>
                            <?php elseif ($tipo === 'lista'): ?>
                                <ul>
                                    <?php foreach (preg_split('/\r\n|\r|\n/', $contenido) ?: [] as $elemento): ?>
                                        <?php if (trim($elemento) !== ''): ?>
                                            <li><?php echo escaparRevisionAdmin(trim($elemento)); ?></li>
                                        <?php endif; ?>
                                    <?php endforeach; ?>
                                </ul>
                            <?php elseif ($tipo === 'cita'): ?>
                                <blockquote class="bloque-cita"><?php echo nl2br(escaparRevisionAdmin($contenido)); ?></blockquote>
                            <?php elseif ($tipo === 'enlace'): ?>
                                <?php if (filter_var($contenido, FILTER_VALIDATE_URL) && in_array(strtolower((string)parse_url($contenido, PHP_URL_SCHEME)), ['http', 'https'], true)): ?>
                                    <p><a href="<?php echo escaparRevisionAdmin($contenido); ?>" target="_blank" rel="noopener noreferrer"><?php echo escaparRevisionAdmin($contenido); ?></a></p>
                                <?php else: ?>
                                    <p class="mensaje-error">Enlace inválido.</p>
                                <?php endif; ?>
                            <?php elseif (in_array($tipo, ['imagen', 'pdf', 'video', 'modelo_3d'], true)): ?>
                                <?php if ($recursoAprobado && $urlRecurso !== ''): ?>
                                    <?php if ($tipo === 'imagen' && ($bloque['tipo_recurso'] ?? '') === 'imagen'): ?>
                                        <figure>
                                            <img src="<?php echo escaparRevisionAdmin($urlRecurso); ?>" alt="<?php echo escaparRevisionAdmin($bloque['recurso_titulo'] ?: 'Imagen de la publicación'); ?>" style="max-width:100%;height:auto">
                                            <?php if (!empty($bloque['recurso_titulo'])): ?><figcaption><?php echo escaparRevisionAdmin($bloque['recurso_titulo']); ?></figcaption><?php endif; ?>
                                        </figure>
                                    <?php elseif (($tipo === 'pdf' && ($bloque['tipo_recurso'] ?? '') === 'pdf') || ($tipo === 'video' && ($bloque['tipo_recurso'] ?? '') === 'video') || ($tipo === 'modelo_3d' && ($bloque['tipo_recurso'] ?? '') === 'modelo_3d')): ?>
                                        <p><a href="<?php echo escaparRevisionAdmin($urlRecurso); ?>" target="_blank" rel="noopener noreferrer"><?php echo escaparRevisionAdmin($bloque['recurso_titulo'] ?: 'Abrir ' . $tipo); ?></a></p>
                                    <?php else: ?>
                                        <p class="mensaje-error">El recurso no coincide con el tipo de bloque.</p>
                                    <?php endif; ?>
                                <?php else: ?>
                                    <p class="mensaje-error">El recurso no está aprobado o no es accesible.</p>
                                <?php endif; ?>
                            <?php else: ?>
                                <p class="mensaje-error">Tipo de bloque no permitido: <?php echo escaparRevisionAdmin($tipo); ?></p>
                            <?php endif; ?>
                        </div>
                    <?php endforeach; ?>
                </section>

                <h3>Fuentes</h3>
                <?php if ($fuentes === []): ?>
                    <p>No hay fuentes asociadas a esta versión.</p>
                <?php else: ?>
                    <ol>
                        <?php foreach ($fuentes as $fuente): ?>
                            <li>
                                <strong><?php echo escaparRevisionAdmin($fuente['titulo']); ?></strong>
                                <?php if (!empty($fuente['autor'])): ?> — <?php echo escaparRevisionAdmin($fuente['autor']); ?><?php endif; ?>
                                <?php if (!empty($fuente['anio'])): ?> (<?php echo (int)$fuente['anio']; ?>)<?php endif; ?>
                                <?php if (!empty($fuente['url'])): ?>
                                    — <a href="<?php echo escaparRevisionAdmin($fuente['url']); ?>" target="_blank" rel="noopener noreferrer">Consultar fuente</a>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ol>
                <?php endif; ?>

                <?php if ($historial !== []): ?>
                    <h3>Historial de decisiones</h3>
                    <ol>
                        <?php foreach ($historial as $registro): ?>
                            <li>
                                <?php echo escaparRevisionAdmin(nombreDecisionRevision($registro['decision'])); ?>
                                — versión <?php echo (int)$registro['numero_version']; ?>,
                                por <?php echo escaparRevisionAdmin($registro['administrador']); ?>
                                el <?php echo escaparRevisionAdmin(fechaRevisionAdmin($registro['fecha'])); ?>
                                <?php if (!empty($registro['observacion'])): ?>
                                    <p><?php echo nl2br(escaparRevisionAdmin($registro['observacion'])); ?></p>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ol>
                <?php endif; ?>

                <form method="POST" action="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php?id=<?php echo (int)$idBlog; ?>">
                    <input type="hidden" name="csrf_token" value="<?php echo escaparRevisionAdmin($csrf); ?>">
                    <input type="hidden" name="id_blog" value="<?php echo (int)$idBlog; ?>">
                    <input type="hidden" name="id_version" value="<?php echo (int)$publicacionSeleccionada['id_version']; ?>">

                    <label for="decision">Decisión</label>
                    <select id="decision" name="decision" required>
                        <option value="">Selecciona una decisión</option>
                        <option value="aprobada">Aprobar y publicar</option>
                        <option value="correccion">Solicitar correcciones</option>
                        <option value="rechazada">Rechazar propuesta</option>
                    </select>

                    <label for="observacion">Observaciones (obligatorias para corrección o rechazo)</label>
                    <textarea id="observacion" name="observacion" maxlength="5000" rows="5"></textarea>

                    <button class="boton" type="submit">Registrar decisión</button>
                </form>
            </article>
        <?php else: ?>
            <section class="seccion-admin">
                <h2>Versiones pendientes</h2>

                <?php if ($pendientes === []): ?>
                    <article class="tarjeta">
                        <p>No hay versiones pendientes de revisión.</p>
                    </article>
                <?php else: ?>
                    <div class="actividad-admin">
                        <?php foreach ($pendientes as $pendiente): ?>
                            <?php
                            $nombrePlantillaPendiente = $pendiente['plantilla']
                                ?? 'clasica';
                            ?>
                            <article class="tarjeta-actividad">
                                <h3><?php echo escaparRevisionAdmin($pendiente['titulo']); ?></h3>
                                <p>Autor: <?php echo escaparRevisionAdmin($pendiente['autor']); ?></p>
                                <p>Categoría: <?php echo escaparRevisionAdmin($pendiente['categoria'] ?? 'Sin categoría'); ?></p>
                                <p>Tipo: <?php echo escaparRevisionAdmin($pendiente['tipo']); ?></p>
                                <p>Plantilla: <?php echo escaparRevisionAdmin(ucfirst($nombrePlantillaPendiente)); ?></p>
                                <p>Versión: <?php echo (int)$pendiente['numero_version']; ?></p>
                                <?php if ($pendiente['version_publica'] !== null): ?>
                                    <p>Actualización de una publicación que sigue visible.</p>
                                <?php endif; ?>
                                <a class="boton boton-secundario" href="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php?id=<?php echo (int)$pendiente['id_blog']; ?>">
                                    Revisar publicación
                                </a>
                            </article>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>
            </section>
        <?php endif; ?>
    </main>

    <script
        src="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>