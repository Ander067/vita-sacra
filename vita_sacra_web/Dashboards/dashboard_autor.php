<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereUsuarioActual($mysqli);

$rolesActuales = obtenerRolesActuales($mysqli);

if (in_array('administrador', $rolesActuales, true)) {
    header(
        'Location: ' . RUTA_WEB . '/Dashboards/dashboard_admin.php',
        true,
        303
    );
    exit;
}

if (!in_array('autor', $rolesActuales, true)) {
    http_response_code(403);
    exit('No tienes permisos para acceder al panel de autor.');
}

$idUsuario = (int)$_SESSION['id_usr'];

$consultaUsuario = $mysqli->prepare(
    "SELECT nom_usr
     FROM usuario
     WHERE id_usr = ?
       AND estatus = 'activo'
     LIMIT 1"
);

$consultaUsuario->bind_param('i', $idUsuario);
$consultaUsuario->execute();
$usuario = $consultaUsuario->get_result()->fetch_assoc();
$consultaUsuario->close();

if (!$usuario) {
    cerrarSesion();
    header('Location: ' . RUTA_WEB . '/Funciones/login.php');
    exit;
}

$consultaResumen = $mysqli->prepare(
    "SELECT
        COUNT(*) AS total,
        COALESCE(SUM(estatus = 'borrador'), 0) AS borradores,
        COALESCE(SUM(estatus = 'revision'), 0) AS en_revision,
        COALESCE(SUM(estatus = 'correccion'), 0) AS correcciones,
        COALESCE(SUM(estatus = 'rechazado'), 0) AS rechazadas,
        COALESCE(SUM(estatus = 'publicado'), 0) AS publicadas,
        COALESCE(SUM(estatus = 'oculto'), 0) AS ocultas
     FROM blog
     WHERE usr_id = ?"
);

$consultaResumen->bind_param('i', $idUsuario);
$consultaResumen->execute();
$resumen = $consultaResumen->get_result()->fetch_assoc();
$consultaResumen->close();

$consultaPublicaciones = $mysqli->prepare(
    "SELECT
        id_blog,
        titulo,
        estatus,
        version_publica,
        fecha_creacion
     FROM blog
     WHERE usr_id = ?
     ORDER BY fecha_creacion DESC
     LIMIT 8"
);

$consultaPublicaciones->bind_param('i', $idUsuario);
$consultaPublicaciones->execute();
$publicaciones = $consultaPublicaciones
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaPublicaciones->close();

$csrf = generarCSRF();

function escaparPanelAutor($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function etiquetaEstadoAutor(string $estado): string
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

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Panel de autor | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <main class="contenedor contenedor-inicio">
        <header>
            <h1>Panel de autor</h1>
            <p class="subtitulo">
                Bienvenido, <?php echo escaparPanelAutor($usuario['nom_usr']); ?>.
            </p>
        </header>

        <section class="tarjeta" aria-labelledby="resumen-titulo">
            <h2 id="resumen-titulo">Resumen de tus publicaciones</h2>

            <p>
                Total:
                <strong><?php echo (int)$resumen['total']; ?></strong>
            </p>
            <p>
                Borradores:
                <strong><?php echo (int)$resumen['borradores']; ?></strong>
            </p>
            <p>
                En revisión:
                <strong><?php echo (int)$resumen['en_revision']; ?></strong>
            </p>
            <p>
                Correcciones solicitadas:
                <strong><?php echo (int)$resumen['correcciones']; ?></strong>
            </p>
            <p>
                Rechazadas:
                <strong><?php echo (int)$resumen['rechazadas']; ?></strong>
            </p>
            <p>
                Publicadas:
                <strong><?php echo (int)$resumen['publicadas']; ?></strong>
            </p>
            <p>
                Ocultas:
                <strong><?php echo (int)$resumen['ocultas']; ?></strong>
            </p>
        </section>

        <nav class="tarjeta" aria-label="Acciones de autor">
            <h2>Acciones</h2>
            <div class="enlaces">
                <a href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/publicaciones.php">
                    Crear borrador
                </a>
                <a href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php">
                    Gestionar mis publicaciones
                </a>
                <a href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Dashboards/dashboard_visor.php">
                    Ir al visor
                </a>
            </div>
        </nav>

        <section class="tarjeta" aria-labelledby="recientes-titulo">
            <h2 id="recientes-titulo">Tus publicaciones recientes</h2>

            <?php if ($publicaciones === []): ?>
                <p>No tienes publicaciones todavía.</p>
            <?php else: ?>
                <?php foreach ($publicaciones as $publicacion): ?>
                    <?php
                    $estado = (string)$publicacion['estatus'];
                    $idPublicacion = (int)$publicacion['id_blog'];

                    $puedeEditar = in_array(
                        $estado,
                        ['borrador', 'correccion'],
                        true
                    ) && $publicacion['version_publica'] === null;

                    $puedeEnviarRevision = $puedeEditar;
                    $puedeConsultar = $estado === 'publicado'
                        && $publicacion['version_publica'] !== null;
                    ?>

                    <article class="tarjeta">
                        <h3>
                            <?php
                            echo escaparPanelAutor($publicacion['titulo']);
                            ?>
                        </h3>

                        <p>
                            Estado:
                            <?php
                            echo escaparPanelAutor(
                                etiquetaEstadoAutor($estado)
                            );
                            ?>
                        </p>

                        <p>
                            Creada:
                            <?php
                            echo escaparPanelAutor(
                                date(
                                    'd/m/Y H:i',
                                    strtotime($publicacion['fecha_creacion'])
                                )
                            );
                            ?>
                        </p>

                        <?php if ($puedeEditar): ?>
                            <a
                                href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/editar_publicacion.php?id=<?php echo $idPublicacion; ?>"
                            >
                                Editar borrador
                            </a>
                        <?php endif; ?>

                        <?php if ($puedeEnviarRevision): ?>
                            <a
                                href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/enviar_revision.php?id=<?php echo $idPublicacion; ?>"
                            >
                                Enviar a revisión
                            </a>
                        <?php endif; ?>

                        <?php if ($puedeConsultar): ?>
                            <a
                                href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/ver_publicacion.php?id=<?php echo $idPublicacion; ?>"
                            >
                                Consultar publicación
                            </a>
                        <?php endif; ?>

                        <?php if ($estado === 'revision'): ?>
                            <p>
                                La publicación está pendiente de decisión
                                administrativa y no se puede editar.
                            </p>
                        <?php elseif ($estado === 'rechazado'): ?>
                            <p>
                                Esta propuesta fue rechazada y no puede volver
                                a enviarse a revisión.
                            </p>
                        <?php elseif ($estado === 'oculto'): ?>
                            <p>
                                Esta publicación está oculta y no se muestra
                                públicamente.
                            </p>
                        <?php endif; ?>
                    </article>
                <?php endforeach; ?>
            <?php endif; ?>
        </section>

        <form
            action="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Conexiones/cerrar_sesion.php"
            method="POST"
        >
            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escaparPanelAutor($csrf); ?>"
            >
            <button type="submit" class="boton-secundario">
                Cerrar sesión
            </button>
        </form>
    </main>
</body>
</html>