<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereRol($mysqli, 'autor', 'administrador');

$rolesActuales = obtenerRolesActuales($mysqli);
$esAdministrador = in_array('administrador', $rolesActuales, true);
$tieneRolAutor = in_array('autor', $rolesActuales, true);
$idUsuario = (int)$_SESSION['id_usr'];
$csrf = generarCSRF();

function escaparGestionPublicaciones($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postGestionPublicaciones(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';

    return is_string($valor) ? $valor : '';
}

function etiquetaEstadoPublicacion(string $estado): string
{
    $etiquetas = [
        'borrador' => 'Borrador',
        'revision' => 'En revisión',
        'correccion' => 'Requiere correcciones',
        'rechazado' => 'Rechazada',
        'publicado' => 'Publicada',
        'oculto' => 'Oculta'
    ];

    return $etiquetas[$estado] ?? 'Estado no reconocido';
}

$mensaje = '';
$tipoMensaje = '';

$mensajeRecibido = $_GET['mensaje'] ?? '';
$mensajeRecibido = is_string($mensajeRecibido)
    ? $mensajeRecibido
    : '';

if ($mensajeRecibido === 'ocultado') {
    $mensaje = 'La publicación se ocultó y la decisión quedó registrada.';
    $tipoMensaje = 'mensaje';
} elseif ($mensajeRecibido === 'revision_enviada') {
    $mensaje = 'La publicación se envió a revisión.';
    $tipoMensaje = 'mensaje';
} elseif ($mensajeRecibido === 'error') {
    $mensaje = 'No se pudo completar la acción solicitada.';
    $tipoMensaje = 'mensaje-error';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['eliminar'])) {
    if (!$esAdministrador) {
        http_response_code(403);
        exit('No tienes permisos para ocultar publicaciones.');
    }

    if (!verificarCSRF(postGestionPublicaciones('csrf_token'))) {
        http_response_code(403);
        exit('La solicitud no es válida. Actualiza la página e intenta nuevamente.');
    }

    $idRecibido = filter_var(
        postGestionPublicaciones('id_blog'),
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );

    $observacion = trim(postGestionPublicaciones('observacion'));

    if ($idRecibido === false) {
        $mensaje = 'La publicación seleccionada no es válida.';
        $tipoMensaje = 'mensaje-error';
    } elseif ($observacion === '') {
        $mensaje = 'Escribe el motivo para ocultar la publicación.';
        $tipoMensaje = 'mensaje-error';
    } elseif (mb_strlen($observacion, 'UTF-8') > 5000) {
        $mensaje = 'El motivo no puede superar los 5,000 caracteres.';
        $tipoMensaje = 'mensaje-error';
    } else {
        $idPublicacionOcultar = (int)$idRecibido;
        $mysqli->begin_transaction();

        try {
            $bloqueo = $mysqli->prepare(
                "SELECT estatus, version_publica
                 FROM blog
                 WHERE id_blog = ?
                 FOR UPDATE"
            );

            $bloqueo->bind_param('i', $idPublicacionOcultar);
            $bloqueo->execute();
            $publicacionBloqueada = $bloqueo
                ->get_result()
                ->fetch_assoc();
            $bloqueo->close();

            if (
                !$publicacionBloqueada ||
                $publicacionBloqueada['estatus'] !== 'publicado' ||
                $publicacionBloqueada['version_publica'] === null
            ) {
                throw new DomainException(
                    'Solo se pueden ocultar publicaciones que estén publicadas.'
                );
            }

            $numeroVersionPublica =
                (int)$publicacionBloqueada['version_publica'];

            $consultaVersion = $mysqli->prepare(
                "SELECT id_version
                 FROM versiones_blog
                 WHERE blog_id = ?
                   AND numero = ?
                 LIMIT 1
                 FOR UPDATE"
            );

            $consultaVersion->bind_param(
                'ii',
                $idPublicacionOcultar,
                $numeroVersionPublica
            );

            $consultaVersion->execute();
            $versionPublica = $consultaVersion
                ->get_result()
                ->fetch_assoc();
            $consultaVersion->close();

            if (!$versionPublica) {
                throw new DomainException(
                    'No se encontró la versión pública que debe quedar registrada.'
                );
            }

            $idVersionPublica = (int)$versionPublica['id_version'];
            $decision = 'oculta';

            $registrarDecision = $mysqli->prepare(
                "INSERT INTO revisiones_blog
                    (version_id, administrador_id, decision, observacion)
                 VALUES (?, ?, ?, ?)"
            );

            $registrarDecision->bind_param(
                'iiss',
                $idVersionPublica,
                $idUsuario,
                $decision,
                $observacion
            );

            $registrarDecision->execute();
            $registrarDecision->close();

            $ocultar = $mysqli->prepare(
                "UPDATE blog
                 SET estatus = 'oculto'
                 WHERE id_blog = ?
                   AND estatus = 'publicado'
                   AND version_publica = ?"
            );

            $ocultar->bind_param(
                'ii',
                $idPublicacionOcultar,
                $numeroVersionPublica
            );

            $ocultar->execute();
            $actualizado = $ocultar->affected_rows === 1;
            $ocultar->close();

            if (!$actualizado) {
                throw new DomainException(
                    'No se pudo cambiar el estado de la publicación.'
                );
            }

            $mysqli->commit();

            header(
                'Location: '
                . RUTA_WEB
                . '/Funciones/gestionar_publicaciones.php?mensaje=ocultado',
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
                'Vita Sacra: error al ocultar publicación, código '
                . $error->getCode()
            );

            $mensaje = 'No fue posible ocultar la publicación. Intenta nuevamente.';
            $tipoMensaje = 'mensaje-error';
        }
    }
}

