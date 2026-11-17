<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

date_default_timezone_set('America/Mexico_City');

requiereRol($mysqli, 'autor', 'administrador');

$rolesActuales = obtenerRolesActuales($mysqli);
$esAdministrador = in_array('administrador', $rolesActuales, true);
$idUsuario = (int)$_SESSION['id_usr'];
$administrador = $esAdministrador ? 1 : 0;

function escaparEdicion($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postEdicion(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';

    return is_string($valor) ? $valor : '';
}

function rutaImagenEdicion($imagen): string
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

$consultaPublicacion = $mysqli->prepare(
    "SELECT
        b.id_blog,
        b.usr_id,
        b.categoria_id,
        b.titulo,
        b.`desc`,
        b.img,
        b.tipo,
        b.estatus,
        b.version_publica
     FROM blog b
     WHERE b.id_blog = ?
       AND (? = 1 OR b.usr_id = ?)
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
    exit('La publicación no existe o no tienes permiso para editarla.');
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
        imagen_snapshot,
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

if (!$versionActual) {
    http_response_code(409);
    exit('La publicación no tiene una versión que pueda editarse.');
}

$esPublicacionPublicada = $publicacion['version_publica'] !== null;
$estadosEditablesPublicados = ['publicado', 'correccion', 'rechazado'];

if (
    $esPublicacionPublicada &&
    !in_array(
        $versionActual['estatus'],
        $estadosEditablesPublicados,
        true
    )
) {
    http_response_code(409);
    exit('La versión está pendiente de revisión y no puede editarse.');
}

if (
    !$esPublicacionPublicada &&
    !in_array(
        $versionActual['estatus'],
        ['borrador', 'correccion'],
        true
    )
) {
    http_response_code(409);
    exit('La versión no está disponible para edición.');
}

$idVersionAnterior = (int)$versionActual['id_version'];
$contenido = '';
$fuentes = [];

$consultaBloque = $mysqli->prepare(
    "SELECT contenido
     FROM bloques_version
     WHERE version_id = ?
       AND tipo = 'parrafo'
     ORDER BY orden ASC
     LIMIT 1"
);

$consultaBloque->bind_param('i', $idVersionAnterior);
$consultaBloque->execute();
$bloque = $consultaBloque->get_result()->fetch_assoc();
$consultaBloque->close();

if ($bloque) {
    $contenido = (string)($bloque['contenido'] ?? '');
}

$consultaFuentes = $mysqli->prepare(
    "SELECT f.titulo, f.autor, f.url, f.anio
     FROM version_fuentes vf
     INNER JOIN fuentes f ON f.id_fuente = vf.fuente_id
     WHERE vf.version_id = ?
     ORDER BY f.titulo"
);

$consultaFuentes->bind_param('i', $idVersionAnterior);
$consultaFuentes->execute();
$fuentes = $consultaFuentes->get_result()->fetch_all(MYSQLI_ASSOC);
$consultaFuentes->close();

$categorias = $mysqli->query(
    "SELECT id_categoria, nombre
     FROM categorias
     WHERE activa = 1
     ORDER BY nombre"
)->fetch_all(MYSQLI_ASSOC);

$titulo = (string)$versionActual['titulo_snapshot'];
$descripcion = (string)($versionActual['descripcion_snapshot'] ?? '');
$categoriaSeleccionada = (int)$versionActual['categoria_id_snapshot'];
$tipoPublicacion = (string)$versionActual['tipo_snapshot'];
$imagenActual = $versionActual['imagen_snapshot'];
$imagen = $imagenActual;
$advertencia = (string)($versionActual['advertencia'] ?? '');

$mensaje = '';
$tipoMensaje = '';
$csrf = generarCSRF();
$tipoImagen = 'conservar';
$imagenURL = '';

$mensajeRecibido = $_GET['mensaje'] ?? '';

if ($mensajeRecibido === 'actualizado') {
    $mensaje = $esPublicacionPublicada
        ? 'Se guardó una nueva versión. La versión publicada sigue visible.'
        : 'Se guardó una nueva versión del borrador.';
    $tipoMensaje = 'mensaje-exito';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!verificarCSRF(postEdicion('csrf_token'))) {
        $mensaje = 'La solicitud no es válida. Actualiza la página e intenta nuevamente.';
        $tipoMensaje = 'mensaje-error';
    } elseif (postEdicion('accion') !== 'guardar') {
        $mensaje = 'La acción solicitada no es válida.';
        $tipoMensaje = 'mensaje-error';
    } else {
        $titulo = trim(postEdicion('titulo'));
        $descripcion = trim(postEdicion('descripcion'));
        $contenido = trim(postEdicion('contenido'));
        $advertencia = trim(postEdicion('advertencia'));
        $tipoImagen = postEdicion('tipo_imagen');
        $imagenURL = trim(postEdicion('imagen_url'));

        $categoriaRecibida = filter_var(
            postEdicion('categoria'),
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        );

        $esFichaSalud = in_array(
            $tipoPublicacion,
            ['ficha_medicamento', 'ficha_producto'],
            true
        );

        if (
            $titulo === '' ||
            $descripcion === '' ||
            $contenido === '' ||
            $categoriaRecibida === false
        ) {
            $mensaje = 'Completa el título, la descripción, el contenido y la categoría.';
            $tipoMensaje = 'mensaje-error';
        } elseif (mb_strlen($titulo, 'UTF-8') > 200) {
            $mensaje = 'El título no puede superar los 200 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif (mb_strlen($descripcion, 'UTF-8') > 500) {
            $mensaje = 'La descripción no puede superar los 500 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif (mb_strlen($contenido, 'UTF-8') > 50000) {
            $mensaje = 'El contenido no puede superar los 50,000 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif ($esFichaSalud && $advertencia === '') {
            $mensaje = 'La ficha educativa debe incluir una advertencia informativa.';
            $tipoMensaje = 'mensaje-error';
        } elseif (mb_strlen($advertencia, 'UTF-8') > 5000) {
            $mensaje = 'La advertencia no puede superar los 5,000 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif (!in_array(
            $tipoImagen,
            ['conservar', 'ninguna', 'enlace', 'local'],
            true
        )) {
            $mensaje = 'Selecciona una opción de imagen válida.';
            $tipoMensaje = 'mensaje-error';
        } else {
            $categoriaSeleccionada = (int)$categoriaRecibida;

            $consultaCategoria = $mysqli->prepare(
                "SELECT id_categoria
                 FROM categorias
                 WHERE id_categoria = ?
                   AND activa = 1
                 LIMIT 1"
            );

            $consultaCategoria->bind_param(
                'i',
                $categoriaSeleccionada
            );

            $consultaCategoria->execute();
            $categoriaValida = $consultaCategoria
                ->get_result()
                ->fetch_assoc();
            $consultaCategoria->close();

            if (!$categoriaValida) {
                $mensaje = 'La categoría seleccionada no existe o está inactiva.';
                $tipoMensaje = 'mensaje-error';
            } else {
                $archivoGuardado = null;
                $imagen = $imagenActual;

                if ($tipoImagen === 'ninguna') {
                    $imagen = null;
                } elseif ($tipoImagen === 'enlace') {
                    if (
                        $imagenURL === '' ||
                        strlen($imagenURL) > 255 ||
                        !filter_var($imagenURL, FILTER_VALIDATE_URL) ||
                        !in_array(
                            strtolower((string)parse_url(
                                $imagenURL,
                                PHP_URL_SCHEME
                            )),
                            ['http', 'https'],
                            true
                        )
                    ) {
                        $mensaje = 'Ingresa una dirección HTTP o HTTPS válida, de hasta 255 caracteres.';
                        $tipoMensaje = 'mensaje-error';
                    } else {
                        $imagen = $imagenURL;
                    }
                } elseif ($tipoImagen === 'local') {
                    $archivo = $_FILES['imagen_archivo'] ?? null;

                    if (
                        !is_array($archivo) ||
                        (int)($archivo['error'] ?? UPLOAD_ERR_NO_FILE)
                            !== UPLOAD_ERR_OK
                    ) {
                        $mensaje = 'Selecciona una imagen válida de tu dispositivo.';
                        $tipoMensaje = 'mensaje-error';
                    } elseif (
                        (int)($archivo['size'] ?? 0) <= 0 ||
                        (int)$archivo['size'] > 5 * 1024 * 1024
                    ) {
                        $mensaje = 'La imagen debe pesar más de 0 y no superar los 5 MB.';
                        $tipoMensaje = 'mensaje-error';
                    } elseif (
                        !isset($archivo['tmp_name']) ||
                        !is_uploaded_file($archivo['tmp_name'])
                    ) {
                        $mensaje = 'El archivo recibido no es una carga válida.';
                        $tipoMensaje = 'mensaje-error';
                    } else {
                        $informacionImagen = @getimagesize(
                            $archivo['tmp_name']
                        );

                        $formatosPermitidos = [
                            'image/jpeg' => 'jpg',
                            'image/png' => 'png',
                            'image/webp' => 'webp',
                            'image/gif' => 'gif'
                        ];

                        $mime = is_array($informacionImagen)
                            ? ($informacionImagen['mime'] ?? '')
                            : '';

                        if (!isset($formatosPermitidos[$mime])) {
                            $mensaje = 'La imagen debe ser JPG, PNG, WEBP o GIF.';
                            $tipoMensaje = 'mensaje-error';
                        } else {
                            $carpeta = __DIR__
                                . '/../Recursos/uploads/publicaciones/';

                            if (
                                !is_dir($carpeta) &&
                                !mkdir($carpeta, 0755, true) &&
                                !is_dir($carpeta)
                            ) {
                                $mensaje = 'No se pudo preparar la carpeta de imágenes.';
                                $tipoMensaje = 'mensaje-error';
                            } elseif (!is_writable($carpeta)) {
                                $mensaje = 'No se puede guardar la imagen en el servidor.';
                                $tipoMensaje = 'mensaje-error';
                            } else {
                                $nombreImagen = bin2hex(random_bytes(16))
                                    . '.'
                                    . $formatosPermitidos[$mime];

                                $rutaCompleta = $carpeta . $nombreImagen;

                                if (move_uploaded_file(
                                    $archivo['tmp_name'],
                                    $rutaCompleta
                                )) {
                                    $imagen =
                                        'Recursos/uploads/publicaciones/'
                                        . $nombreImagen;
                                    $archivoGuardado = $rutaCompleta;
                                } else {
                                    $mensaje = 'No fue posible guardar la imagen.';
                                    $tipoMensaje = 'mensaje-error';
                                }
                            }
                        }
                    }
                }

                if ($tipoMensaje !== 'mensaje-error') {
                    $mysqli->begin_transaction();

                    try {
                        $bloqueo = $mysqli->prepare(
                            "SELECT
                                id_blog,
                                usr_id,
                                estatus,
                                version_publica,
                                tipo,
                                categoria_id
                             FROM blog
                             WHERE id_blog = ?
                             FOR UPDATE"
                        );

                        $bloqueo->bind_param('i', $idBlog);
                        $bloqueo->execute();
                        $registroBloqueado = $bloqueo
                            ->get_result()
                            ->fetch_assoc();
                        $bloqueo->close();

                        $propietarioValido = $registroBloqueado
                            && (
                                $esAdministrador ||
                                (int)$registroBloqueado['usr_id'] === $idUsuario
                            );

                        $tieneVersionPublica =
                            $registroBloqueado &&
                            $registroBloqueado['version_publica'] !== null;

                        $estadoPublicacionValido = $registroBloqueado
                            && (
                                (
                                    !$tieneVersionPublica &&
                                    in_array(
                                        $registroBloqueado['estatus'],
                                        ['borrador', 'correccion'],
                                        true
                                    )
                                )
                                ||
                                (
                                    $tieneVersionPublica &&
                                    $registroBloqueado['estatus'] === 'publicado'
                                )
                            );

                        if (!$propietarioValido || !$estadoPublicacionValido) {
                            throw new DomainException(
                                'La publicación dejó de estar disponible para edición.'
                            );
                        }

                        $versionBloqueada = $mysqli->prepare(
                            "SELECT id_version, numero, estatus
                             FROM versiones_blog
                             WHERE blog_id = ?
                             ORDER BY numero DESC
                             LIMIT 1
                             FOR UPDATE"
                        );

                        $versionBloqueada->bind_param('i', $idBlog);
                        $versionBloqueada->execute();
                        $versionAnterior = $versionBloqueada
                            ->get_result()
                            ->fetch_assoc();
                        $versionBloqueada->close();

                        if (!$versionAnterior) {
                            throw new DomainException(
                                'La publicación no tiene una versión editable.'
                            );
                        }

                        $estadosPermitidos = $tieneVersionPublica
                            ? ['publicado', 'correccion', 'rechazado']
                            : ['borrador', 'correccion'];

                        if (!in_array(
                            $versionAnterior['estatus'],
                            $estadosPermitidos,
                            true
                        )) {
                            throw new DomainException(
                                'La versión está pendiente de revisión o no puede editarse.'
                            );
                        }

                        $tipoBloqueado = (string)$registroBloqueado['tipo'];
                        $esFichaBloqueada = in_array(
                            $tipoBloqueado,
                            ['ficha_medicamento', 'ficha_producto'],
                            true
                        );

                        if ($esFichaBloqueada && $advertencia === '') {
                            throw new DomainException(
                                'La ficha educativa debe incluir una advertencia informativa.'
                            );
                        }

                        $idVersionAnterior = (int)$versionAnterior['id_version'];
                        $numeroVersion = (int)$versionAnterior['numero'] + 1;

                        if ($tieneVersionPublica) {
                            $estatusVersion = $versionAnterior['estatus']
                                === 'correccion'
                                ? 'correccion'
                                : 'borrador';
                        } else {
                            $estatusVersion = (string)$registroBloqueado['estatus'];
                        }

                        $advertenciaDB = $advertencia !== ''
                            ? $advertencia
                            : null;

                        $insertarVersion = $mysqli->prepare(
                            "INSERT INTO versiones_blog
                                (
                                    blog_id,
                                    numero,
                                    advertencia,
                                    estatus,
                                    titulo_snapshot,
                                    descripcion_snapshot,
                                    categoria_id_snapshot,
                                    imagen_snapshot,
                                    tipo_snapshot
                                )
                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
                        );

                        $insertarVersion->bind_param(
                            'iissssiss',
                            $idBlog,
                            $numeroVersion,
                            $advertenciaDB,
                            $estatusVersion,
                            $titulo,
                            $descripcion,
                            $categoriaSeleccionada,
                            $imagen,
                            $tipoBloqueado
                        );

                        $insertarVersion->execute();
                        $idVersionNueva = (int)$mysqli->insert_id;
                        $insertarVersion->close();

                        $insertarBloque = $mysqli->prepare(
                            "INSERT INTO bloques_version
                                (version_id, orden, tipo, contenido)
                             VALUES (?, 1, 'parrafo', ?)"
                        );

                        $insertarBloque->bind_param(
                            'is',
                            $idVersionNueva,
                            $contenido
                        );

                        $insertarBloque->execute();
                        $insertarBloque->close();

                        $copiarFuentes = $mysqli->prepare(
                            "INSERT INTO version_fuentes
                                (version_id, fuente_id)
                             SELECT ?, fuente_id
                             FROM version_fuentes
                             WHERE version_id = ?"
                        );

                        $copiarFuentes->bind_param(
                            'ii',
                            $idVersionNueva,
                            $idVersionAnterior
                        );

                        $copiarFuentes->execute();
                        $copiarFuentes->close();

                        if (!$tieneVersionPublica) {
                            $actualizarPublicacion = $mysqli->prepare(
                                "UPDATE blog
                                 SET categoria_id = ?,
                                     titulo = ?,
                                     `desc` = ?,
                                     img = ?
                                 WHERE id_blog = ?"
                            );

                            $actualizarPublicacion->bind_param(
                                'isssi',
                                $categoriaSeleccionada,
                                $titulo,
                                $descripcion,
                                $imagen,
                                $idBlog
                            );

                            $actualizarPublicacion->execute();
                            $actualizarPublicacion->close();
                        }

                        $mysqli->commit();

                        header(
                            'Location: '
                            . RUTA_WEB
                            . '/Funciones/editar_publicacion.php?id='
                            . (int)$idBlog
                            . '&mensaje=actualizado',
                            true,
                            303
                        );
                        exit;
                    } catch (DomainException $error) {
                        $mysqli->rollback();

                        if (
                            $archivoGuardado !== null &&
                            is_file($archivoGuardado)
                        ) {
                            unlink($archivoGuardado);
                        }

                        $mensaje = $error->getMessage();
                        $tipoMensaje = 'mensaje-error';
                    } catch (Throwable $error) {
                        $mysqli->rollback();

                        if (
                            $archivoGuardado !== null &&
                            is_file($archivoGuardado)
                        ) {
                            unlink($archivoGuardado);
                        }

                        error_log(
                            'Vita Sacra: error al editar publicación, código '
                            . $error->getCode()
                        );

                        $mensaje = 'No fue posible actualizar la publicación. Intenta nuevamente.';
                        $tipoMensaje = 'mensaje-error';
                    }
                }

                if (
                    $tipoMensaje === 'mensaje-error' &&
                    $archivoGuardado !== null &&
                    is_file($archivoGuardado)
                ) {
                    unlink($archivoGuardado);
                }
            }
        }
    }
}

