<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';
require_once __DIR__ . '/componentes/cabecera.php';

date_default_timezone_set('America/Mexico_City');

requiereRol($mysqli, 'autor');

$idUsuario = (int)$_SESSION['id_usr'];
$idRecibido = $_GET['id'] ?? null;
$idBlog = filter_var(
    $idRecibido,
    FILTER_VALIDATE_INT,
    ['options' => ['min_range' => 1]]
);

if ($idBlog === false) {
    header(
        'Location: ' . RUTA_WEB . '/Funciones/gestionar_publicaciones.php',
        true,
        303
    );
    exit;
}

function escaparEnvioRevision($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postEnvioRevision(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';

    return is_string($valor) ? $valor : '';
}

function obtenerFilasFuentes(): array
{
    $campos = [
        'fuente_titulo',
        'fuente_autor',
        'fuente_url',
        'fuente_anio'
    ];

    $valores = [];

    foreach ($campos as $campo) {
        $entrada = $_POST[$campo] ?? [];
        $valores[$campo] = is_array($entrada) ? $entrada : [];
    }

    $cantidad = max(
        count($valores['fuente_titulo']),
        count($valores['fuente_autor']),
        count($valores['fuente_url']),
        count($valores['fuente_anio'])
    );

    $filas = [];

    for ($i = 0; $i < $cantidad && $i < 21; $i++) {
        $filas[] = [
            'titulo' => is_string($valores['fuente_titulo'][$i] ?? null)
                ? trim($valores['fuente_titulo'][$i])
                : '',
            'autor' => is_string($valores['fuente_autor'][$i] ?? null)
                ? trim($valores['fuente_autor'][$i])
                : '',
            'url' => is_string($valores['fuente_url'][$i] ?? null)
                ? trim($valores['fuente_url'][$i])
                : '',
            'anio' => is_string($valores['fuente_anio'][$i] ?? null)
                ? trim($valores['fuente_anio'][$i])
                : ''
        ];
    }

    return $filas;
}

$administrador = 0;

$consultaPublicacion = $mysqli->prepare(
    "SELECT
        b.id_blog,
        b.usr_id,
        b.estatus,
        b.version_publica
     FROM blog b
     WHERE b.id_blog = ?
       AND b.usr_id = ?
       AND (
            (
                b.estatus IN ('borrador', 'correccion')
                AND b.version_publica IS NULL
            )
            OR
            (
                b.estatus = 'publicado'
                AND b.version_publica IS NOT NULL
            )
       )
     LIMIT 1"
);

$consultaPublicacion->bind_param('ii', $idBlog, $idUsuario);
$consultaPublicacion->execute();
$publicacion = $consultaPublicacion->get_result()->fetch_assoc();
$consultaPublicacion->close();

if (!$publicacion) {
    http_response_code(404);
    exit('La publicación no existe o no puede enviarse a revisión.');
}

$consultaVersion = $mysqli->prepare(
    "SELECT
        id_version,
        numero,
        advertencia,
        estatus,
        titulo_snapshot,
        descripcion_snapshot,
        categoria_id_snapshot,
        tipo_snapshot
     FROM versiones_blog
     WHERE blog_id = ?
     ORDER BY numero DESC
     LIMIT 1"
);

$consultaVersion->bind_param('i', $idBlog);
$consultaVersion->execute();
$versionActual = $consultaVersion->get_result()->fetch_assoc();
$consultaVersion->close();

if (
    !$versionActual ||
    !in_array($versionActual['estatus'], ['borrador', 'correccion'], true)
) {
    http_response_code(409);
    exit('La publicación no tiene una versión disponible para enviar a revisión.');
}

$idVersionActual = (int)$versionActual['id_version'];

$consultaCategoria = $mysqli->prepare(
    "SELECT nombre
     FROM categorias
     WHERE id_categoria = ?
     LIMIT 1"
);

$categoriaSnapshot = (int)$versionActual['categoria_id_snapshot'];
$consultaCategoria->bind_param('i', $categoriaSnapshot);
$consultaCategoria->execute();
$filaCategoria = $consultaCategoria->get_result()->fetch_assoc();
$consultaCategoria->close();

$categoriaNombre = $filaCategoria['nombre'] ?? 'Sin categoría';

$consultaContenido = $mysqli->prepare(
    "SELECT COUNT(*) AS cantidad
     FROM bloques_version
     WHERE version_id = ?
       AND contenido IS NOT NULL
       AND CHAR_LENGTH(TRIM(contenido)) > 0"
);

$consultaContenido->bind_param('i', $idVersionActual);
$consultaContenido->execute();
$filaContenido = $consultaContenido->get_result()->fetch_assoc();
$consultaContenido->close();

$consultaFuentes = $mysqli->prepare(
    "SELECT f.titulo, f.autor, f.url, f.anio
     FROM version_fuentes vf
     INNER JOIN fuentes f ON f.id_fuente = vf.fuente_id
     WHERE vf.version_id = ?
     ORDER BY f.titulo"
);

$consultaFuentes->bind_param('i', $idVersionActual);
$consultaFuentes->execute();
$fuentesActuales = $consultaFuentes->get_result()->fetch_all(MYSQLI_ASSOC);
$consultaFuentes->close();

$observacionCorreccion = null;

if ($versionActual['estatus'] === 'correccion') {
    $consultaCorreccion = $mysqli->prepare(
        "SELECT r.observacion, r.fecha
         FROM revisiones_blog r
         WHERE r.version_id = ?
           AND r.decision = 'correccion'
         ORDER BY r.fecha DESC
         LIMIT 1"
    );

    $consultaCorreccion->bind_param('i', $idVersionActual);
    $consultaCorreccion->execute();
    $observacionCorreccion = $consultaCorreccion
        ->get_result()
        ->fetch_assoc();
    $consultaCorreccion->close();
}

$fuentesFormulario = $fuentesActuales;

if ($fuentesFormulario === []) {
    $fuentesFormulario[] = [
        'titulo' => '',
        'autor' => '',
        'url' => '',
        'anio' => ''
    ];
}

$mensaje = '';
$tipoMensaje = '';
$csrf = generarCSRF();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $fuentesFormulario = obtenerFilasFuentes();

    $idVersionRecibida = filter_var(
        postEnvioRevision('id_version'),
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );

    if (count($fuentesFormulario) > 20) {
        $mensaje = 'Puedes agregar un máximo de 20 fuentes.';
        $tipoMensaje = 'mensaje-error';
    } elseif (!verificarCSRF(postEnvioRevision('csrf_token'))) {
        $mensaje = 'La solicitud no es válida. Actualiza la página e intenta nuevamente.';
        $tipoMensaje = 'mensaje-error';
    } elseif (
        $idVersionRecibida === false ||
        (int)$idVersionRecibida !== $idVersionActual
    ) {
        $mensaje = 'La versión seleccionada cambió. Actualiza la página e intenta nuevamente.';
        $tipoMensaje = 'mensaje-error';
    } else {
        $fuentesValidas = [];
        $errorFuentes = '';

        foreach ($fuentesFormulario as $fuente) {
            $vacios = (
                $fuente['titulo'] === '' &&
                $fuente['autor'] === '' &&
                $fuente['url'] === '' &&
                $fuente['anio'] === ''
            );

            if ($vacios) {
                continue;
            }

            if ($fuente['titulo'] === '') {
                $errorFuentes = 'Cada fuente debe incluir un título.';
                break;
            }

            if (mb_strlen($fuente['titulo'], 'UTF-8') > 255) {
                $errorFuentes = 'El título de cada fuente debe tener máximo 255 caracteres.';
                break;
            }

            if (mb_strlen($fuente['autor'], 'UTF-8') > 255) {
                $errorFuentes = 'El autor de cada fuente debe tener máximo 255 caracteres.';
                break;
            }

            if (strlen($fuente['url']) > 1000) {
                $errorFuentes = 'Cada enlace de fuente debe tener máximo 1,000 caracteres.';
                break;
            }

            if (
                $fuente['url'] !== '' &&
                (
                    !filter_var($fuente['url'], FILTER_VALIDATE_URL) ||
                    !in_array(
                        strtolower((string)parse_url(
                            $fuente['url'],
                            PHP_URL_SCHEME
                        )),
                        ['http', 'https'],
                        true
                    )
                )
            ) {
                $errorFuentes = 'Cada URL debe ser un enlace HTTP o HTTPS válido.';
                break;
            }

            $anio = null;

            if ($fuente['anio'] !== '') {
                $anioValidado = filter_var(
                    $fuente['anio'],
                    FILTER_VALIDATE_INT,
                    [
                        'options' => [
                            'min_range' => 1000,
                            'max_range' => (int)date('Y') + 1
                        ]
                    ]
                );

                if ($anioValidado === false) {
                    $errorFuentes = 'Revisa el año indicado en las fuentes.';
                    break;
                }

                $anio = (string)$anioValidado;
            }

            if (
                $fuente['autor'] === '' &&
                $fuente['url'] === '' &&
                $anio === null
            ) {
                $errorFuentes = 'Cada fuente debe tener autor, enlace o año además de su título.';
                break;
            }

            $fuentesValidas[] = [
                'titulo' => $fuente['titulo'],
                'autor' => $fuente['autor'] !== ''
                    ? $fuente['autor']
                    : null,
                'url' => $fuente['url'] !== ''
                    ? $fuente['url']
                    : null,
                'anio' => $anio
            ];
        }

        if ($errorFuentes !== '') {
            $mensaje = $errorFuentes;
            $tipoMensaje = 'mensaje-error';
        } elseif ($fuentesValidas === []) {
            $mensaje = 'Agrega al menos una fuente identificable antes de enviar.';
            $tipoMensaje = 'mensaje-error';
        } else {
            $mysqli->begin_transaction();

            try {
                $bloqueo = $mysqli->prepare(
                    "SELECT usr_id, estatus, version_publica
                     FROM blog
                     WHERE id_blog = ?
                     FOR UPDATE"
                );

                $bloqueo->bind_param('i', $idBlog);
                $bloqueo->execute();
                $registro = $bloqueo->get_result()->fetch_assoc();
                $bloqueo->close();

                $tieneVersionPublica = $registro
                    && $registro['version_publica'] !== null;

                $estadoPermitido = $registro
                    && (
                        (
                            !$tieneVersionPublica &&
                            in_array(
                                $registro['estatus'],
                                ['borrador', 'correccion'],
                                true
                            )
                        )
                        ||
                        (
                            $tieneVersionPublica &&
                            $registro['estatus'] === 'publicado'
                        )
                    );

                if (
                    !$registro ||
                    (int)$registro['usr_id'] !== $idUsuario ||
                    !$estadoPermitido
                ) {
                    throw new DomainException(
                        'La publicación ya no está disponible para enviarse a revisión.'
                    );
                }

                $versionBloqueada = $mysqli->prepare(
                    "SELECT
                        id_version,
                        numero,
                        advertencia,
                        estatus,
                        titulo_snapshot,
                        descripcion_snapshot,
                        categoria_id_snapshot,
                        tipo_snapshot
                     FROM versiones_blog
                     WHERE blog_id = ?
                     ORDER BY numero DESC
                     LIMIT 1
                     FOR UPDATE"
                );

                $versionBloqueada->bind_param('i', $idBlog);
                $versionBloqueada->execute();
                $version = $versionBloqueada->get_result()->fetch_assoc();
                $versionBloqueada->close();

                if (
                    !$version ||
                    (int)$version['id_version'] !== $idVersionActual ||
                    !in_array(
                        $version['estatus'],
                        ['borrador', 'correccion'],
                        true
                    )
                ) {
                    throw new DomainException(
                        'La versión ya no está disponible para enviarse a revisión.'
                    );
                }

                if (
                    trim((string)$version['titulo_snapshot']) === '' ||
                    trim((string)($version['descripcion_snapshot'] ?? '')) === '' ||
                    (int)$version['categoria_id_snapshot'] < 1 ||
                    trim((string)$version['tipo_snapshot']) === ''
                ) {
                    throw new DomainException(
                        'Completa los datos de la publicación antes de enviarla.'
                    );
                }

                $categoriaSnapshot = (int)$version['categoria_id_snapshot'];

                $validarCategoria = $mysqli->prepare(
                    "SELECT id_categoria
                     FROM categorias
                     WHERE id_categoria = ?
                       AND activa = 1
                     LIMIT 1"
                );

                $validarCategoria->bind_param('i', $categoriaSnapshot);
                $validarCategoria->execute();
                $categoriaActiva = $validarCategoria
                    ->get_result()
                    ->fetch_assoc();
                $validarCategoria->close();

                if (!$categoriaActiva) {
                    throw new DomainException(
                        'La categoría de la publicación está inactiva. Edita el borrador y selecciona otra categoría.'
                    );
                }

                $idVersion = (int)$version['id_version'];

                $validarBloques = $mysqli->prepare(
                    "SELECT COUNT(*) AS cantidad
                     FROM bloques_version
                     WHERE version_id = ?
                       AND contenido IS NOT NULL
                       AND CHAR_LENGTH(TRIM(contenido)) > 0"
                );

                $validarBloques->bind_param('i', $idVersion);
                $validarBloques->execute();
                $bloques = $validarBloques->get_result()->fetch_assoc();
                $validarBloques->close();

                if ((int)$bloques['cantidad'] === 0) {
                    throw new DomainException(
                        'Agrega contenido antes de enviar la publicación a revisión.'
                    );
                }

                if (
                    in_array(
                        $version['tipo_snapshot'],
                        ['ficha_medicamento', 'ficha_producto'],
                        true
                    ) &&
                    trim((string)($version['advertencia'] ?? '')) === ''
                ) {
                    throw new DomainException(
                        'La ficha educativa debe incluir una advertencia informativa.'
                    );
                }

                $eliminarRelaciones = $mysqli->prepare(
                    "DELETE FROM version_fuentes
                     WHERE version_id = ?"
                );

                $eliminarRelaciones->bind_param('i', $idVersion);
                $eliminarRelaciones->execute();
                $eliminarRelaciones->close();

                $insertarFuente = $mysqli->prepare(
                    "INSERT INTO fuentes (titulo, autor, url, anio)
                     VALUES (?, ?, ?, ?)"
                );

                $insertarRelacion = $mysqli->prepare(
                    "INSERT INTO version_fuentes (version_id, fuente_id)
                     VALUES (?, ?)"
                );

                foreach ($fuentesValidas as $fuente) {
                    $tituloFuente = $fuente['titulo'];
                    $autorFuente = $fuente['autor'];
                    $urlFuente = $fuente['url'];
                    $anioFuente = $fuente['anio'];

                    $insertarFuente->bind_param(
                        'ssss',
                        $tituloFuente,
                        $autorFuente,
                        $urlFuente,
                        $anioFuente
                    );

                    $insertarFuente->execute();
                    $idFuente = (int)$mysqli->insert_id;

                    $insertarRelacion->bind_param(
                        'ii',
                        $idVersion,
                        $idFuente
                    );

                    $insertarRelacion->execute();
                }

                $insertarFuente->close();
                $insertarRelacion->close();

                $actualizarVersion = $mysqli->prepare(
                    "UPDATE versiones_blog
                     SET estatus = 'revision'
                     WHERE id_version = ?
                       AND blog_id = ?
                       AND estatus IN ('borrador', 'correccion')"
                );

                $actualizarVersion->bind_param('ii', $idVersion, $idBlog);
                $actualizarVersion->execute();
                $versionesActualizadas = $actualizarVersion->affected_rows;
                $actualizarVersion->close();

                if ($versionesActualizadas !== 1) {
                    throw new DomainException(
                        'No se pudo cambiar el estado editorial de la versión.'
                    );
                }

                if (!$tieneVersionPublica) {
                    $actualizarPublicacion = $mysqli->prepare(
                        "UPDATE blog
                         SET estatus = 'revision'
                         WHERE id_blog = ?
                           AND usr_id = ?
                           AND estatus IN ('borrador', 'correccion')
                           AND version_publica IS NULL"
                    );

                    $actualizarPublicacion->bind_param(
                        'ii',
                        $idBlog,
                        $idUsuario
                    );

                    $actualizarPublicacion->execute();
                    $publicacionesActualizadas =
                        $actualizarPublicacion->affected_rows;
                    $actualizarPublicacion->close();

                    if ($publicacionesActualizadas !== 1) {
                        throw new DomainException(
                            'No se pudo cambiar el estado editorial de la publicación.'
                        );
                    }
                }

                $mysqli->commit();

                header(
                    'Location: '
                    . RUTA_WEB
                    . '/Funciones/gestionar_publicaciones.php?mensaje=revision_enviada',
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
                    'Vita Sacra: error al enviar publicación a revisión, código '
                    . $error->getCode()
                );

                $mensaje = 'No fue posible enviar la publicación a revisión. Intenta nuevamente.';
                $tipoMensaje = 'mensaje-error';
            }
        }
    }

    if ($fuentesFormulario === []) {
        $fuentesFormulario[] = [
            'titulo' => '',
            'autor' => '',
            'url' => '',
            'anio' => ''
        ];
    }
}

