<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

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

function rutaImagenRevisionAdmin($imagen): string
{
    if (!is_string($imagen) || $imagen === '') {
        return '';
    }

    if (filter_var($imagen, FILTER_VALIDATE_URL)) {
        return $imagen;
    }

    return RUTA_WEB
        . '/'
        . ltrim(str_replace('\\', '/', $imagen), '/');
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

$idRecibido = $_SERVER['REQUEST_METHOD'] === 'POST'
    ? postRevisionAdmin('id_blog')
    : ($_GET['id'] ?? '');

$idBlog = filter_var(
    $idRecibido,
    FILTER_VALIDATE_INT,
    ['options' => ['min_range' => 1]]
);

if ($idBlog === false) {
    $idBlog = null;
}

$mensaje = '';
$tipoMensaje = '';
$csrf = generarCSRF();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
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

    if (!verificarCSRF(postRevisionAdmin('csrf_token'))) {
        $mensaje = 'La solicitud no es válida. Actualiza la página e intenta nuevamente.';
        $tipoMensaje = 'mensaje-error';
    } elseif ($idDecision === false || $idVersionDecision === false) {
        $mensaje = 'La publicación o versión seleccionada no es válida.';
        $tipoMensaje = 'mensaje-error';
    } elseif (!in_array(
        $decision,
        ['aprobada', 'correccion', 'rechazada'],
        true
    )) {
        $mensaje = 'Selecciona una decisión editorial válida.';
        $tipoMensaje = 'mensaje-error';
    } elseif ($decision !== 'aprobada' && $observacion === '') {
        $mensaje = 'Escribe las observaciones para solicitar correcciones o rechazar la propuesta.';
        $tipoMensaje = 'mensaje-error';
    } elseif (mb_strlen($observacion, 'UTF-8') > 5000) {
        $mensaje = 'La observación no puede superar los 5,000 caracteres.';
        $tipoMensaje = 'mensaje-error';
    } else {
        $idBlog = (int)$idDecision;
        $mysqli->begin_transaction();

        try {
            $bloqueoPublicacion = $mysqli->prepare(
                "SELECT id_blog, estatus, version_publica
                 FROM blog
                 WHERE id_blog = ?
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
                        !$tieneVersionPublica &&
                        $publicacion['estatus'] === 'revision'
                    )
                    ||
                    (
                        $tieneVersionPublica &&
                        $publicacion['estatus'] === 'publicado'
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
                    tipo_snapshot
                 FROM versiones_blog
                 WHERE blog_id = ?
                 ORDER BY numero DESC
                 LIMIT 1
                 FOR UPDATE"
            );

            $consultaVersion->bind_param('i', $idBlog);
            $consultaVersion->execute();
            $version = $consultaVersion->get_result()->fetch_assoc();
            $consultaVersion->close();

            if (
                !$version ||
                (int)$version['id_version'] !== (int)$idVersionDecision ||
                $version['estatus'] !== 'revision'
            ) {
                throw new DomainException(
                    'La versión enviada ya no está pendiente. Actualiza la página.'
                );
            }

            $idVersion = (int)$version['id_version'];
            $numeroVersion = (int)$version['numero'];
            $observacionDB = $observacion !== '' ? $observacion : null;

            if ($decision === 'aprobada') {
                if (
                    trim((string)$version['titulo_snapshot']) === '' ||
                    trim((string)($version['descripcion_snapshot'] ?? '')) === '' ||
                    (int)$version['categoria_id_snapshot'] < 1 ||
                    trim((string)$version['tipo_snapshot']) === ''
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

                $validarContenido = $mysqli->prepare(
                    "SELECT COUNT(*) AS cantidad
                     FROM bloques_version
                     WHERE version_id = ?
                       AND contenido IS NOT NULL
                       AND CHAR_LENGTH(TRIM(contenido)) > 0"
                );

                $validarContenido->bind_param('i', $idVersion);
                $validarContenido->execute();
                $contenidoValido = $validarContenido
                    ->get_result()
                    ->fetch_assoc();
                $validarContenido->close();

                if ((int)$contenidoValido['cantidad'] === 0) {
                    throw new DomainException(
                        'La versión no contiene texto para publicar.'
                    );
                }
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

                $actualizarPublicacion = $mysqli->prepare(
                    "UPDATE blog
                     SET estatus = 'publicado',
                         categoria_id = ?,
                         titulo = ?,
                         `desc` = ?,
                         img = ?,
                         version_publica = ?,
                         fecha_publicacion = COALESCE(fecha_publicacion, NOW())
                     WHERE id_blog = ?"
                );

                $actualizarPublicacion->bind_param(
                    'isssii',
                    $categoriaId,
                    $titulo,
                    $descripcion,
                    $imagen,
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

            $mensajeResultado = $decision === 'aprobada'
                ? 'aprobada'
                : (
                    $decision === 'correccion'
                        ? ($tieneVersionPublica
                            ? 'correccion_publicada'
                            : 'correccion')
                        : ($tieneVersionPublica
                            ? 'rechazada_publicada'
                            : 'rechazada')
                );

            header(
                'Location: '
                . RUTA_WEB
                . '/Funciones/revisar_publicaciones.php?mensaje='
                . rawurlencode($mensajeResultado),
                true,
                303
            );
            exit;
        } catch (DomainException $error) {
            $mysqli->rollback();
            $mensaje = $error->getMessage();
            $tipoMensaje = 'mensaje-error';
        } catch (Throwable $error) {
            $mysqli->rollback();

            error_log(
                'Vita Sacra: error al registrar decisión editorial, código '
                . $error->getCode()
            );

            $mensaje = 'No fue posible registrar la decisión. Intenta nuevamente.';
            $tipoMensaje = 'mensaje-error';
        }
    }
}

$mensajeRecibido = $_GET['mensaje'] ?? '';

if ($mensaje === '' && is_string($mensajeRecibido)) {
    $mensajes = [
        'aprobada' => 'La versión fue aprobada y ahora está disponible públicamente.',
        'correccion' => 'La propuesta fue devuelta al autor para correcciones.',
        'rechazada' => 'La propuesta fue rechazada y no está disponible públicamente.',
        'correccion_publicada' => 'La versión enviada requiere correcciones; la versión pública anterior sigue visible.',
        'rechazada_publicada' => 'La versión enviada fue rechazada; la versión pública anterior sigue visible.'
    ];

    if (isset($mensajes[$mensajeRecibido])) {
        $mensaje = $mensajes[$mensajeRecibido];
        $tipoMensaje = 'mensaje-exito';
    }
}

$consultaPendientes = $mysqli->prepare(
    "SELECT
        b.id_blog,
        b.version_publica,
        v.id_version,
        v.titulo_snapshot AS titulo,
        v.tipo_snapshot AS tipo,
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
         WHERE b.id_blog = ?
           AND v.estatus = 'revision'
           AND (
                (b.estatus = 'revision' AND b.version_publica IS NULL)
                OR
                (b.estatus = 'publicado' AND b.version_publica IS NOT NULL)
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

        $consultaBloques = $mysqli->prepare(
            "SELECT orden, tipo, contenido
             FROM bloques_version
             WHERE version_id = ?
             ORDER BY orden ASC"
        );

        $consultaBloques->bind_param('i', $idVersionDetalle);
        $consultaBloques->execute();
        $bloques = $consultaBloques
            ->get_result()
            ->fetch_all(MYSQLI_ASSOC);
        $consultaBloques->close();

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

$nombreAdministrador = escaparRevisionAdmin(
    $_SESSION['nom_usr'] ?? 'Administrador'
);

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
</head>
<body>
    <main class="contenedor contenedor-inicio">
        <header>
            <h1>Revisión editorial</h1>
            <p class="subtitulo">
                Sesión de <?php echo $nombreAdministrador; ?>
            </p>
        </header>

        <nav class="enlaces" aria-label="Navegación">
            <a href="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Dashboards/dashboard_admin.php">
                Volver al panel administrativo
            </a>
        </nav>

        <?php if ($mensaje !== ''): ?>
            <div
                class="<?php echo escaparRevisionAdmin($tipoMensaje); ?>"
                role="status"
                aria-live="polite"
            >
                <?php echo escaparRevisionAdmin($mensaje); ?>
            </div>
        <?php endif; ?>

        <?php if ($publicacionSeleccionada): ?>
            <section class="tarjeta">
                <h2><?php echo escaparRevisionAdmin($publicacionSeleccionada['titulo']); ?></h2>

                <p>
                    <strong>Autor:</strong>
                    <?php echo escaparRevisionAdmin($publicacionSeleccionada['autor']); ?>
                </p>
                <p>
                    <strong>Categoría:</strong>
                    <?php echo escaparRevisionAdmin($publicacionSeleccionada['categoria'] ?? 'Sin categoría'); ?>
                </p>
                <p>
                    <strong>Tipo:</strong>
                    <?php echo escaparRevisionAdmin($publicacionSeleccionada['tipo']); ?>
                </p>
                <p>
                    <strong>Versión enviada:</strong>
                    <?php echo (int)$publicacionSeleccionada['numero_version']; ?>
                </p>

                <?php if ($publicacionSeleccionada['version_publica'] !== null): ?>
                    <p>
                        La versión pública anterior seguirá visible si esta
                        actualización requiere correcciones o es rechazada.
                    </p>
                <?php endif; ?>

                <p>
                    <strong>Descripción:</strong><br>
                    <?php
                    echo nl2br(
                        escaparRevisionAdmin(
                            $publicacionSeleccionada['desc'] ?? ''
                        )
                    );
                    ?>
                </p>

                <?php if (!empty($publicacionSeleccionada['img'])): ?>
                    <h3>Imagen principal</h3>
                    <img
                        src="<?php echo escaparRevisionAdmin(rutaImagenRevisionAdmin($publicacionSeleccionada['img'])); ?>"
                        alt="Imagen de la publicación"
                        style="max-width: 100%; height: auto;"
                    >
                <?php endif; ?>

                <?php if (!empty($publicacionSeleccionada['advertencia'])): ?>
                    <h3>Advertencia informativa</h3>
                    <p>
                        <?php
                        echo nl2br(
                            escaparRevisionAdmin(
                                $publicacionSeleccionada['advertencia']
                            )
                        );
                        ?>
                    </p>
                <?php endif; ?>

                <h3>Contenido</h3>
                <?php if ($bloques === []): ?>
                    <p>La publicación no tiene bloques de contenido.</p>
                <?php else: ?>
                    <?php foreach ($bloques as $bloque): ?>
                        <p>
                            <?php
                            echo nl2br(
                                escaparRevisionAdmin(
                                    $bloque['contenido'] ?? ''
                                )
                            );
                            ?>
                        </p>
                    <?php endforeach; ?>
                <?php endif; ?>

                <h3>Fuentes</h3>
                <?php if ($fuentes === []): ?>
                    <p>No hay fuentes asociadas a esta versión.</p>
                <?php else: ?>
                    <ol>
                        <?php foreach ($fuentes as $fuente): ?>
                            <li>
                                <strong>
                                    <?php echo escaparRevisionAdmin($fuente['titulo']); ?>
                                </strong>
                                <?php if (!empty($fuente['autor'])): ?>
                                    — <?php echo escaparRevisionAdmin($fuente['autor']); ?>
                                <?php endif; ?>
                                <?php if (!empty($fuente['anio'])): ?>
                                    (<?php echo (int)$fuente['anio']; ?>)
                                <?php endif; ?>
                                <?php if (!empty($fuente['url'])): ?>
                                    —
                                    <a
                                        href="<?php echo escaparRevisionAdmin($fuente['url']); ?>"
                                        target="_blank"
                                        rel="noopener noreferrer"
                                    >
                                        Consultar fuente
                                    </a>
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
                                — versión
                                <?php echo (int)$registro['numero_version']; ?>,
                                por
                                <?php echo escaparRevisionAdmin($registro['administrador']); ?>
                                el
                                <?php echo escaparRevisionAdmin($registro['fecha']); ?>

                                <?php if (!empty($registro['observacion'])): ?>
                                    <p>
                                        <?php
                                        echo nl2br(
                                            escaparRevisionAdmin(
                                                $registro['observacion']
                                            )
                                        );
                                        ?>
                                    </p>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ol>
                <?php endif; ?>

                <form
                    method="POST"
                    action="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php?id=<?php echo (int)$idBlog; ?>"
                >
                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?php echo escaparRevisionAdmin($csrf); ?>"
                    >
                    <input
                        type="hidden"
                        name="id_blog"
                        value="<?php echo (int)$idBlog; ?>"
                    >
                    <input
                        type="hidden"
                        name="id_version"
                        value="<?php echo (int)$publicacionSeleccionada['id_version']; ?>"
                    >

                    <label for="decision">Decisión</label>
                    <select id="decision" name="decision" required>
                        <option value="">Selecciona una decisión</option>
                        <option value="aprobada">Aprobar y publicar</option>
                        <option value="correccion">Solicitar correcciones</option>
                        <option value="rechazada">Rechazar propuesta</option>
                    </select>

                    <label for="observacion">
                        Observaciones
                        <span>(obligatorias para corrección o rechazo)</span>
                    </label>
                    <textarea
                        id="observacion"
                        name="observacion"
                        maxlength="5000"
                        rows="5"
                    ></textarea>

                    <button type="submit">Registrar decisión</button>
                </form>
            </section>
        <?php else: ?>
            <section>
                <h2>Versiones pendientes</h2>

                <?php if ($pendientes === []): ?>
                    <article class="tarjeta">
                        <p>No hay versiones pendientes de revisión.</p>
                    </article>
                <?php else: ?>
                    <?php foreach ($pendientes as $pendiente): ?>
                        <article class="tarjeta">
                            <h3>
                                <?php echo escaparRevisionAdmin($pendiente['titulo']); ?>
                            </h3>
                            <p>
                                Autor:
                                <?php echo escaparRevisionAdmin($pendiente['autor']); ?>
                            </p>
                            <p>
                                Categoría:
                                <?php echo escaparRevisionAdmin($pendiente['categoria'] ?? 'Sin categoría'); ?>
                            </p>
                            <p>
                                Tipo:
                                <?php echo escaparRevisionAdmin($pendiente['tipo']); ?>
                            </p>
                            <p>
                                Versión:
                                <?php echo (int)$pendiente['numero_version']; ?>
                            </p>

                            <?php if ($pendiente['version_publica'] !== null): ?>
                                <p>Actualización de una publicación que sigue visible.</p>
                            <?php endif; ?>

                            <a
                                href="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php?id=<?php echo (int)$pendiente['id_blog']; ?>"
                            >
                                Revisar publicación
                            </a>
                        </article>
                    <?php endforeach; ?>
                <?php endif; ?>
            </section>
        <?php endif; ?>

        <form
            action="<?php echo escaparRevisionAdmin(RUTA_WEB); ?>/Conexiones/cerrar_sesion.php"
            method="POST"
        >
            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escaparRevisionAdmin($csrf); ?>"
            >
            <button type="submit" class="boton-secundario">
                Cerrar sesión
            </button>
        </form>
    </main>
</body>
</html>