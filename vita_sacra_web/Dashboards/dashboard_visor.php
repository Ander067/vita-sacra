<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

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

if (!isset($usuario)) {
    $rolCabecera = 'visitante';
    $nombreCabecera = 'Invitado';
} elseif (in_array('autor', $rolesActuales, true)) {
    $rolCabecera = 'autor';
    $nombreCabecera = $usuario['nom_usr'];
} else {
    $rolCabecera = 'visor';
    $nombreCabecera = $usuario['nom_usr'];
}

$consultaCategorias = $mysqli->prepare(
    "SELECT id_categoria, nombre
     FROM categorias
     WHERE activa = 1
     ORDER BY nombre ASC"
);

$consultaCategorias->execute();
$categorias = $consultaCategorias
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaCategorias->close();

$idsCategorias = array_map(
    static fn(array $categoria): int => (int)$categoria['id_categoria'],
    $categorias
);

$busquedaRecibida = $_GET['buscar'] ?? '';
$busqueda = is_string($busquedaRecibida)
    ? trim(mb_substr($busquedaRecibida, 0, 100, 'UTF-8'))
    : '';

$categoriaRecibida = $_GET['categoria'] ?? '0';
$categoriaSeleccionada = is_scalar($categoriaRecibida)
    ? filter_var(
        $categoriaRecibida,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 0]]
    )
    : false;

if (
    $categoriaSeleccionada === false
    || (
        $categoriaSeleccionada !== 0
        && !in_array($categoriaSeleccionada, $idsCategorias, true)
    )
) {
    $categoriaSeleccionada = 0;
}

