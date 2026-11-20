<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';
require_once __DIR__ . '/componentes/cabecera.php';

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

function bloquesEdicion($entrada): array
{
    if (!is_array($entrada)) {
        return [];
    }

    $permitidos = [
        'titulo',
        'parrafo',
        'lista',
        'cita',
        'enlace',
        'imagen',
        'pdf',
        'video',
        'modelo_3d'
    ];
    $bloques = [];

    foreach ($entrada as $fila) {
        if (!is_array($fila)) {
            continue;
        }

        $tipo = is_string($fila['tipo'] ?? null)
            ? $fila['tipo']
            : '';
        $contenido = is_string($fila['contenido'] ?? null)
            ? trim($fila['contenido'])
            : '';
        $recursoRecibido = $fila['recurso_id'] ?? '';
        $recursoId = is_scalar($recursoRecibido)
            ? filter_var(
                $recursoRecibido,
                FILTER_VALIDATE_INT,
                ['options' => ['min_range' => 1]]
            )
            : false;

        $bloques[] = [
            'tipo' => $tipo,
            'contenido' => $contenido,
            'recurso_id' => $recursoId === false ? null : (int)$recursoId,
            'tipo_valido' => in_array($tipo, $permitidos, true)
        ];
    }

    return array_values($bloques);
}