$nombreUsuario = escaparEdicion($_SESSION['nom_usr'] ?? 'Usuario');
$enlacePanel = $esAdministrador
    ? RUTA_WEB . '/Dashboards/dashboard_admin.php'
    : RUTA_WEB . '/Dashboards/dashboard_autor.php';

$tiposEtiqueta = [
    'articulo' => 'Artículo educativo',
    'ficha_medicamento' => 'Ficha educativa de medicamento',
    'ficha_producto' => 'Ficha educativa de producto de salud'
];

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Editar publicación | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparEdicion(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <main class="contenedor contenedor-inicio">
        <header>
            <h1>Editar publicación</h1>
            <p class="subtitulo">
                Sesión de <?php echo $nombreUsuario; ?>
            </p>
        </header>

        <nav class="enlaces" aria-label="Navegación">
            <a href="<?php echo escaparEdicion($enlacePanel); ?>">
                Volver a mi panel
            </a>
            <a href="<?php echo escaparEdicion(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php">
                Mis publicaciones
            </a>
        </nav>

        <?php if ($mensaje !== ''): ?>
            <div
                class="<?php echo escaparEdicion($tipoMensaje); ?>"
                role="status"
                aria-live="polite"
            >
                <?php echo escaparEdicion($mensaje); ?>
            </div>
        <?php endif; ?>

        <section class="tarjeta">
            <?php if ($esPublicacionPublicada): ?>
                <p>
                    Los cambios se guardarán en una nueva versión. La versión
                    pública actual seguirá visible hasta que un administrador
                    apruebe la actualización.
                </p>
            <?php else: ?>
                <p>
                    Los cambios se guardarán en una nueva versión de borrador.
                    No se publicarán automáticamente.
                </p>
            <?php endif; ?>

            <p>
                Tipo de publicación:
                <strong>
                    <?php
                    echo escaparEdicion(
                        $tiposEtiqueta[$tipoPublicacion]
                            ?? $tipoPublicacion
                    );
                    ?>
                </strong>
            </p>

            <?php if ($fuentes !== []): ?>
                <h2>Fuentes de la versión anterior</h2>
                <ul>
                    <?php foreach ($fuentes as $fuente): ?>
                        <li>
                            <strong>
                                <?php echo escaparEdicion($fuente['titulo']); ?>
                            </strong>

                            <?php if (!empty($fuente['autor'])): ?>
                                — <?php echo escaparEdicion($fuente['autor']); ?>
                            <?php endif; ?>

                            <?php if (!empty($fuente['anio'])): ?>
                                (<?php echo (int)$fuente['anio']; ?>)
                            <?php endif; ?>

                            <?php if (!empty($fuente['url'])): ?>
                                —
                                <a
                                    href="<?php echo escaparEdicion($fuente['url']); ?>"
                                    target="_blank"
                                    rel="noopener noreferrer"
                                >
                                    Consultar fuente
                                </a>
                            <?php endif; ?>
                        </li>
                    <?php endforeach; ?>
                </ul>
                <p>Las fuentes se conservarán en la nueva versión.</p>
            <?php endif; ?>

            <form
                method="POST"
                enctype="multipart/form-data"
                action="<?php echo escaparEdicion(RUTA_WEB); ?>/Funciones/editar_publicacion.php?id=<?php echo (int)$idBlog; ?>"
            >
                <input
                    type="hidden"
                    name="csrf_token"
                    value="<?php echo escaparEdicion($csrf); ?>"
                >
                <input type="hidden" name="accion" value="guardar">

                <label for="titulo">Título o denominación</label>
                <input
                    type="text"
                    id="titulo"
                    name="titulo"
                    maxlength="200"
                    value="<?php echo escaparEdicion($titulo); ?>"
                    required
                >

                <label for="descripcion">Descripción general</label>
                <textarea
                    id="descripcion"
                    name="descripcion"
                    maxlength="500"
                    rows="3"
                    required
                ><?php echo escaparEdicion($descripcion); ?></textarea>

                <label for="contenido">Contenido informativo</label>
                <textarea
                    id="contenido"
                    name="contenido"
                    maxlength="50000"
                    rows="10"
                    required
                ><?php echo escaparEdicion($contenido); ?></textarea>

                <label for="advertencia">Advertencia informativa</label>
                <textarea
                    id="advertencia"
                    name="advertencia"
                    maxlength="5000"
                    rows="4"
                    aria-describedby="ayuda-advertencia"
                ><?php echo escaparEdicion($advertencia); ?></textarea>
                <small id="ayuda-advertencia">
                    Obligatoria para fichas educativas de medicamentos y
                    productos de salud.
                </small>

                <label for="categoria">Categoría</label>
                <select id="categoria" name="categoria" required>
                    <option value="">Selecciona una categoría</option>

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
                            <?php echo escaparEdicion($categoria['nombre']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <?php if (!empty($imagenActual)): ?>
                    <h2>Imagen actual de esta versión</h2>
                    <img
                        src="<?php echo escaparEdicion(rutaImagenEdicion($imagenActual)); ?>"
                        alt="Imagen actual de la publicación"
                        style="max-width: 100%; height: auto;"
                    >
                <?php endif; ?>

                <label for="tipo_imagen">Imagen</label>
                <select id="tipo_imagen" name="tipo_imagen">
                    <option value="conservar">Conservar imagen actual</option>
                    <option value="ninguna">Quitar imagen</option>
                    <option value="enlace">Cambiar por enlace</option>
                    <option value="local">Subir un archivo</option>
                </select>

                <label for="imagen_url">Enlace HTTP o HTTPS</label>
                <input
                    type="url"
                    id="imagen_url"
                    name="imagen_url"
                    maxlength="255"
                    placeholder="https://ejemplo.com/imagen.jpg"
                >

                <label for="imagen_archivo">Archivo de imagen</label>
                <input
                    type="file"
                    id="imagen_archivo"
                    name="imagen_archivo"
                    accept="image/jpeg,image/png,image/webp,image/gif"
                >
                <small>JPG, PNG, WEBP o GIF; máximo 5 MB.</small>

                <button type="submit">Guardar nueva versión</button>
            </form>
        </section>

        <form
            action="<?php echo escaparEdicion(RUTA_WEB); ?>/Conexiones/cerrar_sesion.php"
            method="POST"
        >
            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escaparEdicion($csrf); ?>"
            >
            <button type="submit" class="boton-secundario">
                Cerrar sesión
            </button>
        </form>
    </main>
</body>
</html>