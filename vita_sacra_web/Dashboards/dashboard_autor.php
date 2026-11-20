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

$idUsuario = filter_var(
    $_SESSION['id_usr'] ?? null,
    FILTER_VALIDATE_INT,
    ['options' => ['min_range' => 1]]
);

if ($idUsuario === false) {
    cerrarSesion();
    header('Location: ' . RUTA_WEB . '/Funciones/login.php');
    exit;
}

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

require_once __DIR__ . '/../Funciones/componentes/cabecera.php';

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

function fechaPublicacionAutor($fecha): string
{
    if (!is_string($fecha) || $fecha === '') {
        return 'Fecha no disponible';
    }

    $marcaTiempo = strtotime($fecha);

    if ($marcaTiempo === false) {
        return 'Fecha no disponible';
    }

    return date('d/m/Y H:i', $marcaTiempo);
}

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta
        name="description"
        content="Administra tus borradores y consulta el estado de tus publicaciones en Vita Sacra."
    >
    <title>Panel de autor | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $usuario['nom_usr'],
        'autor',
        'inicio',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin" aria-labelledby="titulo-panel-autor">
            <div>
                <h1 id="titulo-panel-autor">Tu espacio de autor</h1>
                <p>
                    Hola, <?php echo escaparPanelAutor($usuario['nom_usr']); ?>.
                    Aquí puedes continuar tus borradores y dar seguimiento
                    al estado editorial de tus publicaciones.
                </p>
            </div>

            <div>
                <span class="insignia-admin">
                    <?php echo (int)($resumen['total'] ?? 0); ?>
                    publicaciones
                </span>
                <p style="margin-top: 16px;">
                    <a
                        class="boton"
                        href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/publicaciones.php"
                    >
                        Crear borrador
                    </a>
                </p>
            </div>
        </section>

        <section class="seccion-admin" aria-labelledby="titulo-resumen-autor">
            <div class="encabezado-seccion-admin">
                <div>
                    <h2 id="titulo-resumen-autor">Estado editorial</h2>
                    <p>Resumen de tus publicaciones por etapa.</p>
                </div>
            </div>

            <div class="estadisticas">
                <article class="tarjeta-estadistica">
                    <p>Borradores</p>
                    <strong class="valor-estadistica">
                        <?php echo (int)($resumen['borradores'] ?? 0); ?>
                    </strong>
                </article>

                <article class="tarjeta-estadistica tarjeta-estadistica-destacada">
                    <p>En revisión</p>
                    <strong class="valor-estadistica">
                        <?php echo (int)($resumen['en_revision'] ?? 0); ?>
                    </strong>
                </article>

                <article class="tarjeta-estadistica">
                    <p>Correcciones solicitadas</p>
                    <strong class="valor-estadistica">
                        <?php echo (int)($resumen['correcciones'] ?? 0); ?>
                    </strong>
                </article>

                <article class="tarjeta-estadistica">
                    <p>Publicadas</p>
                    <strong class="valor-estadistica">
                        <?php echo (int)($resumen['publicadas'] ?? 0); ?>
                    </strong>
                </article>

                <article class="tarjeta-estadistica">
                    <p>Rechazadas</p>
                    <strong class="valor-estadistica">
                        <?php echo (int)($resumen['rechazadas'] ?? 0); ?>
                    </strong>
                </article>

                <article class="tarjeta-estadistica">
                    <p>Ocultas</p>
                    <strong class="valor-estadistica">
                        <?php echo (int)($resumen['ocultas'] ?? 0); ?>
                    </strong>
                </article>
            </div>
        </section>

        <section class="seccion-admin" aria-labelledby="titulo-publicaciones-recientes">
            <div class="encabezado-seccion-admin">
                <div>
                    <h2 id="titulo-publicaciones-recientes">
                        Publicaciones recientes
                    </h2>
                    <p>
                        Acciones disponibles según el estado de cada publicación.
                    </p>
                </div>

                <a
                    class="boton boton-secundario"
                    href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php"
                >
                    Gestionar publicaciones
                </a>
            </div>

            <?php if ($publicaciones === []): ?>
                <div class="tarjeta-actividad">
                    <h3>Aún no tienes publicaciones</h3>
                    <p>
                        Crea un borrador para comenzar a preparar contenido
                        educativo para Vita Sacra.
                    </p>
                    <a
                        class="boton"
                        href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/publicaciones.php"
                    >
                        Crear mi primer borrador
                    </a>
                </div>
            <?php else: ?>
                <div class="actividad-admin">
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

                        <article class="tarjeta-actividad">
                            <p>
                                <span
                                    class="estado<?php echo $estado === 'revision' ? ' estado-pendiente' : ''; ?>"
                                >
                                    <?php
                                    echo escaparPanelAutor(
                                        etiquetaEstadoAutor($estado)
                                    );
                                    ?>
                                </span>
                            </p>

                            <h3>
                                <?php
                                echo escaparPanelAutor($publicacion['titulo']);
                                ?>
                            </h3>

                            <p>
                                <span class="texto-secundario">Creada:</span>
                                <?php
                                echo escaparPanelAutor(
                                    fechaPublicacionAutor(
                                        $publicacion['fecha_creacion'] ?? null
                                    )
                                );
                                ?>
                            </p>

                            <div class="enlaces">
                                <?php if ($puedeEditar): ?>
                                    <a
                                        class="boton"
                                        href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/editar_publicacion.php?id=<?php echo $idPublicacion; ?>"
                                    >
                                        Editar borrador
                                    </a>
                                <?php endif; ?>

                                <?php if ($puedeEnviarRevision): ?>
                                    <a
                                        class="boton boton-secundario"
                                        href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/enviar_revision.php?id=<?php echo $idPublicacion; ?>"
                                    >
                                        Enviar a revisión
                                    </a>
                                <?php endif; ?>

                                <?php if ($puedeConsultar): ?>
                                    <a
                                        class="boton boton-secundario"
                                        href="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Funciones/ver_publicacion.php?id=<?php echo $idPublicacion; ?>"
                                    >
                                        Consultar publicación
                                    </a>
                                <?php endif; ?>

                                <?php if ($estado === 'revision'): ?>
                                    <span class="texto-secundario">
                                        Espera la decisión editorial.
                                    </span>
                                <?php elseif ($estado === 'rechazado'): ?>
                                    <span class="texto-secundario">
                                        Esta propuesta fue rechazada y no puede
                                        volver a enviarse a revisión.
                                    </span>
                                <?php elseif ($estado === 'oculto'): ?>
                                    <span class="texto-secundario">
                                        Esta publicación está oculta y no se
                                        muestra públicamente.
                                    </span>
                                <?php endif; ?>
                            </div>
                        </article>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
        </section>
    </main>

    <footer class="pie-admin">
        <p>Vita Sacra · Educación y divulgación responsable en salud.</p>
    </footer>

    <script
        src="<?php echo escaparPanelAutor(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>