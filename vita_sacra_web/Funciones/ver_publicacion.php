<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';
require_once __DIR__ . '/componentes/cabecera.php';

$usuario = null;
$rolesActuales = [];
$idUsuario = null;

if (isset($_SESSION['id_usr']) && verificarUsuarioActual($mysqli)) {
    $idUsuario = (int)$_SESSION['id_usr'];
    $rolesActuales = obtenerRolesActuales($mysqli);

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
        $idUsuario = null;
        $rolesActuales = [];
    }
}

if (in_array('administrador', $rolesActuales, true)) {
    header(
        'Location: ' . RUTA_WEB . '/Dashboards/dashboard_admin.php',
        true,
        303
    );
    exit;
}

if (!$usuario) {
    $rolCabecera = 'visitante';
    $nombreCabecera = 'Invitado';
} elseif (in_array('autor', $rolesActuales, true)) {
    $rolCabecera = 'autor';
    $nombreCabecera = $usuario['nom_usr'];
} else {
    $rolCabecera = 'visor';
    $nombreCabecera = $usuario['nom_usr'];
}

function escaparDetallePublicacion($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function rutaDetallePublicacion($ruta): string
{
    if (!is_string($ruta) || trim($ruta) === '') {
        return '';
    }

    $ruta = trim($ruta);

    if (filter_var($ruta, FILTER_VALIDATE_URL)) {
        $esquema = strtolower((string)parse_url($ruta, PHP_URL_SCHEME));
        return in_array($esquema, ['http', 'https'], true) ? $ruta : '';
    }

    if (preg_match('/^[a-z][a-z0-9+.-]*:/i', $ruta)) {
        return '';
    }

    $ruta = str_replace('\\', '/', $ruta);
    $partes = explode('/', ltrim($ruta, '/'));

    foreach ($partes as $parte) {
        if ($parte === '..') {
            return '';
        }
    }

    $partes = array_filter(
        $partes,
        static fn(string $parte): bool =>
            $parte !== '' && $parte !== '.'
    );

    if ($partes === []) {
        return '';
    }

    return rtrim(RUTA_WEB, '/')
        . '/'
        . implode('/', array_map('rawurlencode', $partes));
}

function fechaDetallePublicacion($fecha): string
{
    if (!is_string($fecha) || $fecha === '') {
        return 'Fecha no disponible';
    }

    $marcaTiempo = strtotime($fecha);

    return $marcaTiempo === false
        ? 'Fecha no disponible'
        : date('d/m/Y', $marcaTiempo);
}

$idRecibido = $_GET['id'] ?? null;
$idPublicacion = is_scalar($idRecibido)
    ? filter_var(
        $idRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

$publicacion = null;
$bloques = [];
$fuentes = [];
$recursos = [];
$comentarios = [];
$metricasValoracion = ['total' => 0, 'promedio' => 0.0];
$miValoracion = null;

if ($idPublicacion !== false) {
    $consultaPublicacion = $mysqli->prepare(
        "SELECT
            bp.id_blog,
            bp.usr_id,
            bp.titulo,
            bp.`desc`,
            bp.img,
            bp.tipo,
            bp.fecha_publicacion,
            bp.advertencia,
            bp.id_version,
            v.plantilla_id_snapshot,
            p.nombre AS plantilla,
            c.nombre AS categoria,
            u.nom_usr AS autor
         FROM blog_publico bp
         INNER JOIN versiones_blog v
            ON v.id_version = bp.id_version
         LEFT JOIN plantillas p
            ON p.id_plantilla = v.plantilla_id_snapshot
         LEFT JOIN categorias c
            ON c.id_categoria = bp.categoria_id
         LEFT JOIN usuario u
            ON u.id_usr = bp.usr_id
         WHERE bp.id_blog = ?
         LIMIT 1"
    );

    $consultaPublicacion->bind_param('i', $idPublicacion);
    $consultaPublicacion->execute();
    $publicacion = $consultaPublicacion
        ->get_result()
        ->fetch_assoc();
    $consultaPublicacion->close();
}

if ($publicacion) {
    $idVersion = (int)$publicacion['id_version'];
    $idBlog = (int)$publicacion['id_blog'];

    $consultaBloques = $mysqli->prepare(
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
    $consultaBloques->bind_param('i', $idVersion);
    $consultaBloques->execute();
    $bloques = $consultaBloques
        ->get_result()
        ->fetch_all(MYSQLI_ASSOC);
    $consultaBloques->close();

    $consultaFuentes = $mysqli->prepare(
        "SELECT f.titulo, f.autor, f.url, f.anio
         FROM version_fuentes vf
         INNER JOIN fuentes f
            ON f.id_fuente = vf.fuente_id
         WHERE vf.version_id = ?
         ORDER BY f.titulo"
    );
    $consultaFuentes->bind_param('i', $idVersion);
    $consultaFuentes->execute();
    $fuentes = $consultaFuentes
        ->get_result()
        ->fetch_all(MYSQLI_ASSOC);
    $consultaFuentes->close();

    $consultaRecursos = $mysqli->prepare(
        "SELECT
            r.tipo,
            r.url,
            r.titulo,
            r.licencia,
            r.procedencia,
            vr.orden
         FROM version_recursos vr
         INNER JOIN recursos r
            ON r.id_recurso = vr.recurso_id
         WHERE vr.version_id = ?
           AND r.estatus = 'aprobado'
         ORDER BY vr.orden"
    );
    $consultaRecursos->bind_param('i', $idVersion);
    $consultaRecursos->execute();
    $recursos = $consultaRecursos
        ->get_result()
        ->fetch_all(MYSQLI_ASSOC);
    $consultaRecursos->close();

    $consultaComentarios = $mysqli->prepare(
        "SELECT
            cp.id_com,
            cp.usr_id,
            cp.comentario,
            cp.fecha,
            cp.com_padre_id,
            u.nom_usr AS usuario
         FROM comentarios_publicos cp
         LEFT JOIN usuario u
            ON u.id_usr = cp.usr_id
           AND u.estatus = 'activo'
         WHERE cp.blog_id = ?
         ORDER BY cp.fecha ASC, cp.id_com ASC
         LIMIT 100"
    );
    $consultaComentarios->bind_param('i', $idBlog);
    $consultaComentarios->execute();
    $comentarios = $consultaComentarios
        ->get_result()
        ->fetch_all(MYSQLI_ASSOC);
    $consultaComentarios->close();

    $consultaMetricas = $mysqli->prepare(
        "SELECT COUNT(*) AS total, AVG(estrellas) AS promedio
         FROM valoraciones
         WHERE blog_id = ?"
    );
    $consultaMetricas->bind_param('i', $idBlog);
    $consultaMetricas->execute();
    $metricas = $consultaMetricas->get_result()->fetch_assoc();
    $consultaMetricas->close();

    $metricasValoracion = [
        'total' => (int)($metricas['total'] ?? 0),
        'promedio' => $metricas['promedio'] !== null
            ? (float)$metricas['promedio']
            : 0.0
    ];

    if ($idUsuario !== null) {
        $consultaMiValoracion = $mysqli->prepare(
            "SELECT estrellas
             FROM valoraciones
             WHERE usr_id = ?
               AND blog_id = ?
             LIMIT 1"
        );
        $consultaMiValoracion->bind_param('ii', $idUsuario, $idBlog);
        $consultaMiValoracion->execute();
        $miVoto = $consultaMiValoracion
            ->get_result()
            ->fetch_assoc();
        $consultaMiValoracion->close();
        $miValoracion = $miVoto ? (int)$miVoto['estrellas'] : null;
    }
} else {
    http_response_code(404);
}

$csrf = generarCSRF();
$flashComentario = $_SESSION['flash_comentario'] ?? null;
$flashValoracion = $_SESSION['flash_valoracion'] ?? null;
unset($_SESSION['flash_comentario'], $_SESSION['flash_valoracion']);

$plantilla = $publicacion['plantilla'] ?? 'clasica';
if (!in_array($plantilla, ['clasica', 'divulgativa', 'visual'], true)) {
    $plantilla = 'clasica';
}

?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta
        name="description"
        content="<?php echo escaparDetallePublicacion($publicacion['desc'] ?? 'Publicación educativa de Vita Sacra.'); ?>"
    >
    <title>
        <?php
        echo $publicacion
            ? escaparDetallePublicacion($publicacion['titulo']) . ' | Vita Sacra'
            : 'Publicación no disponible | Vita Sacra';
        ?>
    </title>
    <link
        rel="stylesheet"
        href="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
    <style>
        .articulo-completo.plantilla-divulgativa .bloque-cita {
            border-left-color: var(--azul);
            background: var(--azul-claro);
            padding: 18px;
        }
        .articulo-completo.plantilla-visual .contenido-articulo {
            font-size: 1.08rem;
            line-height: 1.85;
        }
        .bloque-pdf, .bloque-recurso {
            margin: 20px 0;
            padding: 16px;
            border: 1px solid var(--bordes);
            border-radius: var(--radio-pequeno);
        }
    </style>
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreCabecera,
        $rolCabecera,
        'publicaciones',
        $csrf
    );
    ?>

    <?php if (!$publicacion): ?>
        <main class="contenido-visor">
            <section class="bienvenida-visor">
                <h1>Publicación no disponible</h1>
                <p>No encontramos esta publicación o ya no está disponible públicamente.</p>
                <a class="boton" href="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Dashboards/dashboard_visor.php">
                    Volver a publicaciones
                </a>
            </section>
        </main>
    <?php else: ?>
        <?php $imagenPrincipal = rutaDetallePublicacion($publicacion['img'] ?? ''); ?>

        <main class="detalle-publicacion">
            <a
                href="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Dashboards/dashboard_visor.php#publicaciones"
                class="enlace-regresar"
            >← Volver a publicaciones</a>

            <article class="articulo-completo plantilla-<?php echo escaparDetallePublicacion($plantilla); ?>">
                <header class="articulo-encabezado">
                    <span class="etiqueta">
                        <?php echo escaparDetallePublicacion($publicacion['categoria'] ?? 'General'); ?>
                    </span>
                    <h1><?php echo escaparDetallePublicacion($publicacion['titulo']); ?></h1>

                    <?php if (!empty($publicacion['desc'])): ?>
                        <p class="articulo-descripcion">
                            <?php echo escaparDetallePublicacion($publicacion['desc']); ?>
                        </p>
                    <?php endif; ?>

                    <div class="articulo-metadata">
                        <span>Autor: <?php echo escaparDetallePublicacion($publicacion['autor'] ?? 'Autor no disponible'); ?></span>
                        <span>Tipo: <?php echo escaparDetallePublicacion($publicacion['tipo']); ?></span>
                        <span>Plantilla: <?php echo escaparDetallePublicacion(ucfirst($plantilla)); ?></span>
                        <span>Publicada: <?php echo escaparDetallePublicacion(fechaDetallePublicacion($publicacion['fecha_publicacion'] ?? null)); ?></span>
                    </div>

                    <?php
                    $puedeReportarPublicacion = $idUsuario === null
                        || $idUsuario !== (int)$publicacion['usr_id'];
                    ?>
                    <?php if ($puedeReportarPublicacion): ?>
                        <p>
                            <a class="boton boton-secundario" href="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Funciones/reportar_contenido.php?tipo=publicacion&id=<?php echo (int)$publicacion['id_blog']; ?>">
                                Reportar publicación
                            </a>
                        </p>
                    <?php endif; ?>
                </header>

                <?php if ($imagenPrincipal !== ''): ?>
                    <figure class="articulo-imagen-principal">
                        <img
                            src="<?php echo escaparDetallePublicacion($imagenPrincipal); ?>"
                            alt="<?php echo escaparDetallePublicacion($publicacion['titulo']); ?>"
                            loading="lazy"
                        >
                    </figure>
                <?php endif; ?>

                <aside class="advertencia-medica">
                    <strong>Información importante</strong>
                    <p>
                        Este contenido es educativo y no sustituye la valoración,
                        diagnóstico ni tratamiento de un profesional de la salud.
                    </p>
                    <?php if (!empty($publicacion['advertencia'])): ?>
                        <p><?php echo nl2br(escaparDetallePublicacion($publicacion['advertencia'])); ?></p>
                    <?php endif; ?>
                </aside>

                <section class="contenido-articulo" aria-label="Contenido de la publicación">
                    <?php if ($bloques === []): ?>
                        <p>Esta publicación no cuenta con contenido adicional.</p>
                    <?php else: ?>
                        <?php foreach ($bloques as $bloque): ?>
                            <?php
                            $tipo = (string)$bloque['tipo'];
                            $contenido = (string)($bloque['contenido'] ?? '');
                            $tipoRecurso = (string)($bloque['tipo_recurso'] ?? '');
                            $recursoAprobado =
                                ($bloque['estatus_recurso'] ?? '') === 'aprobado';
                            $urlRecurso = $recursoAprobado
                                ? rutaDetallePublicacion($bloque['recurso_url'] ?? '')
                                : '';
                            ?>
                            <?php if ($tipo === 'titulo'): ?>
                                <h2><?php echo escaparDetallePublicacion($contenido); ?></h2>
                            <?php elseif ($tipo === 'parrafo'): ?>
                                <p class="bloque-parrafo"><?php echo nl2br(escaparDetallePublicacion($contenido)); ?></p>
                            <?php elseif ($tipo === 'lista'): ?>
                                <ul class="bloque-lista">
                                    <?php foreach (preg_split('/\r\n|\r|\n/', $contenido) ?: [] as $elemento): ?>
                                        <?php if (trim($elemento) !== ''): ?>
                                            <li><?php echo escaparDetallePublicacion(trim($elemento)); ?></li>
                                        <?php endif; ?>
                                    <?php endforeach; ?>
                                </ul>
                            <?php elseif ($tipo === 'cita'): ?>
                                <blockquote class="bloque-cita"><?php echo nl2br(escaparDetallePublicacion($contenido)); ?></blockquote>
                            <?php elseif ($tipo === 'enlace'): ?>
                                <?php
                                $urlEnlace = rutaDetallePublicacion($contenido);
                                ?>
                                <?php if ($urlEnlace !== ''): ?>
                                    <p class="bloque-recurso">
                                        <a href="<?php echo escaparDetallePublicacion($urlEnlace); ?>" target="_blank" rel="noopener noreferrer">
                                            Consultar enlace
                                        </a>
                                    </p>
                                <?php endif; ?>
                            <?php elseif ($tipo === 'imagen' && $tipoRecurso === 'imagen' && $urlRecurso !== ''): ?>
                                <figure class="bloque-imagen">
                                    <img
                                        src="<?php echo escaparDetallePublicacion($urlRecurso); ?>"
                                        alt="<?php echo escaparDetallePublicacion($bloque['recurso_titulo'] ?: 'Imagen de la publicación'); ?>"
                                        loading="lazy"
                                    >
                                    <?php if (!empty($bloque['recurso_titulo'])): ?>
                                        <figcaption><?php echo escaparDetallePublicacion($bloque['recurso_titulo']); ?></figcaption>
                                    <?php endif; ?>
                                </figure>
                            <?php elseif ($tipo === 'pdf' && $tipoRecurso === 'pdf' && $urlRecurso !== ''): ?>
                                <p class="bloque-pdf">
                                    <a href="<?php echo escaparDetallePublicacion($urlRecurso); ?>" target="_blank" rel="noopener noreferrer">
                                        <?php echo escaparDetallePublicacion($bloque['recurso_titulo'] ?: 'Abrir documento PDF'); ?>
                                    </a>
                                </p>
                            <?php elseif (
                                in_array($tipo, ['video', 'modelo_3d'], true)
                                && $tipoRecurso === ($tipo === 'video' ? 'video' : 'modelo_3d')
                                && $urlRecurso !== ''
                            ): ?>
                                <p class="bloque-recurso">
                                    <a href="<?php echo escaparDetallePublicacion($urlRecurso); ?>" target="_blank" rel="noopener noreferrer">
                                        <?php echo escaparDetallePublicacion($bloque['recurso_titulo'] ?: ($tipo === 'video' ? 'Ver video relacionado' : 'Consultar modelo 3D')); ?>
                                    </a>
                                </p>
                            <?php endif; ?>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </section>

                <?php if ($recursos !== []): ?>
                    <section class="seccion-recursos">
                        <h2>Recursos relacionados</h2>
                        <ul>
                            <?php foreach ($recursos as $recurso): ?>
                                <?php $urlRecursoLista = rutaDetallePublicacion($recurso['url'] ?? ''); ?>
                                <?php if ($urlRecursoLista !== ''): ?>
                                    <li>
                                        <a href="<?php echo escaparDetallePublicacion($urlRecursoLista); ?>" target="_blank" rel="noopener noreferrer">
                                            <?php echo escaparDetallePublicacion($recurso['titulo'] ?: 'Consultar recurso'); ?>
                                        </a>
                                        <?php if (!empty($recurso['licencia'])): ?>
                                            <span>Licencia: <?php echo escaparDetallePublicacion($recurso['licencia']); ?></span>
                                        <?php endif; ?>
                                    </li>
                                <?php endif; ?>
                            <?php endforeach; ?>
                        </ul>
                    </section>
                <?php endif; ?>

                <section class="seccion-fuentes">
                    <h2>Fuentes de información</h2>
                    <?php if ($fuentes === []): ?>
                        <p>Esta publicación aún no tiene fuentes registradas.</p>
                    <?php else: ?>
                        <ol>
                            <?php foreach ($fuentes as $fuente): ?>
                                <?php $urlFuente = rutaDetallePublicacion($fuente['url'] ?? ''); ?>
                                <li>
                                    <strong><?php echo escaparDetallePublicacion($fuente['titulo']); ?></strong>
                                    <?php if (!empty($fuente['autor'])): ?> — <?php echo escaparDetallePublicacion($fuente['autor']); ?><?php endif; ?>
                                    <?php if (!empty($fuente['anio'])): ?> (<?php echo (int)$fuente['anio']; ?>)<?php endif; ?>
                                    <?php if ($urlFuente !== ''): ?>
                                        — <a href="<?php echo escaparDetallePublicacion($urlFuente); ?>" target="_blank" rel="noopener noreferrer">Consultar fuente</a>
                                    <?php endif; ?>
                                </li>
                            <?php endforeach; ?>
                        </ol>
                    <?php endif; ?>
                </section>

                <section class="seccion-valoracion" id="valoracion">
                    <h2>Valoración educativa</h2>

                    <?php if (is_array($flashValoracion)): ?>
                        <div class="<?php echo ($flashValoracion['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>" role="status">
                            <?php echo escaparDetallePublicacion($flashValoracion['mensaje'] ?? ''); ?>
                        </div>
                    <?php endif; ?>

                    <?php if ($metricasValoracion['total'] === 0): ?>
                        <p class="valoracion-promedio">Sin valoraciones</p>
                    <?php else: ?>
                        <p class="valoracion-promedio">
                            <strong><?php echo number_format($metricasValoracion['promedio'], 1, '.', ','); ?> / 5</strong>
                            · <?php echo (int)$metricasValoracion['total']; ?>
                            <?php echo $metricasValoracion['total'] === 1 ? 'valoración' : 'valoraciones'; ?>
                        </p>
                    <?php endif; ?>

                    <?php if ($idUsuario !== null): ?>
                        <p>
                            <?php if ($miValoracion !== null): ?>
                                Tu valoración actual: <?php echo (int)$miValoracion; ?> de 5. Puedes cambiarla.
                            <?php else: ?>
                                ¿Te resultó útil esta publicación?
                            <?php endif; ?>
                        </p>

                        <form
                            class="formulario-valoracion"
                            action="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Funciones/valorar_publicacion.php"
                            method="POST"
                        >
                            <input type="hidden" name="csrf_token" value="<?php echo escaparDetallePublicacion($csrf); ?>">
                            <input type="hidden" name="id_blog" value="<?php echo (int)$publicacion['id_blog']; ?>">

                            <fieldset class="escala-estrellas">
                                <legend>Selecciona de 1 a 5 estrellas</legend>
                                <?php for ($estrella = 5; $estrella >= 1; $estrella--): ?>
                                    <input
                                        type="radio"
                                        id="estrella-<?php echo $estrella; ?>"
                                        name="estrellas"
                                        value="<?php echo $estrella; ?>"
                                        <?php echo $miValoracion === $estrella ? 'checked' : ''; ?>
                                        required
                                    >
                                    <label for="estrella-<?php echo $estrella; ?>" title="<?php echo $estrella; ?> estrellas">★</label>
                                <?php endfor; ?>
                            </fieldset>

                            <button class="boton" type="submit">
                                <?php echo $miValoracion === null ? 'Registrar valoración' : 'Actualizar valoración'; ?>
                            </button>
                        </form>
                        <small class="texto-secundario">
                            La valoración expresa utilidad y no certifica calidad médica.
                        </small>
                    <?php else: ?>
                        <p>
                            <a class="boton boton-secundario" href="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Funciones/login.php">
                                Inicia sesión para valorar
                            </a>
                        </p>
                    <?php endif; ?>
                </section>

                <section class="seccion-recursos" id="comentarios">
                    <h2>Comentarios (<?php echo count($comentarios); ?>)</h2>

                    <?php if (is_array($flashComentario)): ?>
                        <div class="<?php echo ($flashComentario['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>" role="status">
                            <?php echo escaparDetallePublicacion($flashComentario['mensaje'] ?? ''); ?>
                        </div>
                    <?php endif; ?>

                    <?php if ($comentarios === []): ?>
                        <div class="mensaje-vacio">Todavía no hay comentarios aprobados.</div>
                    <?php else: ?>
                        <div class="actividad-admin">
                            <?php foreach ($comentarios as $comentario): ?>
                                <article class="tarjeta-actividad">
                                    <p>
                                        <strong><?php echo escaparDetallePublicacion($comentario['usuario'] ?? 'Usuario'); ?></strong>
                                        · <?php echo escaparDetallePublicacion(fechaDetallePublicacion($comentario['fecha'])); ?>
                                    </p>
                                    <?php if ($comentario['com_padre_id'] !== null): ?>
                                        <span class="estado">Respuesta</span>
                                    <?php endif; ?>
                                    <p><?php echo nl2br(escaparDetallePublicacion($comentario['comentario'])); ?></p>

                                    <?php
                                    $puedeReportarComentario = $idUsuario === null
                                        || $idUsuario !== (int)$comentario['usr_id'];
                                    ?>
                                    <?php if ($puedeReportarComentario): ?>
                                        <a href="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Funciones/reportar_contenido.php?tipo=comentario&id=<?php echo (int)$comentario['id_com']; ?>">
                                            Reportar comentario
                                        </a>
                                    <?php endif; ?>
                                </article>
                            <?php endforeach; ?>
                        </div>
                    <?php endif; ?>

                    <?php if ($idUsuario !== null): ?>
                        <form action="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Funciones/comentar_publicacion.php" method="POST">
                            <input type="hidden" name="csrf_token" value="<?php echo escaparDetallePublicacion($csrf); ?>">
                            <input type="hidden" name="id_blog" value="<?php echo (int)$publicacion['id_blog']; ?>">
                            <label for="comentario">Escribe un comentario</label>
                            <textarea id="comentario" name="comentario" rows="5" maxlength="3000" required></textarea>
                            <small>Máximo 3000 caracteres. Los comentarios nuevos se revisan antes de mostrarse.</small>
                            <p><button class="boton" type="submit">Enviar comentario</button></p>
                        </form>
                    <?php else: ?>
                        <p>
                            <a class="boton" href="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Funciones/login.php">
                                Inicia sesión para comentar
                            </a>
                        </p>
                    <?php endif; ?>
                </section>
            </article>
        </main>
    <?php endif; ?>

    <footer class="pie-visor">
        <p>Vita Sacra · Educación y divulgación responsable en salud.</p>
        <p>
            El contenido tiene fines informativos y no sustituye la valoración
            de un profesional de la salud.
        </p>
    </footer>

    <script
        src="<?php echo escaparDetallePublicacion(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>