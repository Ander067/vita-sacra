<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

date_default_timezone_set('America/Mexico_City');

requiereRol($mysqli, 'autor', 'administrador');

$rolesActuales = obtenerRolesActuales($mysqli);
$esAdministrador = in_array('administrador', $rolesActuales, true);

$mensaje = '';
$tipoMensaje = '';
$csrf = generarCSRF();

$titulo = '';
$descripcion = '';
$contenido = '';
$advertencia = '';
$categoriaSeleccionada = '';
$tipoPublicacion = 'articulo';
$tipoImagen = 'ninguna';
$imagenURL = '';

function escaparNuevaPublicacion($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postNuevaPublicacion(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';

    return is_string($valor) ? $valor : '';
}

$categorias = $mysqli->query(
    "SELECT id_categoria, nombre
     FROM categorias
     WHERE activa = 1
     ORDER BY nombre"
)->fetch_all(MYSQLI_ASSOC);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!verificarCSRF(postNuevaPublicacion('csrf_token'))) {
        $mensaje = 'La solicitud no es válida. Actualiza la página e intenta nuevamente.';
        $tipoMensaje = 'mensaje-error';
    } else {
        $titulo = trim(postNuevaPublicacion('titulo'));
        $descripcion = trim(postNuevaPublicacion('descripcion'));
        $contenido = trim(postNuevaPublicacion('contenido'));
        $advertencia = trim(postNuevaPublicacion('advertencia'));
        $categoriaSeleccionada = postNuevaPublicacion('categoria');
        $tipoPublicacion = postNuevaPublicacion('tipo');
        $tipoImagen = postNuevaPublicacion('tipo_imagen');
        $imagenURL = trim(postNuevaPublicacion('imagen_url'));

        $categoria = filter_var(
            $categoriaSeleccionada,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        );

        $tiposPermitidos = [
            'articulo',
            'ficha_medicamento',
            'ficha_producto'
        ];

        $esFichaSalud = in_array(
            $tipoPublicacion,
            ['ficha_medicamento', 'ficha_producto'],
            true
        );

        $longitudTitulo = mb_strlen($titulo, 'UTF-8');
        $longitudDescripcion = mb_strlen($descripcion, 'UTF-8');
        $longitudContenido = mb_strlen($contenido, 'UTF-8');
        $longitudAdvertencia = mb_strlen($advertencia, 'UTF-8');

        if (
            $titulo === '' ||
            $descripcion === '' ||
            $contenido === '' ||
            $categoria === false
        ) {
            $mensaje = 'Completa el título, la descripción, el contenido y la categoría.';
            $tipoMensaje = 'mensaje-error';
        } elseif (!in_array($tipoPublicacion, $tiposPermitidos, true)) {
            $mensaje = 'Selecciona un tipo de publicación válido.';
            $tipoMensaje = 'mensaje-error';
        } elseif ($longitudTitulo > 200) {
            $mensaje = 'El título no puede superar los 200 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif ($longitudDescripcion > 500) {
            $mensaje = 'La descripción no puede superar los 500 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif ($longitudContenido > 50000) {
            $mensaje = 'El contenido no puede superar los 50,000 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif ($esFichaSalud && $advertencia === '') {
            $mensaje = 'Las fichas educativas deben incluir una advertencia informativa.';
            $tipoMensaje = 'mensaje-error';
        } elseif ($longitudAdvertencia > 5000) {
            $mensaje = 'La advertencia no puede superar los 5,000 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif (!in_array($tipoImagen, ['ninguna', 'enlace', 'local'], true)) {
            $mensaje = 'Selecciona una opción de imagen válida.';
            $tipoMensaje = 'mensaje-error';
        } elseif (
            $tipoImagen === 'enlace' &&
            (
                $imagenURL === '' ||
                strlen($imagenURL) > 255 ||
                !filter_var($imagenURL, FILTER_VALIDATE_URL) ||
                !in_array(
                    strtolower((string)parse_url($imagenURL, PHP_URL_SCHEME)),
                    ['http', 'https'],
                    true
                )
            )
        ) {
            $mensaje = 'Ingresa una dirección de imagen HTTP o HTTPS válida, de hasta 255 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif (
            $tipoImagen === 'local' &&
            (
                !isset($_FILES['imagen_archivo']) ||
                !is_array($_FILES['imagen_archivo']) ||
                (int)($_FILES['imagen_archivo']['error'] ?? UPLOAD_ERR_NO_FILE)
                    !== UPLOAD_ERR_OK
            )
        ) {
            $mensaje = 'Selecciona una imagen válida de tu dispositivo.';
            $tipoMensaje = 'mensaje-error';
        } else {
            $consultaCategoria = $mysqli->prepare(
                "SELECT id_categoria
                 FROM categorias
                 WHERE id_categoria = ?
                   AND activa = 1
                 LIMIT 1"
            );

            $consultaCategoria->bind_param('i', $categoria);
            $consultaCategoria->execute();
            $categoriaValida = $consultaCategoria
                ->get_result()
                ->fetch_assoc();
            $consultaCategoria->close();

            if (!$categoriaValida) {
                $mensaje = 'La categoría seleccionada no existe o está inactiva.';
                $tipoMensaje = 'mensaje-error';
            } else {
                $imagen = null;
                $archivoGuardado = null;

                if ($tipoImagen === 'enlace') {
                    $imagen = $imagenURL;
                } elseif ($tipoImagen === 'local') {
                    $archivo = $_FILES['imagen_archivo'];
                    $tamano = (int)($archivo['size'] ?? 0);
                    $rutaTemporal = $archivo['tmp_name'] ?? '';

                    if ($tamano <= 0 || $tamano > 5 * 1024 * 1024) {
                        $mensaje = 'La imagen debe pesar más de 0 y no superar los 5 MB.';
                        $tipoMensaje = 'mensaje-error';
                    } elseif (!is_uploaded_file($rutaTemporal)) {
                        $mensaje = 'El archivo recibido no es una carga válida.';
                        $tipoMensaje = 'mensaje-error';
                    } else {
                        $informacionImagen = @getimagesize($rutaTemporal);

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

                                if (move_uploaded_file($rutaTemporal, $rutaCompleta)) {
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
                        $slugBase = iconv(
                            'UTF-8',
                            'ASCII//TRANSLIT//IGNORE',
                            $titulo
                        );

                        if (!is_string($slugBase)) {
                            $slugBase = '';
                        }

                        $slugBase = strtolower(
                            trim(
                                preg_replace(
                                    '/[^a-zA-Z0-9]+/',
                                    '-',
                                    $slugBase
                                ),
                                '-'
                            )
                        );

                        if ($slugBase === '') {
                            $slugBase = 'publicacion';
                        }

                        $slug = substr($slugBase, 0, 190)
                            . '-'
                            . bin2hex(random_bytes(4));

                        $idUsuario = (int)$_SESSION['id_usr'];
                        $plantilla = 1;
                        $estatus = 'borrador';
                        $estatusVersion = 'borrador';
                        $advertenciaDB = $advertencia !== ''
                            ? $advertencia
                            : null;

                        $insertar = $mysqli->prepare(
                            "INSERT INTO blog
                                (
                                    usr_id,
                                    categoria_id,
                                    plantilla_id,
                                    titulo,
                                    `desc`,
                                    img,
                                    slug,
                                    tipo,
                                    estatus,
                                    fecha_publicacion
                                )
                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)"
                        );

                        $insertar->bind_param(
                            'iiissssss',
                            $idUsuario,
                            $categoria,
                            $plantilla,
                            $titulo,
                            $descripcion,
                            $imagen,
                            $slug,
                            $tipoPublicacion,
                            $estatus
                        );

                        $insertar->execute();
                        $idBlog = (int)$mysqli->insert_id;
                        $insertar->close();

                        $numeroVersion = 1;

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
                            'iisssiss',
                            $idBlog,
                            $numeroVersion,
                            $advertenciaDB,
                            $estatusVersion,
                            $titulo,
                            $descripcion,
                            $categoria,
                            $imagen,
                            $tipoPublicacion
                        );

                        $insertarVersion->execute();
                        $idVersion = (int)$mysqli->insert_id;
                        $insertarVersion->close();

                        $insertarBloque = $mysqli->prepare(
                            "INSERT INTO bloques_version
                                (version_id, orden, tipo, contenido)
                             VALUES (?, 1, 'parrafo', ?)"
                        );

                        $insertarBloque->bind_param(
                            'is',
                            $idVersion,
                            $contenido
                        );

                        $insertarBloque->execute();
                        $insertarBloque->close();

                        $mysqli->commit();

                        header(
                            'Location: '
                            . RUTA_WEB
                            . '/Funciones/publicaciones.php?mensaje=guardado',
                            true,
                            303
                        );
                        exit;
                    } catch (Throwable $error) {
                        $mysqli->rollback();

                        if (
                            $archivoGuardado !== null &&
                            is_file($archivoGuardado)
                        ) {
                            unlink($archivoGuardado);
                        }

                        error_log(
                            'Vita Sacra: error al crear borrador, código '
                            . $error->getCode()
                        );

                        $mensaje = 'No fue posible guardar el borrador. Intenta nuevamente.';
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

if (isset($_GET['mensaje']) && is_string($_GET['mensaje'])) {
    if ($_GET['mensaje'] === 'guardado') {
        $mensaje = 'El borrador se guardó correctamente.';
        $tipoMensaje = 'mensaje-exito';
    }
}

$enlacePanel = $esAdministrador
    ? RUTA_WEB . '/Dashboards/dashboard_admin.php'
    : RUTA_WEB . '/Dashboards/dashboard_autor.php';

$nombreUsuario = escaparNuevaPublicacion(
    $_SESSION['nom_usr'] ?? 'Usuario'
);

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Crear borrador | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparNuevaPublicacion(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <main class="contenedor contenedor-inicio">
        <header>
            <h1>Crear borrador</h1>
            <p class="subtitulo">
                Sesión de <?php echo $nombreUsuario; ?>
            </p>
        </header>

        <nav class="enlaces" aria-label="Navegación">
            <a href="<?php echo escaparNuevaPublicacion($enlacePanel); ?>">
                Volver a mi panel
            </a>
            <a href="<?php echo escaparNuevaPublicacion(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php">
                Gestionar publicaciones
            </a>
        </nav>

        <?php if ($mensaje !== ''): ?>
            <div
                class="<?php echo escaparNuevaPublicacion($tipoMensaje); ?>"
                role="status"
                aria-live="polite"
            >
                <?php echo escaparNuevaPublicacion($mensaje); ?>
            </div>
        <?php endif; ?>

        <section class="tarjeta">
            <h2>Nueva publicación</h2>
            <p>
                Se guardará como borrador y quedará asociada a tu cuenta.
                No se hará pública al guardarla.
            </p>

            <form method="POST" enctype="multipart/form-data">
                <input
                    type="hidden"
                    name="csrf_token"
                    value="<?php echo escaparNuevaPublicacion($csrf); ?>"
                >

                <label for="tipo">Tipo de publicación</label>
                <select id="tipo" name="tipo" required>
                    <option
                        value="articulo"
                        <?php echo $tipoPublicacion === 'articulo' ? 'selected' : ''; ?>
                    >
                        Artículo educativo
                    </option>
                    <option
                        value="ficha_medicamento"
                        <?php echo $tipoPublicacion === 'ficha_medicamento' ? 'selected' : ''; ?>
                    >
                        Ficha educativa de medicamento
                    </option>
                    <option
                        value="ficha_producto"
                        <?php echo $tipoPublicacion === 'ficha_producto' ? 'selected' : ''; ?>
                    >
                        Ficha educativa de producto de salud
                    </option>
                </select>

                <label for="titulo">Título o denominación</label>
                <input
                    type="text"
                    id="titulo"
                    name="titulo"
                    maxlength="200"
                    value="<?php echo escaparNuevaPublicacion($titulo); ?>"
                    required
                >

                <label for="descripcion">Descripción general</label>
                <textarea
                    id="descripcion"
                    name="descripcion"
                    maxlength="500"
                    rows="3"
                    required
                ><?php echo escaparNuevaPublicacion($descripcion); ?></textarea>

                <label for="contenido">Contenido informativo</label>
                <textarea
                    id="contenido"
                    name="contenido"
                    rows="10"
                    maxlength="50000"
                    required
                ><?php echo escaparNuevaPublicacion($contenido); ?></textarea>

                <label for="advertencia">Advertencia informativa</label>
                <textarea
                    id="advertencia"
                    name="advertencia"
                    maxlength="5000"
                    rows="4"
                    aria-describedby="ayuda-advertencia"
                ><?php echo escaparNuevaPublicacion($advertencia); ?></textarea>
                <small id="ayuda-advertencia">
                    Obligatoria para fichas educativas de medicamentos y
                    productos de salud.
                </small>

                <p class="mensaje">
                    El contenido de salud es exclusivamente informativo. No
                    incluyas diagnósticos, prescripciones, dosis personalizadas
                    ni ofertas de venta.
                </p>

                <label for="categoria">Categoría</label>
                <select id="categoria" name="categoria" required>
                    <option value="">Selecciona una categoría</option>

                    <?php foreach ($categorias as $categoria): ?>
                        <option
                            value="<?php echo (int)$categoria['id_categoria']; ?>"
                            <?php
                            echo (string)$categoriaSeleccionada
                                === (string)$categoria['id_categoria']
                                ? 'selected'
                                : '';
                            ?>
                        >
                            <?php
                            echo escaparNuevaPublicacion($categoria['nombre']);
                            ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <fieldset>
                    <legend>Imagen (opcional)</legend>

                    <label for="tipo_imagen">Origen de la imagen</label>
                    <select id="tipo_imagen" name="tipo_imagen">
                        <option
                            value="ninguna"
                            <?php echo $tipoImagen === 'ninguna' ? 'selected' : ''; ?>
                        >
                            Sin imagen
                        </option>
                        <option
                            value="enlace"
                            <?php echo $tipoImagen === 'enlace' ? 'selected' : ''; ?>
                        >
                            Enlace web
                        </option>
                        <option
                            value="local"
                            <?php echo $tipoImagen === 'local' ? 'selected' : ''; ?>
                        >
                            Archivo de mi dispositivo
                        </option>
                    </select>

                    <label for="imagen_url">Enlace HTTP o HTTPS</label>
                    <input
                        type="url"
                        id="imagen_url"
                        name="imagen_url"
                        maxlength="255"
                        value="<?php echo escaparNuevaPublicacion($imagenURL); ?>"
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
                </fieldset>

                <button type="submit">Guardar borrador</button>
            </form>
        </section>

        <form
            action="<?php echo escaparNuevaPublicacion(RUTA_WEB); ?>/Conexiones/cerrar_sesion.php"
            method="POST"
        >
            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escaparNuevaPublicacion($csrf); ?>"
            >
            <button type="submit" class="boton-secundario">
                Cerrar sesión
            </button>
        </form>
    </main>
</body>
</html>