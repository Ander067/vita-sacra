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

$rolCabecera = !$usuario
    ? 'visitante'
    : (
        in_array('administrador', $rolesActuales, true)
            ? 'administrador'
            : (
                in_array('autor', $rolesActuales, true)
                    ? 'autor'
                    : 'visor'
            )
    );
$nombreCabecera = $usuario
    ? $usuario['nom_usr']
    : 'Invitado';

function escaparDirectorioEstablecimientos($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function urlSitioEstablecimiento($url): string
{
    if (!is_string($url) || trim($url) === '') {
        return '';
    }

    $url = trim($url);

    if (
        !filter_var($url, FILTER_VALIDATE_URL)
        || !in_array(
            strtolower((string)parse_url($url, PHP_URL_SCHEME)),
            ['http', 'https'],
            true
        )
    ) {
        return '';
    }

    return $url;
}

function urlMapaEstablecimiento(string $direccion): string
{
    return 'https://www.google.com/maps/search/?api=1&query='
        . rawurlencode($direccion);
}

$idRecibido = $_GET['id'] ?? null;
$idEstablecimiento = is_scalar($idRecibido)
    ? filter_var(
        $idRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

$qRecibido = $_GET['q'] ?? '';
$busqueda = is_string($qRecibido)
    ? trim($qRecibido)
    : '';

if (mb_strlen($busqueda, 'UTF-8') > 100) {
    $busqueda = mb_substr($busqueda, 0, 100, 'UTF-8');
}

$tipoRecibido = $_GET['tipo'] ?? '';
$tipoFiltro = is_string($tipoRecibido)
    ? trim($tipoRecibido)
    : '';

$tiposDisponibles = $mysqli->query(
    "SELECT DISTINCT tipo
     FROM establecimientos
     WHERE estatus = 'aprobado'
     ORDER BY tipo"
)->fetch_all(MYSQLI_COLUMN);

if (!in_array($tipoFiltro, $tiposDisponibles, true)) {
    $tipoFiltro = '';
}

$detalle = null;
$establecimientos = [];
$totalResultados = 0;
$pagina = 1;
$porPagina = 12;
$totalPaginas = 1;

if ($idEstablecimiento !== false) {
    $idEstablecimiento = (int)$idEstablecimiento;

    $consultaDetalle = $mysqli->prepare(
        "SELECT
            id_establecimiento,
            nombre,
            tipo,
            descripcion,
            direccion,
            telefono,
            sitio_web
         FROM establecimientos
         WHERE id_establecimiento = ?
           AND estatus = 'aprobado'
         LIMIT 1"
    );
    $consultaDetalle->bind_param('i', $idEstablecimiento);
    $consultaDetalle->execute();
    $detalle = $consultaDetalle
        ->get_result()
        ->fetch_assoc();
    $consultaDetalle->close();

    if (!$detalle) {
        http_response_code(404);
    }
} else {
    $paginaRecibida = $_GET['pagina'] ?? 1;
    $paginaValidada = is_scalar($paginaRecibida)
        ? filter_var(
            $paginaRecibida,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        )
        : false;
    $pagina = $paginaValidada === false
        ? 1
        : (int)$paginaValidada;

    $patron = '%' . $busqueda . '%';

    $consultaTotal = $mysqli->prepare(
        "SELECT COUNT(*) AS total
         FROM establecimientos
         WHERE estatus = 'aprobado'
           AND (? = '' OR nombre LIKE ? OR tipo LIKE ?)
           AND (? = '' OR tipo = ?)"
    );
    $consultaTotal->bind_param(
        'sssss',
        $busqueda,
        $patron,
        $patron,
        $tipoFiltro,
        $tipoFiltro
    );
    $consultaTotal->execute();
    $filaTotal = $consultaTotal->get_result()->fetch_assoc();
    $consultaTotal->close();

    $totalResultados = (int)($filaTotal['total'] ?? 0);
    $totalPaginas = max(
        1,
        (int)ceil($totalResultados / $porPagina)
    );
    $pagina = min($pagina, $totalPaginas);
    $offset = ($pagina - 1) * $porPagina;

    $consultaLista = $mysqli->prepare(
        "SELECT
            id_establecimiento,
            nombre,
            tipo,
            descripcion,
            direccion,
            telefono,
            sitio_web
         FROM establecimientos
         WHERE estatus = 'aprobado'
           AND (? = '' OR nombre LIKE ? OR tipo LIKE ?)
           AND (? = '' OR tipo = ?)
         ORDER BY nombre ASC, id_establecimiento DESC
         LIMIT ? OFFSET ?"
    );
    $consultaLista->bind_param(
        'sssssii',
        $busqueda,
        $patron,
        $patron,
        $tipoFiltro,
        $tipoFiltro,
        $porPagina,
        $offset
    );
    $consultaLista->execute();
    $establecimientos = $consultaLista
        ->get_result()
        ->fetch_all(MYSQLI_ASSOC);
    $consultaLista->close();
}

$csrf = generarCSRF();
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta
        name="description"
        content="Directorio informativo de establecimientos relacionados con salud."
    >
    <title>
        <?php echo $detalle
            ? escaparDirectorioEstablecimientos($detalle['nombre']) . ' | Directorio Vita Sacra'
            : 'Directorio de establecimientos | Vita Sacra'; ?>
    </title>
    <link
        rel="stylesheet"
        href="<?php echo escaparDirectorioEstablecimientos(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
    <style>
        .directorio-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
            gap: 18px;
        }
        .directorio-filtros {
            display: grid;
            grid-template-columns: minmax(0, 1fr) minmax(180px, 240px) auto;
            gap: 12px;
            align-items: end;
        }
        .directorio-detalle {
            max-width: 900px;
            margin: 24px auto;
        }
        @media (max-width: 680px) {
            .directorio-filtros {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreCabecera,
        $rolCabecera,
        'directorio',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <?php if ($detalle): ?>
            <a
                class="boton boton-secundario"
                href="<?php echo escaparDirectorioEstablecimientos(RUTA_WEB); ?>/Funciones/establecimientos.php"
            >
                Volver al directorio
            </a>

            <article class="tarjeta directorio-detalle">
                <span class="etiqueta">
                    <?php echo escaparDirectorioEstablecimientos($detalle['tipo']); ?>
                </span>

                <h1><?php echo escaparDirectorioEstablecimientos($detalle['nombre']); ?></h1>

                <?php if (!empty($detalle['descripcion'])): ?>
                    <p><?php echo nl2br(escaparDirectorioEstablecimientos($detalle['descripcion'])); ?></p>
                <?php endif; ?>

                <h2>Ubicación general</h2>
                <p><?php echo escaparDirectorioEstablecimientos($detalle['direccion']); ?></p>
                <p>
                    <a
                        class="boton boton-secundario"
                        href="<?php echo escaparDirectorioEstablecimientos(urlMapaEstablecimiento($detalle['direccion'])); ?>"
                        target="_blank"
                        rel="noopener noreferrer"
                    >
                        Abrir ubicación en un servicio de mapas
                    </a>
                </p>

                <?php if (!empty($detalle['telefono'])): ?>
                    <p>
                        <strong>Contacto:</strong>
                        <?php echo escaparDirectorioEstablecimientos($detalle['telefono']); ?>
                    </p>
                <?php endif; ?>

                <?php $sitio = urlSitioEstablecimiento($detalle['sitio_web'] ?? ''); ?>
                <?php if ($sitio !== ''): ?>
                    <p>
                        <a
                            href="<?php echo escaparDirectorioEstablecimientos($sitio); ?>"
                            target="_blank"
                            rel="noopener noreferrer"
                        >
                            Visitar sitio web
                        </a>
                    </p>
                <?php endif; ?>

                <aside class="mensaje">
                    Esta ficha es informativa. Su publicación no certifica
                    licencias, formación profesional ni la calidad de los servicios.
                </aside>
            </article>
        <?php else: ?>
            <section class="presentacion-admin">
                <div>
                    <h1>Directorio de establecimientos</h1>
                    <p>
                        Consulta fichas informativas aprobadas. No se muestran
                        solicitudes pendientes ni documentos de verificación.
                    </p>
                </div>
            </section>

            <form
                class="tarjeta directorio-filtros"
                method="GET"
                action="<?php echo escaparDirectorioEstablecimientos(RUTA_WEB); ?>/Funciones/establecimientos.php"
            >
                <div>
                    <label for="q">Buscar por nombre o tipo</label>
                    <input
                        id="q"
                        name="q"
                        type="search"
                        maxlength="100"
                        value="<?php echo escaparDirectorioEstablecimientos($busqueda); ?>"
                    >
                </div>

                <div>
                    <label for="tipo">Tipo</label>
                    <select id="tipo" name="tipo">
                        <option value="">Todos</option>
                        <?php foreach ($tiposDisponibles as $tipoDisponible): ?>
                            <option
                                value="<?php echo escaparDirectorioEstablecimientos($tipoDisponible); ?>"
                                <?php echo $tipoFiltro === $tipoDisponible ? 'selected' : ''; ?>
                            >
                                <?php echo escaparDirectorioEstablecimientos($tipoDisponible); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <button class="boton" type="submit">Buscar</button>
            </form>

            <p>
                Resultados: <?php echo $totalResultados; ?>
            </p>

            <?php if ($establecimientos === []): ?>
                <article class="tarjeta">
                    <p>No encontramos establecimientos aprobados con esos criterios.</p>
                </article>
            <?php else: ?>
                <section class="directorio-grid" aria-label="Establecimientos aprobados">
                    <?php foreach ($establecimientos as $establecimiento): ?>
                        <article class="tarjeta">
                            <span class="etiqueta">
                                <?php echo escaparDirectorioEstablecimientos($establecimiento['tipo']); ?>
                            </span>
                            <h2><?php echo escaparDirectorioEstablecimientos($establecimiento['nombre']); ?></h2>

                            <?php if (!empty($establecimiento['descripcion'])): ?>
                                <p>
                                    <?php
                                    $descripcion = (string)$establecimiento['descripcion'];
                                    echo escaparDirectorioEstablecimientos(
                                        mb_strlen($descripcion, 'UTF-8') > 220
                                            ? mb_substr($descripcion, 0, 217, 'UTF-8') . '...'
                                            : $descripcion
                                    );
                                    ?>
                                </p>
                            <?php endif; ?>

                            <p>
                                <strong>Ubicación:</strong>
                                <?php echo escaparDirectorioEstablecimientos($establecimiento['direccion']); ?>
                            </p>

                            <a
                                class="boton boton-secundario"
                                href="<?php echo escaparDirectorioEstablecimientos(RUTA_WEB); ?>/Funciones/establecimientos.php?id=<?php echo (int)$establecimiento['id_establecimiento']; ?>"
                            >
                                Ver ficha
                            </a>
                        </article>
                    <?php endforeach; ?>
                </section>

                <?php if ($totalPaginas > 1): ?>
                    <nav class="enlaces" aria-label="Paginación del directorio">
                        <?php if ($pagina > 1): ?>
                            <a
                                class="boton boton-secundario"
                                href="<?php echo escaparDirectorioEstablecimientos(RUTA_WEB); ?>/Funciones/establecimientos.php?q=<?php echo rawurlencode($busqueda); ?>&amp;tipo=<?php echo rawurlencode($tipoFiltro); ?>&amp;pagina=<?php echo $pagina - 1; ?>"
                            >
                                Anterior
                            </a>
                        <?php endif; ?>

                        <span>Página <?php echo $pagina; ?> de <?php echo $totalPaginas; ?></span>

                        <?php if ($pagina < $totalPaginas): ?>
                            <a
                                class="boton boton-secundario"
                                href="<?php echo escaparDirectorioEstablecimientos(RUTA_WEB); ?>/Funciones/establecimientos.php?q=<?php echo rawurlencode($busqueda); ?>&amp;tipo=<?php echo rawurlencode($tipoFiltro); ?>&amp;pagina=<?php echo $pagina + 1; ?>"
                            >
                                Siguiente
                            </a>
                        <?php endif; ?>
                    </nav>
                <?php endif; ?>
            <?php endif; ?>
        <?php endif; ?>
    </main>

    <script
        src="<?php echo escaparDirectorioEstablecimientos(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>