$csrf = generarCSRF();
$nombreUsuario = escaparEnvioRevision($_SESSION['nom_usr'] ?? 'Usuario');

$tituloMostrar = (string)$versionActual['titulo_snapshot'];
$descripcionMostrar = (string)($versionActual['descripcion_snapshot'] ?? '');
$esActualizacionPublicada = $publicacion['version_publica'] !== null;

$nombreNavGlobal = $_SESSION['nom_usr'] ?? 'Mi cuenta';
if (!is_string($nombreNavGlobal)) {
    $nombreNavGlobal = 'Mi cuenta';
}
$rolNavGlobal = 'autor';
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Enviar a revisión | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparEnvioRevision(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreNavGlobal,
        $rolNavGlobal,
        'gestionar',
        $csrf
    );
    ?>
    <main class="contenedor contenedor-inicio">
        <header>
            <h1>Enviar publicación a revisión</h1>
            <p class="subtitulo">
                Sesión de <?php echo $nombreUsuario; ?>
            </p>
        </header>

        <nav class="enlaces" aria-label="Navegación">
            <a href="<?php echo escaparEnvioRevision(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php">
                Volver a mis publicaciones
            </a>
        </nav>

        <?php if ($mensaje !== ''): ?>
            <div
                class="<?php echo escaparEnvioRevision($tipoMensaje); ?>"
                role="alert"
                aria-live="polite"
            >
                <?php echo escaparEnvioRevision($mensaje); ?>
            </div>
        <?php endif; ?>

        <section class="tarjeta">
            <h2><?php echo escaparEnvioRevision($tituloMostrar); ?></h2>

            <p>
                Categoría:
                <?php echo escaparEnvioRevision($categoriaNombre); ?>
            </p>

            <?php if ($esActualizacionPublicada): ?>
                <p>
                    Estás enviando una actualización. La versión que ya está
                    publicada permanecerá visible hasta que esta sea aprobada.
                </p>
            <?php else: ?>
                <p>
                    Estado:
                    <?php
                    echo $publicacion['estatus'] === 'correccion'
                        ? 'Corrección solicitada'
                        : 'Borrador';
                    ?>
                </p>
            <?php endif; ?>

            <p>
                Descripción:
                <?php echo escaparEnvioRevision($descripcionMostrar); ?>
            </p>

            <?php if ($observacionCorreccion): ?>
                <section aria-labelledby="observaciones-titulo">
                    <h3 id="observaciones-titulo">
                        Observaciones del administrador
                    </h3>
                    <p>
                        <?php
                        echo nl2br(
                            escaparEnvioRevision(
                                $observacionCorreccion['observacion'] ?? ''
                            )
                        );
                        ?>
                    </p>
                </section>
            <?php endif; ?>

            <p>
                Versión actual:
                <?php echo (int)$versionActual['numero']; ?>
            </p>

            <?php if ((int)$filaContenido['cantidad'] === 0): ?>
                <p class="mensaje-error">
                    La publicación no tiene contenido. Regresa a editarla antes
                    de enviarla.
                </p>
            <?php endif; ?>

            <form
                method="POST"
                action="<?php echo escaparEnvioRevision(RUTA_WEB); ?>/Funciones/enviar_revision.php?id=<?php echo (int)$idBlog; ?>"
            >
                <input
                    type="hidden"
                    name="csrf_token"
                    value="<?php echo escaparEnvioRevision($csrf); ?>"
                >
                <input
                    type="hidden"
                    name="id_version"
                    value="<?php echo (int)$versionActual['id_version']; ?>"
                >

                <h3>Fuentes</h3>
                <p>
                    Registra al menos una fuente con título y, además, autor,
                    enlace o año.
                </p>

                <div id="fuentes">
                    <?php foreach ($fuentesFormulario as $indice => $fuente): ?>
                        <fieldset class="tarjeta fuente-editor">
                            <legend>Fuente <?php echo (int)$indice + 1; ?></legend>

                            <label for="fuente_titulo_<?php echo (int)$indice; ?>">
                                Título
                            </label>
                            <input
                                type="text"
                                id="fuente_titulo_<?php echo (int)$indice; ?>"
                                name="fuente_titulo[]"
                                maxlength="255"
                                value="<?php echo escaparEnvioRevision($fuente['titulo'] ?? ''); ?>"
                            >

                            <label for="fuente_autor_<?php echo (int)$indice; ?>">
                                Autor o institución
                            </label>
                            <input
                                type="text"
                                id="fuente_autor_<?php echo (int)$indice; ?>"
                                name="fuente_autor[]"
                                maxlength="255"
                                value="<?php echo escaparEnvioRevision($fuente['autor'] ?? ''); ?>"
                            >

                            <label for="fuente_url_<?php echo (int)$indice; ?>">
                                URL
                            </label>
                            <input
                                type="url"
                                id="fuente_url_<?php echo (int)$indice; ?>"
                                name="fuente_url[]"
                                maxlength="1000"
                                value="<?php echo escaparEnvioRevision($fuente['url'] ?? ''); ?>"
                            >

                            <label for="fuente_anio_<?php echo (int)$indice; ?>">
                                Año
                            </label>
                            <input
                                type="number"
                                id="fuente_anio_<?php echo (int)$indice; ?>"
                                name="fuente_anio[]"
                                min="1000"
                                max="<?php echo (int)date('Y') + 1; ?>"
                                value="<?php echo escaparEnvioRevision($fuente['anio'] ?? ''); ?>"
                            >

                            <button
                                type="button"
                                class="boton-secundario quitar-fuente"
                            >
                                Quitar fuente
                            </button>
                        </fieldset>
                    <?php endforeach; ?>
                </div>

                <button type="button" id="agregar-fuente">
                    Agregar otra fuente
                </button>

                <p>
                    Al enviar, esta versión quedará bloqueada para edición
                    hasta que un administrador registre una decisión.
                </p>

                <button
                    type="submit"
                    <?php
                    echo (int)$filaContenido['cantidad'] === 0
                        ? 'disabled'
                        : '';
                    ?>
                >
                    Enviar a revisión
                </button>
            </form>
        </section>
    </main>

    <script>
        (() => {
            const contenedor = document.getElementById('fuentes');
            const agregar = document.getElementById('agregar-fuente');

            function crearCampo(etiqueta, nombre, tipo, maximo = null) {
                const envoltura = document.createElement('div');
                const id = `${nombre}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
                const label = document.createElement('label');
                const input = document.createElement('input');

                label.htmlFor = id;
                label.textContent = etiqueta;

                input.id = id;
                input.name = `${nombre}[]`;
                input.type = tipo;

                if (maximo !== null) {
                    input.maxLength = maximo;
                }

                envoltura.append(label, input);
                return envoltura;
            }

            agregar.addEventListener('click', () => {
                if (contenedor.querySelectorAll('.fuente-editor').length >= 20) {
                    return;
                }

                const fieldset = document.createElement('fieldset');
                const legend = document.createElement('legend');
                const quitar = document.createElement('button');

                fieldset.className = 'tarjeta fuente-editor';
                legend.textContent = 'Nueva fuente';

                fieldset.append(
                    legend,
                    crearCampo('Título', 'fuente_titulo', 'text', 255),
                    crearCampo('Autor o institución', 'fuente_autor', 'text', 255),
                    crearCampo('URL', 'fuente_url', 'url', 1000),
                    crearCampo('Año', 'fuente_anio', 'number')
                );

                quitar.type = 'button';
                quitar.className = 'boton-secundario quitar-fuente';
                quitar.textContent = 'Quitar fuente';
                fieldset.append(quitar);
                contenedor.append(fieldset);
            });

            contenedor.addEventListener('click', (evento) => {
                if (evento.target.classList.contains('quitar-fuente')) {
                    const fuente = evento.target.closest('.fuente-editor');

                    if (fuente && contenedor.children.length > 1) {
                        fuente.remove();
                    }
                }
            });
        })();
    </script>
    <script
        src="<?php echo escaparEnvioRevision(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>