$buscarRecibido = $_GET['buscar'] ?? '';
$buscar = is_string($buscarRecibido)
    ? trim(mb_substr($buscarRecibido, 0, 100, 'UTF-8'))
    : '';

$verTodas = $esAdministrador ? 1 : 0;
$termino = $buscar;

$consulta = $mysqli->prepare(
    "SELECT
        b.id_blog,
        b.usr_id,
        b.titulo,
        b.`desc`,
        b.img,
        b.estatus,
        b.version_publica,
        b.fecha_publicacion,
        b.fecha_creacion,
        c.nombre AS categoria
     FROM blog b
     LEFT JOIN categorias c
        ON c.id_categoria = b.categoria_id
     WHERE (? = 1 OR b.usr_id = ?)
       AND (? = '' OR b.titulo LIKE CONCAT('%', ?, '%'))
     ORDER BY b.fecha_creacion DESC"
);

$consulta->bind_param(
    'iiss',
    $verTodas,
    $idUsuario,
    $buscar,
    $termino
);

$consulta->execute();
$publicaciones = $consulta
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consulta->close();

$nombreUsuario = escaparGestionPublicaciones(
    $_SESSION['nom_usr'] ?? 'Usuario'
);

$enlacePanel = $esAdministrador
    ? RUTA_WEB . '/Dashboards/dashboard_admin.php'
    : RUTA_WEB . '/Dashboards/dashboard_autor.php';

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Mis publicaciones | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <main class="contenedor contenedor-inicio">
        <header>
            <h1>
                <?php
                echo $esAdministrador
                    ? 'Gestionar publicaciones'
                    : 'Mis publicaciones';
                ?>
            </h1>
            <p class="subtitulo">
                Sesión de <?php echo $nombreUsuario; ?>
            </p>
        </header>

        <nav class="enlaces" aria-label="Navegación">
            <a href="<?php echo escaparGestionPublicaciones($enlacePanel); ?>">
                Volver a mi panel
            </a>

            <a href="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Funciones/publicaciones.php">
                Crear borrador
            </a>

            <?php if ($esAdministrador): ?>
                <a href="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php">
                    Revisar publicaciones pendientes
                </a>
            <?php endif; ?>
        </nav>

        <?php if ($mensaje !== ''): ?>
            <div
                class="<?php echo escaparGestionPublicaciones($tipoMensaje); ?>"
                role="status"
                aria-live="polite"
            >
                <?php echo escaparGestionPublicaciones($mensaje); ?>
            </div>
        <?php endif; ?>

        <form
            method="GET"
            action="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php"
        >
            <label for="buscar">Buscar por título</label>
            <input
                type="search"
                id="buscar"
                name="buscar"
                maxlength="100"
                value="<?php echo escaparGestionPublicaciones($buscar); ?>"
            >
            <button type="submit">Buscar</button>
        </form>

        <section aria-labelledby="listado-titulo">
            <h2 id="listado-titulo">
                <?php
                echo $esAdministrador
                    ? 'Publicaciones registradas'
                    : 'Tus publicaciones';
                ?>
                (<?php echo count($publicaciones); ?>)
            </h2>

            <?php if ($publicaciones === []): ?>
                <article class="tarjeta">
                    <p>
                        <?php
                        echo $buscar !== ''
                            ? 'No se encontraron publicaciones con ese título.'
                            : 'No hay publicaciones para mostrar.';
                        ?>
                    </p>
                </article>
            <?php else: ?>
                <?php foreach ($publicaciones as $publicacion): ?>
                    <?php
                    $estado = is_string($publicacion['estatus'] ?? null)
                        ? $publicacion['estatus']
                        : '';

                    $idPublicacion = (int)$publicacion['id_blog'];
                    $esPropietario =
                        (int)$publicacion['usr_id'] === $idUsuario;
                    $sinVersionPublica =
                        $publicacion['version_publica'] === null;

                    $estadoEditable = in_array(
                        $estado,
                        ['borrador', 'correccion'],
                        true
                    );

                    $puedeEditar = $estadoEditable
                        && $sinVersionPublica
                        && ($esAdministrador || $esPropietario);

                    $puedeEnviarRevision = !$esAdministrador
                        && $tieneRolAutor
                        && $esPropietario
                        && $estadoEditable
                        && $sinVersionPublica;

                    $puedeOcultar = $esAdministrador
                        && $estado === 'publicado'
                        && !$sinVersionPublica;

                    $idCampoObservacion =
                        'observacion_' . $idPublicacion;
                    ?>

                    <article class="tarjeta">
                        <h3>
                            <?php
                            echo escaparGestionPublicaciones(
                                $publicacion['titulo']
                            );
                            ?>
                        </h3>

                        <p>
                            Categoría:
                            <?php
                            echo escaparGestionPublicaciones(
                                $publicacion['categoria'] ?? 'Sin categoría'
                            );
                            ?>
                        </p>

                        <p>
                            Estado:
                            <?php
                            echo escaparGestionPublicaciones(
                                etiquetaEstadoPublicacion($estado)
                            );
                            ?>
                        </p>

                        <p>
                            Creada:
                            <?php
                            echo escaparGestionPublicaciones(
                                date(
                                    'd/m/Y H:i',
                                    strtotime($publicacion['fecha_creacion'])
                                )
                            );
                            ?>
                        </p>

                        <a
                            href="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Funciones/historial_publicacion.php?id=<?php echo $idPublicacion; ?>"
                        >
                            Ver historial editorial
                        </a>

                        <?php if ($puedeEditar): ?>
                            <a
                                href="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Funciones/editar_publicacion.php?id=<?php echo $idPublicacion; ?>"
                            >
                                Editar
                            </a>
                        <?php endif; ?>

                        <?php if ($puedeEnviarRevision): ?>
                            <a
                                href="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Funciones/enviar_revision.php?id=<?php echo $idPublicacion; ?>"
                            >
                                Enviar a revisión
                            </a>
                        <?php endif; ?>

                        <?php if ($puedeOcultar): ?>
                            <form
                                method="POST"
                                action="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php"
                                onsubmit="return confirm('¿Deseas ocultar esta publicación?');"
                            >
                                <input
                                    type="hidden"
                                    name="csrf_token"
                                    value="<?php echo escaparGestionPublicaciones($csrf); ?>"
                                >
                                <input
                                    type="hidden"
                                    name="id_blog"
                                    value="<?php echo $idPublicacion; ?>"
                                >

                                <label for="<?php echo escaparGestionPublicaciones($idCampoObservacion); ?>">
                                    Motivo para ocultarla
                                </label>
                                <textarea
                                    id="<?php echo escaparGestionPublicaciones($idCampoObservacion); ?>"
                                    name="observacion"
                                    maxlength="5000"
                                    rows="3"
                                    required
                                ></textarea>

                                <button
                                    type="submit"
                                    name="eliminar"
                                    class="boton-secundario"
                                >
                                    Ocultar publicación
                                </button>
                            </form>
                        <?php endif; ?>
                    </article>
                <?php endforeach; ?>
            <?php endif; ?>
        </section>

        <form
            action="<?php echo escaparGestionPublicaciones(RUTA_WEB); ?>/Conexiones/cerrar_sesion.php"
            method="POST"
        >
            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escaparGestionPublicaciones($csrf); ?>"
            >
            <button type="submit" class="boton-secundario">
                Cerrar sesión
            </button>
        </form>
    </main>
</body>
</html>