$paginaRecibida = $_GET['pagina'] ?? '1';
$pagina = is_scalar($paginaRecibida)
    ? filter_var(
        $paginaRecibida,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

if ($pagina === false) {
    $pagina = 1;
}

$publicacionesPorPagina = 9;

$consultaTotal = $mysqli->prepare(
    "SELECT COUNT(*) AS total
     FROM blog_publico bp
     WHERE (
        ? = ''
        OR bp.titulo LIKE CONCAT('%', ?, '%')
        OR bp.`desc` LIKE CONCAT('%', ?, '%')
     )
       AND (? = 0 OR bp.categoria_id = ?)"
);

$consultaTotal->bind_param(
    'sssii',
    $busqueda,
    $busqueda,
    $busqueda,
    $categoriaSeleccionada,
    $categoriaSeleccionada
);

$consultaTotal->execute();
$datosTotal = $consultaTotal->get_result()->fetch_assoc();
$consultaTotal->close();

$totalPublicaciones = (int)($datosTotal['total'] ?? 0);
$totalPaginas = max(
    1,
    (int)ceil($totalPublicaciones / $publicacionesPorPagina)
);

$pagina = min($pagina, $totalPaginas);
$desplazamiento = ($pagina - 1) * $publicacionesPorPagina;

$consultaPublicaciones = $mysqli->prepare(
    "SELECT
        bp.id_blog,
        bp.usr_id,
        bp.titulo,
        bp.`desc`,
        bp.img,
        bp.tipo,
        bp.fecha_publicacion,
        bp.advertencia,
        c.nombre AS categoria,
        u.nom_usr AS autor
     FROM blog_publico bp
     LEFT JOIN categorias c
        ON c.id_categoria = bp.categoria_id
     LEFT JOIN usuario u
        ON u.id_usr = bp.usr_id
     WHERE (
        ? = ''
        OR bp.titulo LIKE CONCAT('%', ?, '%')
        OR bp.`desc` LIKE CONCAT('%', ?, '%')
     )
       AND (? = 0 OR bp.categoria_id = ?)
     ORDER BY bp.fecha_publicacion DESC, bp.id_blog DESC
     LIMIT ? OFFSET ?"
);

$consultaPublicaciones->bind_param(
    'sssiiii',
    $busqueda,
    $busqueda,
    $busqueda,
    $categoriaSeleccionada,
    $categoriaSeleccionada,
    $publicacionesPorPagina,
    $desplazamiento
);

$consultaPublicaciones->execute();
$publicaciones = $consultaPublicaciones
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaPublicaciones->close();

$totalGuardados = null;

if ($idUsuario !== null) {
    $consultaGuardados = $mysqli->prepare(
        "SELECT COUNT(*) AS total
         FROM guardados g
         INNER JOIN blog_publico bp
            ON bp.id_blog = g.blog_id
         WHERE g.usr_id = ?"
    );

    $consultaGuardados->bind_param('i', $idUsuario);
    $consultaGuardados->execute();
    $datosGuardados = $consultaGuardados
        ->get_result()
        ->fetch_assoc();
    $consultaGuardados->close();

    $totalGuardados = (int)($datosGuardados['total'] ?? 0);
}

$csrf = generarCSRF();

require_once __DIR__ . '/../Funciones/componentes/cabecera.php';

function escaparCatalogo($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function rutaImagenCatalogo($imagen): string
{
    if (!is_string($imagen) || trim($imagen) === '') {
        return '';
    }

    $imagen = trim($imagen);

    if (preg_match('/^https?:\/\//i', $imagen)) {
        return filter_var($imagen, FILTER_VALIDATE_URL) ? $imagen : '';
    }

    if (preg_match('/^[a-z][a-z0-9+.-]*:/i', $imagen)) {
        return '';
    }

    $imagen = str_replace('\\', '/', $imagen);
    $partes = explode('/', ltrim($imagen, '/'));

    foreach ($partes as $parte) {
        if ($parte === '..') {
            return '';
        }
    }

    $partes = array_filter(
        $partes,
        static fn(string $parte): bool => $parte !== '' && $parte !== '.'
    );

    if ($partes === []) {
        return '';
    }

    return rtrim(RUTA_WEB, '/')
        . '/'
        . implode('/', array_map('rawurlencode', $partes));
}

function fechaCatalogo($fecha): string
{
    if (!is_string($fecha) || $fecha === '') {
        return 'Fecha no disponible';
    }

    $marcaTiempo = strtotime($fecha);

    return $marcaTiempo === false
        ? 'Fecha no disponible'
        : date('d/m/Y', $marcaTiempo);
}

function urlCatalogo(array $parametros): string
{
    $parametros = array_filter(
        $parametros,
        static fn($valor): bool => $valor !== null && $valor !== ''
    );

    return rtrim(RUTA_WEB, '/')
        . '/Dashboards/dashboard_visor.php?'
        . http_build_query($parametros);
}

$parametrosFiltro = [
    'buscar' => $busqueda,
    'categoria' => $categoriaSeleccionada
];

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta
        name="description"
        content="Explora publicaciones educativas de Vita Sacra sobre salud y bienestar."
    >
    <title>Explorar salud y bienestar | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparCatalogo(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreCabecera,
        $rolCabecera,
        'inicio',
        $csrf
    );
    ?>

    <main class="contenido-visor">
        <section class="bienvenida-visor" aria-labelledby="titulo-bienvenida">
            <span class="etiqueta">Educación para el bienestar</span>
            <h1 id="titulo-bienvenida">
                Información de salud para aprender y cuidarte mejor
            </h1>
            <p>
                Explora contenido educativo organizado por temas. Las
                publicaciones muestran su autoría y fecha, y cuando corresponde
                incluyen fuentes para que puedas consultarlas.
            </p>
            <p class="texto-secundario">
                El contenido es informativo y no sustituye la atención de un
                profesional de la salud.
            </p>

            <?php if ($totalGuardados !== null): ?>
                <p>
                    Tienes
                    <strong><?php echo $totalGuardados; ?></strong>
                    publicaciones guardadas.
                </p>
            <?php endif; ?>
        </section>

        <section class="seccion-visor" id="categorias">
            <h2>Explora por tema</h2>

            <div class="categorias">
                <a
                    class="tarjeta-categoria"
                    href="<?php echo escaparCatalogo(urlCatalogo(['buscar' => $busqueda])); ?>#publicaciones"
                >
                    <h3>Todos los temas</h3>
                </a>

                <?php foreach ($categorias as $categoria): ?>
                    <a
                        class="tarjeta-categoria"
                        href="<?php
                        echo escaparCatalogo(
                            urlCatalogo([
                                'buscar' => $busqueda,
                                'categoria' => (int)$categoria['id_categoria']
                            ])
                        );
                        ?>#publicaciones"
                    >
                        <h3>
                            <?php echo escaparCatalogo($categoria['nombre']); ?>
                        </h3>
                    </a>
                <?php endforeach; ?>
            </div>

            <?php if ($categorias === []): ?>
                <p class="mensaje-vacio">
                    No hay categorías disponibles actualmente.
                </p>
            <?php endif; ?>
        </section>

        <section class="seccion-visor" id="publicaciones">
            <div class="encabezado-seccion-admin">
                <div>
                    <h2>Publicaciones</h2>
                    <p>
                        <?php echo $totalPublicaciones; ?>
                        resultado<?php echo $totalPublicaciones === 1 ? '' : 's'; ?>
                    </p>
                </div>
            </div>

            <form
                class="buscador-visor"
                method="GET"
                action="<?php echo escaparCatalogo(RUTA_WEB); ?>/Dashboards/dashboard_visor.php#publicaciones"
            >
                <label for="buscar-publicacion">
                    Buscar por título o contenido
                </label>
                <input
                    id="buscar-publicacion"
                    type="search"
                    name="buscar"
                    maxlength="100"
                    placeholder="Ej. prevención, bienestar..."
                    value="<?php echo escaparCatalogo($busqueda); ?>"
                >

                <label for="categoria-publicacion">Categoría</label>
                <select
                    id="categoria-publicacion"
                    name="categoria"
                >
                    <option value="0">Todas las categorías</option>
                    <?php foreach ($categorias as $categoria): ?>
                        <option
                            value="<?php echo (int)$categoria['id_categoria']; ?>"
                            <?php
                            echo $categoriaSeleccionada
                                === (int)$categoria['id_categoria']
                                ? 'selected'
                                : '';
                            ?>
                        >
                            <?php echo escaparCatalogo($categoria['nombre']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <button class="boton" type="submit">Buscar</button>
            </form>

            <?php if ($publicaciones !== []): ?>
                <div class="publicaciones">
                    <?php foreach ($publicaciones as $publicacion): ?>
                        <?php
                        $imagen = rutaImagenCatalogo(
                            $publicacion['img'] ?? ''
                        );

                        $descripcion = trim(strip_tags(
                            (string)($publicacion['desc'] ?? '')
                        ));

                        if (mb_strlen($descripcion, 'UTF-8') > 160) {
                            $descripcion = mb_substr(
                                $descripcion,
                                0,
                                160,
                                'UTF-8'
                            ) . '…';
                        }
                        ?>

                        <article class="tarjeta-publicacion">
                            <?php if ($imagen !== ''): ?>
                                <img
                                    src="<?php echo escaparCatalogo($imagen); ?>"
                                    alt=""
                                    class="imagen-publicacion"
                                    loading="lazy"
                                >
                            <?php else: ?>
                                <div
                                    class="imagen-publicacion"
                                    aria-hidden="true"
                                ></div>
                            <?php endif; ?>

                            <div class="contenido-publicacion">
                                <span class="etiqueta">
                                    <?php
                                    echo escaparCatalogo(
                                        $publicacion['categoria']
                                            ?? 'General'
                                    );
                                    ?>
                                </span>

                                <h3>
                                    <?php
                                    echo escaparCatalogo(
                                        $publicacion['titulo']
                                    );
                                    ?>
                                </h3>

                                <?php if ($descripcion !== ''): ?>
                                    <p><?php echo escaparCatalogo($descripcion); ?></p>
                                <?php endif; ?>

                                <?php if (!empty($publicacion['advertencia'])): ?>
                                    <div class="advertencia">
                                        <strong>Nota:</strong>
                                        <?php
                                        echo escaparCatalogo(
                                            $publicacion['advertencia']
                                        );
                                        ?>
                                    </div>
                                <?php endif; ?>

                                <div class="informacion-publicacion">
                                    <span>
                                        Autor:
                                        <?php
                                        echo escaparCatalogo(
                                            $publicacion['autor']
                                                ?? 'Autor no disponible'
                                        );
                                        ?>
                                    </span>
                                    <span>
                                        <?php
                                        echo escaparCatalogo(
                                            fechaCatalogo(
                                                $publicacion['fecha_publicacion']
                                                    ?? null
                                            )
                                        );
                                        ?>
                                    </span>
                                </div>

                                <a
                                    href="<?php echo escaparCatalogo(RUTA_WEB); ?>/Funciones/ver_publicacion.php?id=<?php echo (int)$publicacion['id_blog']; ?>"
                                    class="btn-leer-publicacion"
                                >
                                    Leer publicación
                                </a>
                            </div>
                        </article>
                    <?php endforeach; ?>
                </div>

                <?php if ($totalPaginas > 1): ?>
                    <nav class="enlaces" aria-label="Paginación de publicaciones">
                        <?php if ($pagina > 1): ?>
                            <a
                                class="boton boton-secundario"
                                href="<?php
                                echo escaparCatalogo(
                                    urlCatalogo(
                                        $parametrosFiltro
                                        + ['pagina' => $pagina - 1]
                                    )
                                );
                                ?>#publicaciones"
                            >
                                Anterior
                            </a>
                        <?php endif; ?>

                        <span class="texto-secundario">
                            Página <?php echo $pagina; ?>
                            de <?php echo $totalPaginas; ?>
                        </span>

                        <?php if ($pagina < $totalPaginas): ?>
                            <a
                                class="boton boton-secundario"
                                href="<?php
                                echo escaparCatalogo(
                                    urlCatalogo(
                                        $parametrosFiltro
                                        + ['pagina' => $pagina + 1]
                                    )
                                );
                                ?>#publicaciones"
                            >
                                Siguiente
                            </a>
                        <?php endif; ?>
                    </nav>
                <?php endif; ?>
            <?php else: ?>
                <div class="mensaje-vacio">
                    <h3>No encontramos publicaciones</h3>
                    <p>
                        Prueba con otra búsqueda o selecciona una categoría
                        diferente.
                    </p>
                    <a
                        class="boton boton-secundario"
                        href="<?php echo escaparCatalogo(RUTA_WEB); ?>/Dashboards/dashboard_visor.php#publicaciones"
                    >
                        Limpiar filtros
                    </a>
                </div>
            <?php endif; ?>
        </section>
    </main>

    <footer class="pie-visor">
        <p>Vita Sacra · Educación y divulgación responsable en salud.</p>
        <p>
            El contenido tiene fines informativos y no sustituye la valoración
            de un profesional de la salud.
        </p>
    </footer>

    <script
        src="<?php echo escaparCatalogo(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>