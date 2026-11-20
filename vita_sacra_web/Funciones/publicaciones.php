<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';
require_once __DIR__ . '/componentes/cabecera.php';

date_default_timezone_set('America/Mexico_City');
requiereRol($mysqli, 'autor', 'administrador');

$rolesActuales = obtenerRolesActuales($mysqli);
$esAdministrador = in_array('administrador', $rolesActuales, true);
$idUsuario = (int)$_SESSION['id_usr'];
$csrf = generarCSRF();

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

function bloquesNuevaPublicacion($entrada): array
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
        'pdf'
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

function guardarImagenNuevaPublicacion(
    string $tipo,
    string $url,
    $archivo,
    ?string &$rutaArchivoGuardado
): ?string {
    $rutaArchivoGuardado = null;

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
       AND tipo IN ('imagen', 'pdf')
     ORDER BY tipo, titulo"
)->fetch_all(MYSQLI_ASSOC);

$recursosPorId = [];
foreach ($recursos as $recurso) {
    $recursosPorId[(int)$recurso['id_recurso']] = $recurso;
}

$mensaje = '';
$tipoMensaje = '';
$titulo = '';
$descripcion = '';
$advertencia = '';
$categoriaSeleccionada = '';
$tipoPublicacion = 'articulo';
$plantillaSeleccionada = 1;
$tipoImagen = 'ninguna';
$imagenURL = '';
$bloquesFormulario = [[
    'tipo' => 'parrafo',
    'contenido' => '',
    'recurso_id' => null,
    'tipo_valido' => true
]];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $titulo = trim(postNuevaPublicacion('titulo'));
    $descripcion = trim(postNuevaPublicacion('descripcion'));
    $advertencia = trim(postNuevaPublicacion('advertencia'));
    $categoriaRecibida = filter_var(
        postNuevaPublicacion('categoria'),
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );
    $plantillaRecibida = filter_var(
        postNuevaPublicacion('plantilla_id'),
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );
    $tipoPublicacion = postNuevaPublicacion('tipo');
    $tipoImagen = postNuevaPublicacion('tipo_imagen');
    $imagenURL = trim(postNuevaPublicacion('imagen_url'));
    $bloquesFormulario = bloquesNuevaPublicacion($_POST['bloques'] ?? []);

    $tiposPublicacion = [
        'articulo',
        'ficha_medicamento',
        'ficha_producto'
    ];
    $esFichaSalud = in_array(
        $tipoPublicacion,
        ['ficha_medicamento', 'ficha_producto'],
        true
    );

    try {
        if (!verificarCSRF(postNuevaPublicacion('csrf_token'))) {
            throw new DomainException(
                'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
            );
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

        if (!in_array($tipoPublicacion, $tiposPublicacion, true)) {
            throw new DomainException('Selecciona un tipo de publicación válido.');
        }

        if ($categoriaRecibida === false) {
            throw new DomainException('Selecciona una categoría válida.');
        }

        if ($plantillaRecibida === false) {
            throw new DomainException('Selecciona una plantilla válida.');
        }

        if ($esFichaSalud && trim($advertencia) === '') {
            throw new DomainException(
                'Las fichas educativas deben incluir una advertencia informativa.'
            );
        }

        if (mb_strlen($advertencia, 'UTF-8') > 5000) {
            throw new DomainException(
                'La advertencia no puede superar 5,000 caracteres.'
            );
        }

        $plantillaValida = false;
        foreach ($plantillas as $plantilla) {
            if ((int)$plantilla['id_plantilla'] === $plantillaRecibida) {
                $plantillaValida = true;
                break;
            }
        }

        if (!$plantillaValida) {
            throw new DomainException('La plantilla seleccionada no está disponible.');
        }

        $categoriaSeleccionada = (int)$categoriaRecibida;
        $plantillaSeleccionada = (int)$plantillaRecibida;

        $validarCategoria = $mysqli->prepare(
            "SELECT id_categoria
             FROM categorias
             WHERE id_categoria = ?
               AND activa = 1
             LIMIT 1"
        );
        $validarCategoria->bind_param('i', $categoriaSeleccionada);
        $validarCategoria->execute();
        $categoriaValida = $validarCategoria
            ->get_result()
            ->fetch_assoc();
        $validarCategoria->close();

        if (!$categoriaValida) {
            throw new DomainException('La categoría no existe o está inactiva.');
        }

        if ($bloquesFormulario === [] || count($bloquesFormulario) > 50) {
            throw new DomainException(
                'Agrega entre 1 y 50 bloques de contenido.'
            );
        }

        $hayTexto = false;
        foreach ($bloquesFormulario as $bloque) {
            if (!$bloque['tipo_valido']) {
                throw new DomainException('Uno de los tipos de bloque no es válido.');
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
                $tipoRecurso = $tipo === 'imagen' ? 'imagen' : 'pdf';
                $recurso = $idRecurso !== null
                    ? ($recursosPorId[$idRecurso] ?? null)
                    : null;

                if (!$recurso || $recurso['tipo'] !== $tipoRecurso) {
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

        $archivoGuardado = null;
        $imagen = guardarImagenNuevaPublicacion(
            $tipoImagen,
            $imagenURL,
            $_FILES['imagen_archivo'] ?? null,
            $archivoGuardado
        );

        $slugBase = iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $titulo);
        $slugBase = is_string($slugBase) ? $slugBase : '';
        $slugBase = strtolower(trim(
            preg_replace('/[^a-zA-Z0-9]+/', '-', $slugBase),
            '-'
        ));
        $slug = substr($slugBase !== '' ? $slugBase : 'publicacion', 0, 190)
            . '-'
            . bin2hex(random_bytes(4));

        $mysqli->begin_transaction();

        try {
            $estatus = 'borrador';
            $estatusVersion = 'borrador';
            $advertenciaDB = $advertencia !== '' ? $advertencia : null;

            $insertarBlog = $mysqli->prepare(
                "INSERT INTO blog
                    (
                        usr_id, categoria_id, plantilla_id, titulo,
                        `desc`, img, slug, tipo, estatus, fecha_publicacion
                    )
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)"
            );
            $insertarBlog->bind_param(
                'iiissssss',
                $idUsuario,
                $categoriaSeleccionada,
                $plantillaSeleccionada,
                $titulo,
                $descripcion,
                $imagen,
                $slug,
                $tipoPublicacion,
                $estatus
            );
            $insertarBlog->execute();
            $idBlog = (int)$mysqli->insert_id;
            $insertarBlog->close();

            $numeroVersion = 1;
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
            $idVersion = (int)$mysqli->insert_id;
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
                    ['imagen', 'pdf'],
                    true
                ) ? null : $bloque['contenido'];
                $recursoId = $bloque['recurso_id'];

                $insertarBloque->bind_param(
                    'iissi',
                    $idVersion,
                    $orden,
                    $tipo,
                    $contenido,
                    $recursoId
                );
                $insertarBloque->execute();
            }

            $insertarBloque->close();
            $mysqli->commit();

            header(
                'Location: ' . RUTA_WEB . '/Funciones/publicaciones.php?mensaje=guardado',
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
            'Vita Sacra: error al crear borrador: '
            . $error->getMessage()
        );
        $mensaje = 'No fue posible guardar el borrador. Inténtalo nuevamente.';
        $tipoMensaje = 'mensaje-error';
    } catch (RuntimeException $error) {
        $mensaje = $error->getMessage();
        $tipoMensaje = 'mensaje-error';
    }
}