function guardarImagenEdicion(
    string $tipo,
    string $url,
    $archivo,
    ?string $imagenActual,
    ?string &$rutaArchivoGuardado
): ?string {
    $rutaArchivoGuardado = null;

    if ($tipo === 'conservar') {
        return $imagenActual;
    }

    if ($tipo === 'ninguna') {
        return null;
    }

    if ($tipo === 'enlace') {
        if (
            $url === ''
            || strlen($url) > 255
            || !filter_var($url, FILTER_VALIDATE_URL)
            || !in_array(
                strtolower((string)parse_url($url, PHP_URL_SCHEME)),
                ['http', 'https'],
                true
            )
        ) {
            throw new DomainException(
                'Ingresa una dirección de imagen HTTP o HTTPS válida.'
            );
        }

        return $url;
    }

    if ($tipo !== 'local' || !is_array($archivo)) {
        throw new DomainException('Selecciona un tipo de imagen válido.');
    }

    if ((int)($archivo['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        throw new DomainException('Selecciona una imagen válida.');
    }

    $tamano = (int)($archivo['size'] ?? 0);
    $temporal = $archivo['tmp_name'] ?? '';

    if ($tamano <= 0 || $tamano > 5 * 1024 * 1024) {
        throw new DomainException(
            'La imagen debe pesar más de 0 y no superar los 5 MB.'
        );
    }

    if (!is_string($temporal) || !is_uploaded_file($temporal)) {
        throw new DomainException('El archivo recibido no es una carga válida.');
    }

    $datosImagen = @getimagesize($temporal);
    $formatos = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif'
    ];
    $mime = is_array($datosImagen)
        ? (string)($datosImagen['mime'] ?? '')
        : '';

    if (!isset($formatos[$mime])) {
        throw new DomainException('La imagen debe ser JPG, PNG, WEBP o GIF.');
    }

    $carpeta = __DIR__ . '/../Recursos/uploads/publicaciones/';

    if (
        !is_dir($carpeta)
        && !mkdir($carpeta, 0755, true)
        && !is_dir($carpeta)
    ) {
        throw new RuntimeException('No se pudo preparar la carpeta de imágenes.');
    }

    if (!is_writable($carpeta)) {
        throw new RuntimeException('No se puede guardar la imagen en el servidor.');
    }

    $nombre = bin2hex(random_bytes(16)) . '.' . $formatos[$mime];
    $destino = $carpeta . $nombre;

    if (!move_uploaded_file($temporal, $destino)) {
        throw new RuntimeException('No fue posible guardar la imagen.');
    }

    $rutaArchivoGuardado = $destino;

    return 'Recursos/uploads/publicaciones/' . $nombre;
}

function rutaImagenEdicion($imagen): string
{
    if (!is_string($imagen) || trim($imagen) === '') {
        return '';
    }

    $imagen = trim($imagen);

    if (filter_var($imagen, FILTER_VALIDATE_URL)) {
        $esquema = strtolower((string)parse_url($imagen, PHP_URL_SCHEME));

        return in_array($esquema, ['http', 'https'], true)
            ? $imagen
            : '';
    }

    $imagen = str_replace('\\', '/', $imagen);

    if (str_contains($imagen, '..')) {
        return '';
    }

    return rtrim(RUTA_WEB, '/') . '/' . ltrim($imagen, '/');
}

$idRecibido = $_GET['id'] ?? null;
$idBlog = is_scalar($idRecibido)
    ? filter_var(
        $idRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

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
        b.plantilla_id,
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
        tipo_snapshot,
        plantilla_id_snapshot
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

$tieneVersionPublica = $publicacion['version_publica'] !== null;
$estadosPermitidos = $tieneVersionPublica
    ? ['publicado', 'correccion', 'rechazado']
    : ['borrador', 'correccion'];

if (!in_array($versionActual['estatus'], $estadosPermitidos, true)) {
    http_response_code(409);
    exit('La versión está pendiente de revisión o no puede editarse.');
}

$idVersionAnterior = (int)$versionActual['id_version'];

$consultaBloques = $mysqli->prepare(
    "SELECT orden, tipo, contenido, recurso_id
     FROM bloques_version
     WHERE version_id = ?
     ORDER BY orden ASC"
);
$consultaBloques->bind_param('i', $idVersionAnterior);
$consultaBloques->execute();
$bloquesBD = $consultaBloques
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaBloques->close();

$bloquesFormulario = [];
foreach ($bloquesBD as $bloqueBD) {
    $bloquesFormulario[] = [
        'tipo' => (string)$bloqueBD['tipo'],
        'contenido' => (string)($bloqueBD['contenido'] ?? ''),
        'recurso_id' => $bloqueBD['recurso_id'] !== null
            ? (int)$bloqueBD['recurso_id']
            : null,
        'tipo_valido' => true
    ];
}

if ($bloquesFormulario === []) {
    $bloquesFormulario[] = [
        'tipo' => 'parrafo',
        'contenido' => '',
        'recurso_id' => null,
        'tipo_valido' => true
    ];
}

$fuentes = $mysqli->prepare(
    "SELECT f.titulo, f.autor, f.url, f.anio
     FROM version_fuentes vf
     INNER JOIN fuentes f
        ON f.id_fuente = vf.fuente_id
     WHERE vf.version_id = ?
     ORDER BY f.titulo"
);
$fuentes->bind_param('i', $idVersionAnterior);
$fuentes->execute();
$fuentesActuales = $fuentes->get_result()->fetch_all(MYSQLI_ASSOC);
$fuentes->close();

$categorias = $mysqli->query(
    "SELECT id_categoria, nombre
     FROM categorias
     WHERE activa = 1
     ORDER BY nombre"
)->fetch_all(MYSQLI_ASSOC);

$plantillas = $mysqli->query(
    "SELECT id_plantilla, nombre, descripcion
     FROM plantillas
     WHERE nombre IN ('clasica', 'divulgativa', 'visual')
     ORDER BY FIELD(nombre, 'clasica', 'divulgativa', 'visual')"
)->fetch_all(MYSQLI_ASSOC);

$recursos = $mysqli->query(
    "SELECT id_recurso, tipo, titulo, url
     FROM recursos
     WHERE estatus = 'aprobado'
       AND tipo IN ('imagen', 'pdf', 'video', 'modelo_3d')
     ORDER BY tipo, titulo"
)->fetch_all(MYSQLI_ASSOC);

$recursosPorId = [];
foreach ($recursos as $recurso) {
    $recursosPorId[(int)$recurso['id_recurso']] = $recurso;
}

$titulo = (string)$versionActual['titulo_snapshot'];
$descripcion = (string)($versionActual['descripcion_snapshot'] ?? '');
$advertencia = (string)($versionActual['advertencia'] ?? '');
$categoriaSeleccionada = (int)$versionActual['categoria_id_snapshot'];
$tipoPublicacion = (string)$versionActual['tipo_snapshot'];
$plantillaSeleccionada = (int)(
    $versionActual['plantilla_id_snapshot']
    ?? $publicacion['plantilla_id']
);
$imagenActual = $versionActual['imagen_snapshot'];
$imagen = $imagenActual;

$mensaje = '';
$tipoMensaje = '';
$csrf = generarCSRF();
$tipoImagen = 'conservar';
$imagenURL = '';

if (($_GET['mensaje'] ?? '') === 'actualizado') {
    $mensaje = $tieneVersionPublica
        ? 'Se guardó una nueva versión. La versión publicada sigue visible.'
        : 'Se guardó una nueva versión del borrador.';
    $tipoMensaje = 'mensaje-exito';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $titulo = trim(postEdicion('titulo'));
    $descripcion = trim(postEdicion('descripcion'));
    $advertencia = trim(postEdicion('advertencia'));
    $tipoImagen = postEdicion('tipo_imagen');
    $imagenURL = trim(postEdicion('imagen_url'));
    $bloquesFormulario = bloquesEdicion($_POST['bloques'] ?? []);

    $categoriaRecibida = filter_var(
        postEdicion('categoria'),
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );
    $plantillaRecibida = filter_var(
        postEdicion('plantilla_id'),
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );

    $archivoGuardado = null;

    try {
        if (!verificarCSRF(postEdicion('csrf_token'))) {
            throw new DomainException(
                'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
            );
        }

        if (postEdicion('accion') !== 'guardar') {
            throw new DomainException('La acción solicitada no es válida.');
        }

        if ($titulo === '' || mb_strlen($titulo, 'UTF-8') > 200) {
            throw new DomainException(
                'El título es obligatorio y no puede superar 200 caracteres.'
            );
        }

        if ($descripcion === '' || mb_strlen($descripcion, 'UTF-8') > 500) {
            throw new DomainException(
                'La descripción es obligatoria y no puede superar 500 caracteres.'
            );
        }

        if (
            in_array(
                $tipoPublicacion,
                ['ficha_medicamento', 'ficha_producto'],
                true
            )
            && $advertencia === ''
        ) {
            throw new DomainException(
                'La ficha educativa debe incluir una advertencia informativa.'
            );
        }

        if (mb_strlen($advertencia, 'UTF-8') > 5000) {
            throw new DomainException(
                'La advertencia no puede superar 5,000 caracteres.'
            );
        }

        if ($categoriaRecibida === false || $plantillaRecibida === false) {
            throw new DomainException(
                'Selecciona una categoría y plantilla válidas.'
            );
        }

        $categoriaSeleccionada = (int)$categoriaRecibida;
        $plantillaSeleccionada = (int)$plantillaRecibida;

        $categoriaValida = false;
        foreach ($categorias as $categoria) {
            if ((int)$categoria['id_categoria'] === $categoriaSeleccionada) {
                $categoriaValida = true;
                break;
            }
        }

        $plantillaValida = false;
        foreach ($plantillas as $plantilla) {
            if ((int)$plantilla['id_plantilla'] === $plantillaSeleccionada) {
                $plantillaValida = true;
                break;
            }
        }

        if (!$categoriaValida || !$plantillaValida) {
            throw new DomainException(
                'La categoría o plantilla seleccionada ya no está disponible.'
            );
        }

        if ($bloquesFormulario === [] || count($bloquesFormulario) > 50) {
            throw new DomainException(
                'Agrega entre 1 y 50 bloques de contenido.'
            );
        }

        $hayTexto = false;
        $tiposRecurso = [
            'imagen' => 'imagen',
            'pdf' => 'pdf',
            'video' => 'video',
            'modelo_3d' => 'modelo_3d'
        ];

        foreach ($bloquesFormulario as $bloque) {
            if (!$bloque['tipo_valido']) {
                throw new DomainException(
                    'Uno de los tipos de bloque no es válido.'
                );
            }

            $tipo = $bloque['tipo'];
            $contenido = $bloque['contenido'];

            if (in_array($tipo, ['titulo', 'parrafo', 'lista', 'cita'], true)) {
                if ($contenido === '' || mb_strlen($contenido, 'UTF-8') > 10000) {
                    throw new DomainException(
                        'Completa el contenido de cada bloque de texto.'
                    );
                }
                $hayTexto = true;
            } elseif ($tipo === 'enlace') {
                if (
                    strlen($contenido) > 1000
                    || !filter_var($contenido, FILTER_VALIDATE_URL)
                    || !in_array(
                        strtolower((string)parse_url($contenido, PHP_URL_SCHEME)),
                        ['http', 'https'],
                        true
                    )
                ) {
                    throw new DomainException(
                        'Los bloques de enlace deben usar una URL HTTP o HTTPS válida.'
                    );
                }
                $hayTexto = true;
            } else {
                $idRecurso = $bloque['recurso_id'];
                $recurso = $idRecurso !== null
                    ? ($recursosPorId[$idRecurso] ?? null)
                    : null;

                if (
                    !$recurso
                    || $recurso['tipo'] !== ($tiposRecurso[$tipo] ?? '')
                ) {
                    throw new DomainException(
                        'Selecciona un recurso aprobado del tipo correspondiente.'
                    );
                }
            }
        }

        if (!$hayTexto) {
            throw new DomainException(
                'Agrega al menos un bloque de texto o enlace.'
            );
        }

        $imagen = guardarImagenEdicion(
            $tipoImagen,
            $imagenURL,
            $_FILES['imagen_archivo'] ?? null,
            $imagenActual,
            $archivoGuardado
        );

        $mysqli->begin_transaction();

        try {
            $bloqueoBlog = $mysqli->prepare(
                "SELECT usr_id, estatus, version_publica
                 FROM blog
                 WHERE id_blog = ?
                 LIMIT 1
                 FOR UPDATE"
            );
            $bloqueoBlog->bind_param('i', $idBlog);
            $bloqueoBlog->execute();
            $blogBloqueado = $bloqueoBlog->get_result()->fetch_assoc();
            $bloqueoBlog->close();

            if (
                !$blogBloqueado
                || (
                    !$esAdministrador
                    && (int)$blogBloqueado['usr_id'] !== $idUsuario
                )
            ) {
                throw new DomainException(
                    'No tienes permiso para editar esta publicación.'
                );
            }

            $tienePublicacionAprobada =
                $blogBloqueado['version_publica'] !== null;

            if (
                (
                    !$tienePublicacionAprobada
                    && !in_array(
                        $blogBloqueado['estatus'],
                        ['borrador', 'correccion'],
                        true
                    )
                )
                || (
                    $tienePublicacionAprobada
                    && $blogBloqueado['estatus'] !== 'publicado'
                )
            ) {
                throw new DomainException(
                    'La publicación no está disponible para edición.'
                );
            }

            $consultaVersionBloqueada = $mysqli->prepare(
                "SELECT id_version, numero, estatus
                 FROM versiones_blog
                 WHERE blog_id = ?
                 ORDER BY numero DESC
                 LIMIT 1
                 FOR UPDATE"
            );
            $consultaVersionBloqueada->bind_param('i', $idBlog);
            $consultaVersionBloqueada->execute();
            $versionBloqueada = $consultaVersionBloqueada
                ->get_result()
                ->fetch_assoc();
            $consultaVersionBloqueada->close();

            if (!$versionBloqueada) {
                throw new DomainException(
                    'No se encontró una versión editable.'
                );
            }

            $estadosEditables = $tienePublicacionAprobada
                ? ['publicado', 'correccion', 'rechazado']
                : ['borrador', 'correccion'];

            if (!in_array($versionBloqueada['estatus'], $estadosEditables, true)) {
                throw new DomainException(
                    'La versión está pendiente de revisión y no puede editarse.'
                );
            }

            $numeroVersion = (int)$versionBloqueada['numero'] + 1;
            $estatusVersion = $tienePublicacionAprobada
                ? (
                    $versionBloqueada['estatus'] === 'correccion'
                        ? 'correccion'
                        : 'borrador'
                )
                : (string)$blogBloqueado['estatus'];
            $advertenciaDB = $advertencia !== '' ? $advertencia : null;

            $insertarVersion = $mysqli->prepare(
                "INSERT INTO versiones_blog
                    (
                        blog_id, numero, advertencia, estatus,
                        titulo_snapshot, descripcion_snapshot,
                        categoria_id_snapshot, imagen_snapshot,
                        tipo_snapshot, plantilla_id_snapshot
                    )
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            );
            $insertarVersion->bind_param(
                'iissssissi',
                $idBlog,
                $numeroVersion,
                $advertenciaDB,
                $estatusVersion,
                $titulo,
                $descripcion,
                $categoriaSeleccionada,
                $imagen,
                $tipoPublicacion,
                $plantillaSeleccionada
            );
            $insertarVersion->execute();
            $idVersionNueva = (int)$mysqli->insert_id;
            $insertarVersion->close();

            $insertarBloque = $mysqli->prepare(
                "INSERT INTO bloques_version
                    (version_id, orden, tipo, contenido, recurso_id)
                 VALUES (?, ?, ?, ?, ?)"
            );

            foreach ($bloquesFormulario as $indice => $bloque) {
                $orden = $indice + 1;
                $tipo = $bloque['tipo'];
                $contenido = in_array(
                    $tipo,
                    ['imagen', 'pdf', 'video', 'modelo_3d'],
                    true
                ) ? null : $bloque['contenido'];
                $recursoId = $bloque['recurso_id'];

                $insertarBloque->bind_param(
                    'iissi',
                    $idVersionNueva,
                    $orden,
                    $tipo,
                    $contenido,
                    $recursoId
                );
                $insertarBloque->execute();
            }

            $insertarBloque->close();

            $copiarFuentes = $mysqli->prepare(
                "INSERT INTO version_fuentes (version_id, fuente_id)
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

            if (!$tienePublicacionAprobada) {
                $actualizarBlog = $mysqli->prepare(
                    "UPDATE blog
                     SET categoria_id = ?,
                         plantilla_id = ?,
                         titulo = ?,
                         `desc` = ?,
                         img = ?
                     WHERE id_blog = ?"
                );
                $actualizarBlog->bind_param(
                    'iisssi',
                    $categoriaSeleccionada,
                    $plantillaSeleccionada,
                    $titulo,
                    $descripcion,
                    $imagen,
                    $idBlog
                );
                $actualizarBlog->execute();
                $actualizarBlog->close();
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
        } catch (Throwable $error) {
            $mysqli->rollback();

            if ($archivoGuardado !== null && is_file($archivoGuardado)) {
                unlink($archivoGuardado);
            }

            throw $error;
        }
    } catch (DomainException $error) {
        $mensaje = $error->getMessage();
        $tipoMensaje = 'mensaje-error';
    } catch (mysqli_sql_exception $error) {
        error_log(
            'Vita Sacra: error al editar publicación: '
            . $error->getMessage()
        );
        $mensaje = 'No fue posible guardar la nueva versión.';
        $tipoMensaje = 'mensaje-error';
    } catch (RuntimeException $error) {
        $mensaje = $error->getMessage();
        $tipoMensaje = 'mensaje-error';
    }
}

$nombreNav = $_SESSION['nom_usr'] ?? 'Mi cuenta';
$nombreNav = is_string($nombreNav) ? $nombreNav : 'Mi cuenta';
$rolNav = $esAdministrador ? 'administrador' : 'autor';
$enlacePanel = $esAdministrador
    ? RUTA_WEB . '/Dashboards/dashboard_admin.php'
    : RUTA_WEB . '/Dashboards/dashboard_autor.php';

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
    <style>
        .bloques-editor { display: grid; gap: 16px; }
        .bloque-editor { padding: 18px; border: 1px solid var(--bordes); border-radius: var(--radio); background: var(--superficie); }
        .bloque-controles { display: flex; flex-wrap: wrap; gap: 8px; }
        .vista-previa { padding: 22px; border: 1px solid var(--bordes); border-radius: var(--radio); background: var(--superficie); }
        .vista-previa.plantilla-divulgativa { border-top: 5px solid var(--azul); }
        .vista-previa.plantilla-visual { background: var(--azul-claro); }
        .campo-recurso[hidden] { display: none; }
    </style>
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreNav,
        $rolNav,
        'gestionar',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Editar publicación</h1>
                <p>
                    Los cambios se guardarán en una nueva versión. Si ya está
                    publicada, la versión pública seguirá visible hasta su
                    aprobación.
                </p>
            </div>
        </section>

        <nav class="enlaces" aria-label="Navegación">
            <a class="boton boton-secundario" href="<?php echo escaparEdicion($enlacePanel); ?>">
                Volver a mi panel
            </a>
            <a class="boton boton-secundario" href="<?php echo escaparEdicion(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php">
                Mis publicaciones
            </a>
        </nav>

        <?php if ($mensaje !== ''): ?>
            <div class="<?php echo escaparEdicion($tipoMensaje); ?>" role="status">
                <?php echo escaparEdicion($mensaje); ?>
            </div>
        <?php endif; ?>

        <form
            class="seccion-admin"
            method="POST"
            enctype="multipart/form-data"
            action="<?php echo escaparEdicion(RUTA_WEB); ?>/Funciones/editar_publicacion.php?id=<?php echo (int)$idBlog; ?>"
        >
            <input type="hidden" name="csrf_token" value="<?php echo escaparEdicion($csrf); ?>">
            <input type="hidden" name="accion" value="guardar">

            <section class="tarjeta">
                <h2>Datos de la publicación</h2>

                <label for="titulo">Título</label>
                <input id="titulo" name="titulo" maxlength="200" required value="<?php echo escaparEdicion($titulo); ?>">

                <label for="descripcion">Descripción</label>
                <textarea id="descripcion" name="descripcion" maxlength="500" rows="3" required><?php echo escaparEdicion($descripcion); ?></textarea>

                <p>
                    Tipo:
                    <strong><?php echo escaparEdicion($tipoPublicacion); ?></strong>
                </p>

                <label for="categoria">Categoría</label>
                <select id="categoria" name="categoria" required>
                    <?php foreach ($categorias as $categoria): ?>
                        <option value="<?php echo (int)$categoria['id_categoria']; ?>" <?php echo $categoriaSeleccionada === (int)$categoria['id_categoria'] ? 'selected' : ''; ?>>
                            <?php echo escaparEdicion($categoria['nombre']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <label for="plantilla_id">Plantilla</label>
                <select id="plantilla_id" name="plantilla_id" required>
                    <?php foreach ($plantillas as $plantilla): ?>
                        <option
                            value="<?php echo (int)$plantilla['id_plantilla']; ?>"
                            data-plantilla="<?php echo escaparEdicion($plantilla['nombre']); ?>"
                            <?php echo $plantillaSeleccionada === (int)$plantilla['id_plantilla'] ? 'selected' : ''; ?>
                        >
                            <?php echo escaparEdicion(ucfirst($plantilla['nombre'])); ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <label for="advertencia">Advertencia informativa</label>
                <textarea id="advertencia" name="advertencia" maxlength="5000" rows="3"><?php echo escaparEdicion($advertencia); ?></textarea>

                <fieldset>
                    <legend>Imagen de portada</legend>
                    <?php if (!empty($imagenActual)): ?>
                        <img
                            src="<?php echo escaparEdicion(rutaImagenEdicion($imagenActual)); ?>"
                            alt="Portada actual"
                            style="max-width:100%;height:auto"
                        >
                    <?php endif; ?>
                    <label for="tipo_imagen">Acción</label>
                    <select id="tipo_imagen" name="tipo_imagen">
                        <option value="conservar">Conservar imagen actual</option>
                        <option value="ninguna">Quitar imagen</option>
                        <option value="enlace">Cambiar por enlace</option>
                        <option value="local">Subir archivo</option>
                    </select>
                    <label for="imagen_url">URL HTTP o HTTPS</label>
                    <input id="imagen_url" type="url" name="imagen_url" maxlength="255" value="<?php echo escaparEdicion($imagenURL); ?>">
                    <label for="imagen_archivo">Archivo</label>
                    <input id="imagen_archivo" type="file" name="imagen_archivo" accept="image/jpeg,image/png,image/webp,image/gif">
                    <small>JPG, PNG, WEBP o GIF; máximo 5 MB.</small>
                </fieldset>
            </section>

            <section class="seccion-admin">
                <h2>Bloques del artículo</h2>
                <p>Reordena los bloques con los botones. El orden se conserva al guardar.</p>

                <div id="bloques-editor" class="bloques-editor">
                    <?php foreach ($bloquesFormulario as $indice => $bloque): ?>
                        <?php $tipoBloque = $bloque['tipo']; ?>
                        <fieldset class="bloque-editor">
                            <legend>Bloque</legend>
                            <label>Tipo
                                <select name="bloques[<?php echo (int)$indice; ?>][tipo]" class="tipo-bloque">
                                    <?php foreach (['titulo', 'parrafo', 'lista', 'cita', 'enlace', 'imagen', 'pdf', 'video', 'modelo_3d'] as $tipo): ?>
                                        <option value="<?php echo escaparEdicion($tipo); ?>" <?php echo $tipoBloque === $tipo ? 'selected' : ''; ?>>
                                            <?php echo escaparEdicion(ucfirst(str_replace('_', ' ', $tipo))); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </select>
                            </label>
                            <label class="campo-contenido">Texto o URL
                                <textarea name="bloques[<?php echo (int)$indice; ?>][contenido]" rows="4" maxlength="10000"><?php echo escaparEdicion($bloque['contenido']); ?></textarea>
                            </label>
                            <label class="campo-recurso" hidden>Recurso aprobado
                                <select name="bloques[<?php echo (int)$indice; ?>][recurso_id]">
                                    <option value="">Selecciona un recurso</option>
                                    <?php foreach ($recursos as $recurso): ?>
                                        <option
                                            value="<?php echo (int)$recurso['id_recurso']; ?>"
                                            data-tipo="<?php echo escaparEdicion($recurso['tipo']); ?>"
                                            <?php echo $bloque['recurso_id'] === (int)$recurso['id_recurso'] ? 'selected' : ''; ?>
                                        >
                                            <?php echo escaparEdicion($recurso['titulo'] ?: $recurso['url']); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </select>
                            </label>
                            <div class="bloque-controles">
                                <button type="button" class="boton boton-secundario mover-arriba">Subir</button>
                                <button type="button" class="boton boton-secundario mover-abajo">Bajar</button>
                                <button type="button" class="boton boton-secundario quitar-bloque">Quitar</button>
                            </div>
                        </fieldset>
                    <?php endforeach; ?>
                </div>

                <div class="enlaces">
                    <button type="button" class="boton boton-secundario" id="agregar-bloque">
                        Agregar bloque
                    </button>
                </div>
            </section>

            <section class="seccion-admin">
                <h2>Vista previa</h2>
                <div id="vista-previa" class="vista-previa" aria-live="polite"></div>
            </section>

            <?php if ($fuentesActuales !== []): ?>
                <section class="seccion-admin">
                    <h2>Fuentes que se conservarán</h2>
                    <ul>
                        <?php foreach ($fuentesActuales as $fuente): ?>
                            <li>
                                <?php echo escaparEdicion($fuente['titulo']); ?>
                                <?php if (!empty($fuente['autor'])): ?>
                                    — <?php echo escaparEdicion($fuente['autor']); ?>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ul>
                </section>
            <?php endif; ?>

            <button class="boton" type="submit">Guardar nueva versión</button>
        </form>
    </main>

    <template id="plantilla-bloque">
        <fieldset class="bloque-editor">
            <legend>Bloque</legend>
            <label>Tipo
                <select name="bloques[__I__][tipo]" class="tipo-bloque">
                    <option value="titulo">Título</option>
                    <option value="parrafo">Párrafo</option>
                    <option value="lista">Lista</option>
                    <option value="cita">Cita</option>
                    <option value="enlace">Enlace</option>
                    <option value="imagen">Imagen</option>
                    <option value="pdf">PDF</option>
                </select>
            </label>
            <label class="campo-contenido">Texto o URL
                <textarea name="bloques[__I__][contenido]" rows="4" maxlength="10000"></textarea>
            </label>
            <label class="campo-recurso" hidden>Recurso aprobado
                <select name="bloques[__I__][recurso_id]">
                    <option value="">Selecciona un recurso</option>
                    <?php foreach ($recursos as $recurso): ?>
                        <option value="<?php echo (int)$recurso['id_recurso']; ?>" data-tipo="<?php echo escaparEdicion($recurso['tipo']); ?>">
                            <?php echo escaparEdicion($recurso['titulo'] ?: $recurso['url']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </label>
            <div class="bloque-controles">
                <button type="button" class="boton boton-secundario mover-arriba">Subir</button>
                <button type="button" class="boton boton-secundario mover-abajo">Bajar</button>
                <button type="button" class="boton boton-secundario quitar-bloque">Quitar</button>
            </div>
        </fieldset>
    </template>

    <script>
    (() => {
        const lista = document.getElementById('bloques-editor');
        const plantilla = document.getElementById('plantilla-bloque');
        const selectorPlantilla = document.getElementById('plantilla_id');
        const vista = document.getElementById('vista-previa');
        let siguiente = lista.querySelectorAll('.bloque-editor').length;

        function actualizarBloque(bloque) {
            const tipo = bloque.querySelector('.tipo-bloque').value;
            const recurso = ['imagen', 'pdf', 'video', 'modelo_3d'].includes(tipo);
            bloque.querySelector('.campo-recurso').hidden = !recurso;
            bloque.querySelector('.campo-contenido').hidden = recurso;
            bloque.querySelectorAll('.campo-recurso option[data-tipo]').forEach((opcion) => {
                opcion.hidden = recurso && opcion.dataset.tipo !== tipo;
            });
        }

        function actualizarVista() {
            vista.replaceChildren();
            const nombre = selectorPlantilla.selectedOptions[0]?.dataset.plantilla || 'clasica';
            vista.className = 'vista-previa plantilla-' + nombre;

            lista.querySelectorAll('.bloque-editor').forEach((bloque) => {
                const tipo = bloque.querySelector('.tipo-bloque').value;
                const esRecurso = ['imagen', 'pdf', 'video', 'modelo_3d'].includes(tipo);
                const contenido = esRecurso
                    ? bloque.querySelector('.campo-recurso select').selectedOptions[0]?.textContent || 'Selecciona recurso'
                    : bloque.querySelector('textarea').value;
                const elemento = document.createElement(tipo === 'titulo' ? 'h3' : tipo === 'cita' ? 'blockquote' : 'p');
                elemento.textContent = contenido;
                vista.appendChild(elemento);
            });
        }

        lista.addEventListener('change', (evento) => {
            const bloque = evento.target.closest('.bloque-editor');
            if (bloque) actualizarBloque(bloque);
            actualizarVista();
        });
        lista.addEventListener('input', actualizarVista);
        lista.addEventListener('click', (evento) => {
            const bloque = evento.target.closest('.bloque-editor');
            if (!bloque) return;

            if (evento.target.matches('.quitar-bloque')) {
                bloque.remove();
            } else if (evento.target.matches('.mover-arriba') && bloque.previousElementSibling) {
                lista.insertBefore(bloque, bloque.previousElementSibling);
            } else if (evento.target.matches('.mover-abajo') && bloque.nextElementSibling) {
                lista.insertBefore(bloque.nextElementSibling, bloque);
            }

            actualizarVista();
        });

        document.getElementById('agregar-bloque').addEventListener('click', () => {
            lista.insertAdjacentHTML(
                'beforeend',
                plantilla.innerHTML.replaceAll('__I__', String(siguiente++))
            );
            actualizarBloque(lista.lastElementChild);
            actualizarVista();
        });

        selectorPlantilla.addEventListener('change', actualizarVista);
        lista.querySelectorAll('.bloque-editor').forEach(actualizarBloque);
        actualizarVista();
    })();
    </script>

    <script
        src="<?php echo escaparEdicion(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>