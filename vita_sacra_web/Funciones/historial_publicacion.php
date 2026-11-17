<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereUsuarioActual($mysqli);

$rolesActuales = obtenerRolesActuales($mysqli);
$esAdministrador = in_array('administrador', $rolesActuales, true);
$esAutor = in_array('autor', $rolesActuales, true);
$idUsuario = (int)$_SESSION['id_usr'];

if (!$esAdministrador && !$esAutor) {
    http_response_code(403);
    exit('No tienes permisos para consultar historiales editoriales.');
}

function escaparHistorialEditorial($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function etiquetaEstadoHistorial(string $estado): string
{
    $etiquetas = [
        'borrador' => 'Borrador',
        'revision' => 'En revisión',
        'correccion' => 'Corrección solicitada',
        'rechazado' => 'Rechazada',
        'publicado' => 'Publicado',
        'oculto' => 'Oculto'
    ];

    return $etiquetas[$estado] ?? 'Estado no reconocido';
}

function etiquetaDecisionHistorial(string $decision): string
{
    $etiquetas = [
        'aprobada' => 'Aprobada y publicada',
        'correccion' => 'Correcciones solicitadas',
        'rechazada' => 'Rechazada',
        'oculta' => 'Publicación ocultada'
    ];

    return $etiquetas[$decision] ?? 'Decisión no reconocida';
}

function fechaHistorial($fecha): string
{
    if (!is_string($fecha) || $fecha === '') {
        return 'No disponible';
    }

    $marcaTiempo = strtotime($fecha);

    return $marcaTiempo === false
        ? 'No disponible'
        : date('d/m/Y H:i', $marcaTiempo);
}

$idRecibido = $_GET['id'] ?? null;
$idBlog = filter_var(
    $idRecibido,
    FILTER_VALIDATE_INT,
    ['options' => ['min_range' => 1]]
);

if ($idBlog === false) {
    http_response_code(400);
    exit('El identificador de la publicación no es válido.');
}

$administrador = $esAdministrador ? 1 : 0;

$consultaPublicacion = $mysqli->prepare(
    "SELECT
        b.id_blog,
        b.usr_id,
        b.titulo,
        b.`desc`,
        b.tipo,
        b.estatus,
        b.version_publica,
        b.fecha_creacion,
        b.fecha_publicacion,
        u.nom_usr AS autor,
        c.nombre AS categoria
     FROM blog b
     INNER JOIN usuario u ON u.id_usr = b.usr_id
     LEFT JOIN categorias c ON c.id_categoria = b.categoria_id
     WHERE b.id_blog = ?
       AND (? = 1 OR b.usr_id = ?)
     LIMIT 1"
);

$consultaPublicacion->bind_param(
    'iii',
    $idBlog,
    $administrador,
    $idUsuario
);

$consultaPublicacion->execute();
$publicacion = $consultaPublicacion
    ->get_result()
    ->fetch_assoc();
$consultaPublicacion->close();

if (!$publicacion) {
    http_response_code(404);
    exit('La publicación no existe o no tienes permiso para consultar su historial.');
}

$consultaVersiones = $mysqli->prepare(
    "SELECT id_version, numero, advertencia, fecha
     FROM versiones_blog
     WHERE blog_id = ?
     ORDER BY numero DESC"
);

$consultaVersiones->bind_param('i', $idBlog);
$consultaVersiones->execute();
$versiones = $consultaVersiones
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaVersiones->close();

$consultaBloques = $mysqli->prepare(
    "SELECT
        b.version_id,
        b.orden,
        b.tipo,
        b.contenido,
        r.url AS recurso_url,
        r.titulo AS recurso_titulo
     FROM bloques_version b
     INNER JOIN versiones_blog v ON v.id_version = b.version_id
     LEFT JOIN recursos r ON r.id_recurso = b.recurso_id
     WHERE v.blog_id = ?
     ORDER BY v.numero DESC, b.orden ASC"
);

$consultaBloques->bind_param('i', $idBlog);
$consultaBloques->execute();
$resultadoBloques = $consultaBloques->get_result();
$bloquesPorVersion = [];

while ($bloque = $resultadoBloques->fetch_assoc()) {
    $idVersion = (int)$bloque['version_id'];
    $bloquesPorVersion[$idVersion][] = $bloque;
}

$consultaBloques->close();

$consultaFuentes = $mysqli->prepare(
    "SELECT
        vf.version_id,
        f.titulo,
        f.autor,
        f.url,
        f.anio
     FROM version_fuentes vf
     INNER JOIN versiones_blog v ON v.id_version = vf.version_id
     INNER JOIN fuentes f ON f.id_fuente = vf.fuente_id
     WHERE v.blog_id = ?
     ORDER BY v.numero DESC, f.titulo ASC"
);

$consultaFuentes->bind_param('i', $idBlog);
$consultaFuentes->execute();
$resultadoFuentes = $consultaFuentes->get_result();
$fuentesPorVersion = [];

while ($fuente = $resultadoFuentes->fetch_assoc()) {
    $idVersion = (int)$fuente['version_id'];
    $fuentesPorVersion[$idVersion][] = $fuente;
}

$consultaFuentes->close();

$consultaDecisiones = $mysqli->prepare(
    "SELECT
        r.version_id,
        r.decision,
        r.observacion,
        r.fecha,
        u.nom_usr AS administrador
     FROM revisiones_blog r
     INNER JOIN versiones_blog v ON v.id_version = r.version_id
     INNER JOIN usuario u ON u.id_usr = r.administrador_id
     WHERE v.blog_id = ?
     ORDER BY r.fecha DESC"
);

$consultaDecisiones->bind_param('i', $idBlog);
$consultaDecisiones->execute();
$resultadoDecisiones = $consultaDecisiones->get_result();
$decisionesPorVersion = [];

while ($decision = $resultadoDecisiones->fetch_assoc()) {
    $idVersion = (int)$decision['version_id'];
    $decisionesPorVersion[$idVersion][] = $decision;
}

$consultaDecisiones->close();

$csrf = generarCSRF();

$enlacePanel = $esAdministrador
    ? RUTA_WEB . '/Dashboards/dashboard_admin.php'
    : RUTA_WEB . '/Dashboards/dashboard_autor.php';

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Historial editorial | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparHistorialEditorial(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <main class="contenedor contenedor-inicio">
        <header>
            <h1>Historial editorial</h1>
            <p class="subtitulo">
                Registro de versiones y decisiones de la publicación
            </p>
        </header>

        <nav class="enlaces" aria-label="Navegación">
            <a href="<?php echo escaparHistorialEditorial($enlacePanel); ?>">
                Volver a mi panel
            </a>
            <a href="<?php echo escaparHistorialEditorial(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php">
                Gestionar publicaciones
            </a>

            <?php if ($publicacion['estatus'] === 'publicado'): ?>
                <a
                    href="<?php echo escaparHistorialEditorial(RUTA_WEB); ?>/Funciones/ver_publicacion.php?id=<?php echo (int)$publicacion['id_blog']; ?>"
                >
                    Ver publicación pública
                </a>
            <?php endif; ?>
        </nav>

        <section class="tarjeta">
            <h2><?php echo escaparHistorialEditorial($publicacion['titulo']); ?></h2>

            <p>
                <strong>Autor:</strong>
                <?php echo escaparHistorialEditorial($publicacion['autor']); ?>
            </p>
            <p>
                <strong>Categoría:</strong>
                <?php
                echo escaparHistorialEditorial(
                    $publicacion['categoria'] ?? 'Sin categoría'
                );
                ?>
            </p>
            <p>
                <strong>Tipo:</strong>
                <?php echo escaparHistorialEditorial($publicacion['tipo']); ?>
            </p>
            <p>
                <strong>Estado actual:</strong>
                <?php
                echo escaparHistorialEditorial(
                    etiquetaEstadoHistorial($publicacion['estatus'])
                );
                ?>
            </p>
            <p>
                <strong>Creada:</strong>
                <?php
                echo escaparHistorialEditorial(
                    fechaHistorial($publicacion['fecha_creacion'])
                );
                ?>
            </p>

            <?php if ($publicacion['fecha_publicacion'] !== null): ?>
                <p>
                    <strong>Fecha de publicación:</strong>
                    <?php
                    echo escaparHistorialEditorial(
                        fechaHistorial($publicacion['fecha_publicacion'])
                    );
                    ?>
                </p>
            <?php endif; ?>
        </section>

        <section aria-labelledby="versiones-titulo">
            <h2 id="versiones-titulo">Versiones editoriales</h2>

            <?php if ($versiones === []): ?>
                <article class="tarjeta">
                    <p>Esta publicación todavía no tiene versiones registradas.</p>
                </article>
            <?php else: ?>
                <?php foreach ($versiones as $version): ?>
                    <?php
                    $idVersion = (int)$version['id_version'];
                    $numeroVersion = (int)$version['numero'];
                    $esVersionPublica =
                        $publicacion['version_publica'] !== null
                        && $numeroVersion === (int)$publicacion['version_publica'];

                    $bloques = $bloquesPorVersion[$idVersion] ?? [];
                    $fuentes = $fuentesPorVersion[$idVersion] ?? [];
                    $decisiones = $decisionesPorVersion[$idVersion] ?? [];
                    ?>

                    <article class="tarjeta">
                        <h3>
                            Versión <?php echo $numeroVersion; ?>

                            <?php if ($esVersionPublica): ?>
                                — Versión pública
                            <?php endif; ?>
                        </h3>

                        <p>
                            <strong>Fecha de versión:</strong>
                            <?php
                            echo escaparHistorialEditorial(
                                fechaHistorial($version['fecha'])
                            );
                            ?>
                        </p>

                        <?php if (!empty($version['advertencia'])): ?>
                            <section>
                                <h4>Advertencia informativa</h4>
                                <p>
                                    <?php
                                    echo nl2br(
                                        escaparHistorialEditorial(
                                            $version['advertencia']
                                        )
                                    );
                                    ?>
                                </p>
                            </section>
                        <?php endif; ?>

                        <section>
                            <h4>Contenido</h4>

                            <?php if ($bloques === []): ?>
                                <p>No hay bloques registrados para esta versión.</p>
                            <?php else: ?>
                                <?php foreach ($bloques as $bloque): ?>
                                    <div class="bloque-historico">
                                        <strong>
                                            <?php
                                            echo escaparHistorialEditorial(
                                                ucfirst((string)$bloque['tipo'])
                                            );
                                            ?>:
                                        </strong>

                                        <?php if (!empty($bloque['contenido'])): ?>
                                            <p>
                                                <?php
                                                echo nl2br(
                                                    escaparHistorialEditorial(
                                                        $bloque['contenido']
                                                    )
                                                );
                                                ?>
                                            </p>
                                        <?php endif; ?>

                                        <?php
                                        $urlRecurso = (string)(
                                            $bloque['recurso_url'] ?? ''
                                        );

                                        $urlRecursoValida =
                                            $urlRecurso !== ''
                                            && filter_var(
                                                $urlRecurso,
                                                FILTER_VALIDATE_URL
                                            )
                                            && in_array(
                                                strtolower((string)parse_url(
                                                    $urlRecurso,
                                                    PHP_URL_SCHEME
                                                )),
                                                ['http', 'https'],
                                                true
                                            );
                                        ?>

                                        <?php if ($urlRecursoValida): ?>
                                            <p>
                                                <a
                                                    href="<?php echo escaparHistorialEditorial($urlRecurso); ?>"
                                                    target="_blank"
                                                    rel="noopener noreferrer"
                                                >
                                                    <?php
                                                    echo escaparHistorialEditorial(
                                                        $bloque['recurso_titulo']
                                                            ?: 'Consultar recurso'
                                                    );
                                                    ?>
                                                </a>
                                            </p>
                                        <?php endif; ?>
                                    </div>
                                <?php endforeach; ?>
                            <?php endif; ?>
                        </section>

                        <section>
                            <h4>Fuentes</h4>

                            <?php if ($fuentes === []): ?>
                                <p>Esta versión no tiene fuentes asociadas.</p>
                            <?php else: ?>
                                <ol>
                                    <?php foreach ($fuentes as $fuente): ?>
                                        <li>
                                            <strong>
                                                <?php
                                                echo escaparHistorialEditorial(
                                                    $fuente['titulo']
                                                );
                                                ?>
                                            </strong>

                                            <?php if (!empty($fuente['autor'])): ?>
                                                — <?php
                                                echo escaparHistorialEditorial(
                                                    $fuente['autor']
                                                );
                                                ?>
                                            <?php endif; ?>

                                            <?php if (!empty($fuente['anio'])): ?>
                                                (<?php echo (int)$fuente['anio']; ?>)
                                            <?php endif; ?>

                                            <?php
                                            $urlFuente = (string)(
                                                $fuente['url'] ?? ''
                                            );

                                            $urlFuenteValida =
                                                $urlFuente !== ''
                                                && filter_var(
                                                    $urlFuente,
                                                    FILTER_VALIDATE_URL
                                                )
                                                && in_array(
                                                    strtolower((string)parse_url(
                                                        $urlFuente,
                                                        PHP_URL_SCHEME
                                                    )),
                                                    ['http', 'https'],
                                                    true
                                                );
                                            ?>

                                            <?php if ($urlFuenteValida): ?>
                                                —
                                                <a
                                                    href="<?php echo escaparHistorialEditorial($urlFuente); ?>"
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
                        </section>

                        <section>
                            <h4>Decisiones administrativas</h4>

                            <?php if ($decisiones === []): ?>
                                <p>No hay decisiones registradas para esta versión.</p>
                            <?php else: ?>
                                <ol>
                                    <?php foreach ($decisiones as $decision): ?>
                                        <li>
                                            <strong>
                                                <?php
                                                echo escaparHistorialEditorial(
                                                    etiquetaDecisionHistorial(
                                                        $decision['decision']
                                                    )
                                                );
                                                ?>
                                            </strong>
                                            — <?php
                                            echo escaparHistorialEditorial(
                                                fechaHistorial($decision['fecha'])
                                            );
                                            ?>,
                                            por
                                            <?php
                                            echo escaparHistorialEditorial(
                                                $decision['administrador']
                                            );
                                            ?>

                                            <?php if (!empty($decision['observacion'])): ?>
                                                <p>
                                                    <?php
                                                    echo nl2br(
                                                        escaparHistorialEditorial(
                                                            $decision['observacion']
                                                        )
                                                    );
                                                    ?>
                                                </p>
                                            <?php endif; ?>
                                        </li>
                                    <?php endforeach; ?>
                                </ol>
                            <?php endif; ?>
                        </section>
                    </article>
                <?php endforeach; ?>
            <?php endif; ?>
        </section>

        <form
            action="<?php echo escaparHistorialEditorial(RUTA_WEB); ?>/Conexiones/cerrar_sesion.php"
            method="POST"
        >
            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escaparHistorialEditorial($csrf); ?>"
            >
            <button type="submit" class="boton-secundario">
                Cerrar sesión
            </button>
        </form>
    </main>
</body>
</html>