if (($_GET['mensaje'] ?? '') === 'guardado') {
    $mensaje = 'El borrador se guardó correctamente.';
    $tipoMensaje = 'mensaje-exito';
}

if (!in_array($tipoImagen, ['ninguna', 'enlace', 'local'], true)) {
    $tipoImagen = 'ninguna';
}

if ($bloquesFormulario === []) {
    $bloquesFormulario = [[
        'tipo' => 'parrafo',
        'contenido' => '',
        'recurso_id' => null,
        'tipo_valido' => true
    ]];
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
    <title>Crear borrador | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparNuevaPublicacion(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
    <style>
        .bloques-editor { display: grid; gap: 16px; }
        .bloque-editor { padding: 18px; border: 1px solid var(--bordes); border-radius: var(--radio); background: var(--superficie); }
        .bloque-controles { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
        .vista-previa { padding: 22px; border: 1px solid var(--bordes); border-radius: var(--radio); background: var(--superficie); }
        .vista-previa.plantilla-divulgativa { border-top: 5px solid var(--azul); }
        .vista-previa.plantilla-visual { background: var(--azul-claro); }
        .campo-recurso[hidden] { display: none; }
    </style>
</head>
<body>
    <?php
    vitaSacraRenderCabecera($nombreNav, $rolNav, 'crear', $csrf);
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Crear borrador</h1>
                <p>Organiza el artículo por bloques. Guardar no lo publica.</p>
            </div>
        </section>

        <nav class="enlaces" aria-label="Navegación">
            <a class="boton boton-secundario" href="<?php echo escaparNuevaPublicacion($enlacePanel); ?>">
                Volver a mi panel
            </a>
            <a class="boton boton-secundario" href="<?php echo escaparNuevaPublicacion(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php">
                Mis publicaciones
            </a>
        </nav>

        <?php if ($mensaje !== ''): ?>
            <div class="<?php echo escaparNuevaPublicacion($tipoMensaje); ?>" role="status">
                <?php echo escaparNuevaPublicacion($mensaje); ?>
            </div>
        <?php endif; ?>

        <form class="seccion-admin" method="POST" enctype="multipart/form-data">
            <input type="hidden" name="csrf_token" value="<?php echo escaparNuevaPublicacion($csrf); ?>">

            <section class="tarjeta">
                <h2>Datos de la publicación</h2>

                <label for="titulo">Título</label>
                <input id="titulo" name="titulo" maxlength="200" required value="<?php echo escaparNuevaPublicacion($titulo); ?>">

                <label for="descripcion">Descripción</label>
                <textarea id="descripcion" name="descripcion" maxlength="500" rows="3" required><?php echo escaparNuevaPublicacion($descripcion); ?></textarea>

                <label for="tipo">Tipo</label>
                <select id="tipo" name="tipo" required>
                    <?php
                    $tipos = [
                        'articulo' => 'Artículo educativo',
                        'ficha_medicamento' => 'Ficha educativa de medicamento',
                        'ficha_producto' => 'Ficha educativa de producto de salud'
                    ];
                    ?>
                    <?php foreach ($tipos as $valor => $etiqueta): ?>
                        <option value="<?php echo escaparNuevaPublicacion($valor); ?>" <?php echo $tipoPublicacion === $valor ? 'selected' : ''; ?>>
                            <?php echo escaparNuevaPublicacion($etiqueta); ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <label for="categoria">Categoría</label>
                <select id="categoria" name="categoria" required>
                    <option value="">Selecciona una categoría</option>
                    <?php foreach ($categorias as $categoria): ?>
                        <option value="<?php echo (int)$categoria['id_categoria']; ?>" <?php echo (string)$categoriaSeleccionada === (string)$categoria['id_categoria'] ? 'selected' : ''; ?>>
                            <?php echo escaparNuevaPublicacion($categoria['nombre']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <label for="plantilla_id">Plantilla</label>
                <select id="plantilla_id" name="plantilla_id" required>
                    <?php foreach ($plantillas as $plantilla): ?>
                        <option
                            value="<?php echo (int)$plantilla['id_plantilla']; ?>"
                            data-plantilla="<?php echo escaparNuevaPublicacion($plantilla['nombre']); ?>"
                            <?php echo $plantillaSeleccionada === (int)$plantilla['id_plantilla'] ? 'selected' : ''; ?>
                        >
                            <?php echo escaparNuevaPublicacion(ucfirst($plantilla['nombre'])); ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <label for="advertencia">Advertencia informativa</label>
                <textarea id="advertencia" name="advertencia" maxlength="5000" rows="3"><?php echo escaparNuevaPublicacion($advertencia); ?></textarea>
                <small>Obligatoria para fichas educativas de medicamentos y productos de salud.</small>

                <fieldset>
                    <legend>Imagen de portada (opcional)</legend>
                    <label for="tipo_imagen">Origen</label>
                    <select id="tipo_imagen" name="tipo_imagen">
                        <option value="ninguna" <?php echo $tipoImagen === 'ninguna' ? 'selected' : ''; ?>>Sin imagen</option>
                        <option value="enlace" <?php echo $tipoImagen === 'enlace' ? 'selected' : ''; ?>>Enlace web</option>
                        <option value="local" <?php echo $tipoImagen === 'local' ? 'selected' : ''; ?>>Archivo de mi dispositivo</option>
                    </select>
                    <label for="imagen_url">URL HTTP o HTTPS</label>
                    <input id="imagen_url" type="url" name="imagen_url" maxlength="255" value="<?php echo escaparNuevaPublicacion($imagenURL); ?>">
                    <label for="imagen_archivo">Archivo</label>
                    <input id="imagen_archivo" type="file" name="imagen_archivo" accept="image/jpeg,image/png,image/webp,image/gif">
                    <small>JPG, PNG, WEBP o GIF; máximo 5 MB.</small>
                </fieldset>
            </section>

            <section class="seccion-admin">
                <h2>Bloques del artículo</h2>
                <p>El orden de la lista será el orden del artículo. No se admite HTML libre.</p>

                <div id="bloques-editor" class="bloques-editor">
                    <?php foreach ($bloquesFormulario as $indice => $bloque): ?>
                        <?php
                        $tipoBloque = $bloque['tipo'];
                        $idRecurso = $bloque['recurso_id'];
                        ?>
                        <fieldset class="bloque-editor">
                            <legend>Bloque</legend>
                            <label>Tipo
                                <select name="bloques[<?php echo (int)$indice; ?>][tipo]" class="tipo-bloque">
                                    <?php foreach (['titulo', 'parrafo', 'lista', 'cita', 'enlace', 'imagen', 'pdf'] as $tipo): ?>
                                        <option value="<?php echo $tipo; ?>" <?php echo $tipoBloque === $tipo ? 'selected' : ''; ?>>
                                            <?php echo ucfirst($tipo); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </select>
                            </label>
                            <label class="campo-contenido">Texto o URL
                                <textarea name="bloques[<?php echo (int)$indice; ?>][contenido]" rows="4" maxlength="10000"><?php echo escaparNuevaPublicacion($bloque['contenido']); ?></textarea>
                            </label>
                            <label class="campo-recurso" hidden>Recurso aprobado
                                <select name="bloques[<?php echo (int)$indice; ?>][recurso_id]">
                                    <option value="">Selecciona un recurso</option>
                                    <?php foreach ($recursos as $recurso): ?>
                                        <option
                                            value="<?php echo (int)$recurso['id_recurso']; ?>"
                                            data-tipo="<?php echo escaparNuevaPublicacion($recurso['tipo']); ?>"
                                            <?php echo $idRecurso === (int)$recurso['id_recurso'] ? 'selected' : ''; ?>
                                        >
                                            <?php echo escaparNuevaPublicacion($recurso['titulo'] ?: $recurso['url']); ?>
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
                    <button type="button" class="boton boton-secundario" id="agregar-bloque">Agregar bloque</button>
                </div>
            </section>

            <section class="seccion-admin">
                <h2>Vista previa</h2>
                <div id="vista-previa" class="vista-previa plantilla-clasica" aria-live="polite"></div>
            </section>

            <button class="boton" type="submit">Guardar borrador</button>
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
                        <option value="<?php echo (int)$recurso['id_recurso']; ?>" data-tipo="<?php echo escaparNuevaPublicacion($recurso['tipo']); ?>">
                            <?php echo escaparNuevaPublicacion($recurso['titulo'] ?: $recurso['url']); ?>
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
            const esRecurso = tipo === 'imagen' || tipo === 'pdf';
            bloque.querySelector('.campo-recurso').hidden = !esRecurso;
            bloque.querySelector('.campo-contenido').hidden = esRecurso;

            const opciones = bloque.querySelectorAll('.campo-recurso option[data-tipo]');
            opciones.forEach((opcion) => {
                opcion.hidden = esRecurso && opcion.dataset.tipo !== tipo;
            });
        }

        function actualizarVista() {
            vista.replaceChildren();
            const nombre = selectorPlantilla.selectedOptions[0]?.dataset.plantilla || 'clasica';
            vista.className = 'vista-previa plantilla-' + nombre;

            lista.querySelectorAll('.bloque-editor').forEach((bloque) => {
                const tipo = bloque.querySelector('.tipo-bloque').value;
                const campoTexto = bloque.querySelector('textarea');
                const texto = campoTexto ? campoTexto.value : '';
                const elemento = document.createElement(
                    tipo === 'titulo' ? 'h3' :
                    tipo === 'cita' ? 'blockquote' : 'p'
                );

                if (tipo === 'imagen' || tipo === 'pdf') {
                    const recurso = bloque.querySelector('.campo-recurso select');
                    const opcion = recurso.selectedOptions[0];
                    elemento.textContent = opcion && opcion.value
                        ? (tipo === 'pdf' ? 'PDF: ' : 'Imagen: ') + opcion.textContent
                        : 'Selecciona un recurso aprobado.';
                } else if (tipo === 'enlace' && texto) {
                    elemento.textContent = texto;
                } else {
                    elemento.textContent = texto;
                }

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
            const html = plantilla.innerHTML.replaceAll('__I__', String(siguiente++));
            lista.insertAdjacentHTML('beforeend', html);
            actualizarBloque(lista.lastElementChild);
            actualizarVista();
        });

        selectorPlantilla.addEventListener('change', actualizarVista);
        lista.querySelectorAll('.bloque-editor').forEach(actualizarBloque);
        actualizarVista();
    })();
    </script>

    <script
        src="<?php echo escaparNuevaPublicacion(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>