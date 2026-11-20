<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';
require_once __DIR__ . '/componentes/cabecera.php';

requiereUsuarioActual($mysqli);

$idUsuario = (int)$_SESSION['id_usr'];
$csrf = generarCSRF();

function escaparCorreccionEstablecimiento($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postCorreccionEstablecimiento(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';
    return is_string($valor) ? trim($valor) : '';
}

function rutaPrivadaCorreccionEstablecimiento(): string
{
    $raizWebRecibida = $_SERVER['DOCUMENT_ROOT'] ?? '';
    $raizWeb = is_string($raizWebRecibida)
        ? realpath($raizWebRecibida)
        : false;

    if ($raizWeb === false) {
        throw new RuntimeException('No se pudo determinar la raíz web.');
    }

    $directorio = dirname($raizWeb)
        . DIRECTORY_SEPARATOR
        . 'vitasacra_privado'
        . DIRECTORY_SEPARATOR
        . 'establecimientos';

    if (
        !is_dir($directorio)
        && !mkdir($directorio, 0700, true)
        && !is_dir($directorio)
    ) {
        throw new RuntimeException(
            'No se pudo preparar el almacenamiento privado.'
        );
    }

    $directorioReal = realpath($directorio);
    $raizNormalizada = rtrim(
        strtolower(str_replace('\\', '/', $raizWeb)),
        '/'
    );
    $directorioNormalizado = $directorioReal === false
        ? ''
        : strtolower(str_replace('\\', '/', $directorioReal));

    if (
        $directorioReal === false
        || strpos($directorioNormalizado, $raizNormalizada . '/') === 0
    ) {
        throw new RuntimeException(
            'El almacenamiento debe estar fuera de la raíz web.'
        );
    }

    return $directorioReal;
}

function recopilarDocumentosCorreccion($entrada): array
{
    if (
        !is_array($entrada)
        || !isset(
            $entrada['name'],
            $entrada['tmp_name'],
            $entrada['error'],
            $entrada['size']
        )
        || !is_array($entrada['name'])
        || !is_array($entrada['tmp_name'])
        || !is_array($entrada['error'])
        || !is_array($entrada['size'])
    ) {
        throw new DomainException('La carga de documentos no es válida.');
    }

    $formatos = [
        'application/pdf' => 'pdf',
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp'
    ];
    $documentos = [];

    foreach ($entrada['name'] as $indice => $nombreRecibido) {
        $error = (int)($entrada['error'][$indice] ?? UPLOAD_ERR_NO_FILE);

        if ($error === UPLOAD_ERR_NO_FILE) {
            continue;
        }

        if ($error !== UPLOAD_ERR_OK) {
            throw new DomainException(
                'Uno de los documentos no se recibió correctamente.'
            );
        }

        $temporal = $entrada['tmp_name'][$indice] ?? '';
        $tamano = (int)($entrada['size'][$indice] ?? 0);

        if (
            !is_string($temporal)
            || !is_uploaded_file($temporal)
            || $tamano <= 0
            || $tamano > 10 * 1024 * 1024
        ) {
            throw new DomainException(
                'Cada documento debe ser válido y no superar los 10 MB.'
            );
        }

        if (!class_exists('finfo')) {
            throw new RuntimeException(
                'La extensión fileinfo de PHP es necesaria para validar documentos.'
            );
        }

        $informacion = new finfo(FILEINFO_MIME_TYPE);
        $mime = $informacion->file($temporal);

        if (!is_string($mime) || !isset($formatos[$mime])) {
            throw new DomainException(
                'Solo se aceptan documentos PDF, JPG, PNG o WEBP.'
            );
        }

        $nombreOriginal = is_string($nombreRecibido)
            ? basename($nombreRecibido)
            : 'documento';

        $nombreOriginal = preg_replace(
            '/[\x00-\x1F\x7F]/u',
            '',
            $nombreOriginal
        );

        $documentos[] = [
            'temporal' => $temporal,
            'nombre_original' => mb_substr(
                (string)$nombreOriginal,
                0,
                255,
                'UTF-8'
            ),
            'tamano' => $tamano,
            'mime' => $mime,
            'extension' => $formatos[$mime],
            'sha256' => hash_file('sha256', $temporal)
        ];
    }

    if ($documentos === []) {
        throw new DomainException(
            'Adjunta al menos un documento actualizado.'
        );
    }

    if (count($documentos) > 5) {
        throw new DomainException(
            'Puedes adjuntar hasta cinco documentos por reenvío.'
        );
    }

    return $documentos;
}

$idRecibido = $_GET['id'] ?? null;
$idEstablecimiento = is_scalar($idRecibido)
    ? filter_var(
        $idRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

if ($idEstablecimiento === false) {
    http_response_code(404);
    exit('No se encontró el expediente solicitado.');
}

$idEstablecimiento = (int)$idEstablecimiento;

$consultaExpediente = $mysqli->prepare(
    "SELECT
        id_establecimiento,
        nombre,
        tipo,
        descripcion,
        direccion,
        telefono,
        sitio_web,
        estatus,
        observacion_revision
     FROM establecimientos
     WHERE id_establecimiento = ?
       AND solicitante_id = ?
       AND estatus = 'correccion'
     LIMIT 1"
);
$consultaExpediente->bind_param(
    'ii',
    $idEstablecimiento,
    $idUsuario
);
$consultaExpediente->execute();
$expediente = $consultaExpediente
    ->get_result()
    ->fetch_assoc();
$consultaExpediente->close();

if (!$expediente) {
    http_response_code(404);
    exit('El expediente no existe, no te pertenece o no requiere correcciones.');
}

$tiposEstablecimiento = [
    'clinica' => 'Clínica',
    'farmacia' => 'Farmacia',
    'hospital' => 'Hospital',
    'laboratorio' => 'Laboratorio',
    'consultorio' => 'Consultorio',
    'otro' => 'Otro establecimiento relacionado con salud'
];

$tiposDocumento = [
    'identificacion' => 'Identificación del representante',
    'autorizacion' => 'Autorización o permiso aplicable',
    'domicilio' => 'Comprobante de domicilio comercial',
    'otro' => 'Otro documento de respaldo'
];

$mensaje = '';
$tipoMensaje = '';

$nombre = (string)$expediente['nombre'];
$tipoEstablecimiento = (string)$expediente['tipo'];
$descripcion = (string)($expediente['descripcion'] ?? '');
$direccion = (string)$expediente['direccion'];
$telefono = (string)($expediente['telefono'] ?? '');
$sitioWeb = (string)($expediente['sitio_web'] ?? '');
$tipoDocumento = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $nombre = postCorreccionEstablecimiento('nombre');
    $tipoEstablecimiento = postCorreccionEstablecimiento('tipo');
    $descripcion = postCorreccionEstablecimiento('descripcion');
    $direccion = postCorreccionEstablecimiento('direccion');
    $telefono = postCorreccionEstablecimiento('telefono');
    $sitioWeb = postCorreccionEstablecimiento('sitio_web');
    $tipoDocumento = postCorreccionEstablecimiento('tipo_documento');
    $archivosMovidos = [];

    try {
        if (!verificarCSRF(postCorreccionEstablecimiento('csrf_token'))) {
            throw new DomainException(
                'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
            );
        }

        if ($nombre === '' || mb_strlen($nombre, 'UTF-8') > 180) {
            throw new DomainException(
                'El nombre comercial es obligatorio y no puede superar 180 caracteres.'
            );
        }

        if (!isset($tiposEstablecimiento[$tipoEstablecimiento])) {
            throw new DomainException(
                'Selecciona un tipo de establecimiento válido.'
            );
        }

        if (mb_strlen($descripcion, 'UTF-8') > 5000) {
            throw new DomainException(
                'La descripción no puede superar 5,000 caracteres.'
            );
        }

        if ($direccion === '' || mb_strlen($direccion, 'UTF-8') > 300) {
            throw new DomainException(
                'La dirección general es obligatoria y no puede superar 300 caracteres.'
            );
        }

        if (mb_strlen($telefono, 'UTF-8') > 30) {
            throw new DomainException('El teléfono no puede superar 30 caracteres.');
        }

        if (
            $telefono !== ''
            && !preg_match('/^[0-9+()\-\s.]+$/', $telefono)
        ) {
            throw new DomainException('El teléfono contiene caracteres no válidos.');
        }

        if (mb_strlen($sitioWeb, 'UTF-8') > 500) {
            throw new DomainException('El sitio web no puede superar 500 caracteres.');
        }

        if (
            $sitioWeb !== ''
            && (
                !filter_var($sitioWeb, FILTER_VALIDATE_URL)
                || !in_array(
                    strtolower((string)parse_url($sitioWeb, PHP_URL_SCHEME)),
                    ['http', 'https'],
                    true
                )
            )
        ) {
            throw new DomainException(
                'El sitio web debe ser una URL HTTP o HTTPS válida.'
            );
        }

        if (!isset($tiposDocumento[$tipoDocumento])) {
            throw new DomainException('Selecciona el tipo de documento adjunto.');
        }

        $documentos = recopilarDocumentosCorreccion(
            $_FILES['documentos'] ?? null
        );
        $directorioPrivado = rutaPrivadaCorreccionEstablecimiento();

        foreach ($documentos as &$documento) {
            $clave = bin2hex(random_bytes(16))
                . '.'
                . $documento['extension'];
            $destino = $directorioPrivado
                . DIRECTORY_SEPARATOR
                . $clave;

            if (!move_uploaded_file($documento['temporal'], $destino)) {
                throw new RuntimeException(
                    'No se pudo guardar uno de los documentos privados.'
                );
            }

            $documento['clave'] = $clave;
            $documento['ruta'] = $destino;
            $archivosMovidos[] = $destino;
        }
        unset($documento);

        $mysqli->begin_transaction();

        try {
            $bloqueo = $mysqli->prepare(
                "SELECT estatus
                 FROM establecimientos
                 WHERE id_establecimiento = ?
                   AND solicitante_id = ?
                 LIMIT 1
                 FOR UPDATE"
            );
            $bloqueo->bind_param(
                'ii',
                $idEstablecimiento,
                $idUsuario
            );
            $bloqueo->execute();
            $registro = $bloqueo->get_result()->fetch_assoc();
            $bloqueo->close();

            if (!$registro || $registro['estatus'] !== 'correccion') {
                throw new DomainException(
                    'El expediente ya no está disponible para correcciones.'
                );
            }

            $descripcionDB = $descripcion !== '' ? $descripcion : null;
            $telefonoDB = $telefono !== '' ? $telefono : null;
            $sitioWebDB = $sitioWeb !== '' ? $sitioWeb : null;

            $actualizar = $mysqli->prepare(
                "UPDATE establecimientos
                 SET nombre = ?,
                     tipo = ?,
                     descripcion = ?,
                     direccion = ?,
                     telefono = ?,
                     sitio_web = ?,
                     estatus = 'pendiente',
                     fecha_solicitud = CURRENT_TIMESTAMP,
                     actualizado_en = CURRENT_TIMESTAMP,
                     administrador_id = NULL,
                     fecha_revision = NULL,
                     observacion_revision = NULL
                 WHERE id_establecimiento = ?
                   AND solicitante_id = ?
                   AND estatus = 'correccion'"
            );
            $actualizar->bind_param(
                'ssssssii',
                $nombre,
                $tipoEstablecimiento,
                $descripcionDB,
                $direccion,
                $telefonoDB,
                $sitioWebDB,
                $idEstablecimiento,
                $idUsuario
            );
            $actualizar->execute();

            if ($actualizar->affected_rows !== 1) {
                $actualizar->close();
                throw new DomainException(
                    'El expediente cambió antes de guardar las correcciones.'
                );
            }
            $actualizar->close();

            $insertarDocumento = $mysqli->prepare(
                "INSERT INTO documentos_establecimiento
                    (
                        establecimiento_id,
                        subido_por,
                        tipo_documento,
                        nombre_original,
                        clave_almacenamiento,
                        mime,
                        tamano_bytes,
                        sha256
                    )
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            );

            foreach ($documentos as $documento) {
                $nombreOriginal = $documento['nombre_original'];
                $clave = $documento['clave'];
                $mime = $documento['mime'];
                $tamano = (int)$documento['tamano'];
                $sha256 = $documento['sha256'];

                $insertarDocumento->bind_param(
                    'iissssis',
                    $idEstablecimiento,
                    $idUsuario,
                    $tipoDocumento,
                    $nombreOriginal,
                    $clave,
                    $mime,
                    $tamano,
                    $sha256
                );
                $insertarDocumento->execute();
            }
            $insertarDocumento->close();

            $accion = 'datos_actualizados';
            $estadoAnterior = 'correccion';
            $estadoNuevo = 'pendiente';
            $observacion = null;

            $insertarHistorial = $mysqli->prepare(
                "INSERT INTO historial_establecimientos
                    (
                        establecimiento_id,
                        actor_id,
                        accion,
                        estado_anterior,
                        estado_nuevo,
                        observacion
                    )
                 VALUES (?, ?, ?, ?, ?, ?)"
            );
            $insertarHistorial->bind_param(
                'iissss',
                $idEstablecimiento,
                $idUsuario,
                $accion,
                $estadoAnterior,
                $estadoNuevo,
                $observacion
            );
            $insertarHistorial->execute();
            $insertarHistorial->close();

            $mysqli->commit();
        } catch (Throwable $error) {
            $mysqli->rollback();
            throw $error;
        }

        $_SESSION['flash_solicitud_establecimiento'] = [
            'tipo' => 'exito',
            'mensaje' => 'Las correcciones se enviaron nuevamente para revisión.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/solicitar_establecimiento.php',
            true,
            303
        );
        exit;
    } catch (DomainException $error) {
        foreach ($archivosMovidos as $ruta) {
            if (is_file($ruta)) {
                unlink($ruta);
            }
        }
        $mensaje = $error->getMessage();
        $tipoMensaje = 'mensaje-error';
    } catch (Throwable $error) {
        foreach ($archivosMovidos as $ruta) {
            if (is_file($ruta)) {
                unlink($ruta);
            }
        }
        error_log(
            'Vita Sacra: error al reenviar expediente: '
            . $error->getMessage()
        );
        $mensaje = 'No se pudieron guardar las correcciones. Inténtalo nuevamente.';
        $tipoMensaje = 'mensaje-error';
    }
}

$consultaDocumentos = $mysqli->prepare(
    "SELECT tipo_documento, nombre_original, estatus
     FROM documentos_establecimiento
     WHERE establecimiento_id = ?
     ORDER BY fecha, id_documento"
);
$consultaDocumentos->bind_param('i', $idEstablecimiento);
$consultaDocumentos->execute();
$documentosActuales = $consultaDocumentos
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaDocumentos->close();

$nombreCabecera = $_SESSION['nom_usr'] ?? 'Mi cuenta';
$nombreCabecera = is_string($nombreCabecera)
    ? $nombreCabecera
    : 'Mi cuenta';
$rolesActuales = obtenerRolesActuales($mysqli);
$rolCabecera = in_array('administrador', $rolesActuales, true)
    ? 'administrador'
    : (
        in_array('autor', $rolesActuales, true)
            ? 'autor'
            : 'visor'
    );
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Corregir solicitud de establecimiento | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparCorreccionEstablecimiento(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreCabecera,
        $rolCabecera,
        '',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Corregir solicitud</h1>
                <p><?php echo escaparCorreccionEstablecimiento($expediente['nombre']); ?></p>
            </div>
        </section>

        <?php if ($mensaje !== ''): ?>
            <div class="<?php echo escaparCorreccionEstablecimiento($tipoMensaje); ?>" role="status">
                <?php echo escaparCorreccionEstablecimiento($mensaje); ?>
            </div>
        <?php endif; ?>

        <?php if (!empty($expediente['observacion_revision'])): ?>
            <section class="tarjeta">
                <h2>Observación administrativa</h2>
                <p><?php echo nl2br(escaparCorreccionEstablecimiento($expediente['observacion_revision'])); ?></p>
            </section>
        <?php endif; ?>

        <section class="tarjeta">
            <h2>Documentos ya enviados</h2>
            <ul>
                <?php foreach ($documentosActuales as $documento): ?>
                    <li>
                        <?php echo escaparCorreccionEstablecimiento($documento['tipo_documento']); ?>
                        — <?php echo escaparCorreccionEstablecimiento($documento['nombre_original']); ?>
                        (<?php echo escaparCorreccionEstablecimiento($documento['estatus']); ?>)
                    </li>
                <?php endforeach; ?>
            </ul>
        </section>

        <section class="tarjeta">
            <form method="POST" enctype="multipart/form-data">
                <input type="hidden" name="csrf_token" value="<?php echo escaparCorreccionEstablecimiento($csrf); ?>">

                <label for="nombre">Nombre comercial</label>
                <input id="nombre" name="nombre" maxlength="180" required value="<?php echo escaparCorreccionEstablecimiento($nombre); ?>">

                <label for="tipo">Tipo de establecimiento</label>
                <select id="tipo" name="tipo" required>
                    <?php foreach ($tiposEstablecimiento as $valor => $etiqueta): ?>
                        <option value="<?php echo escaparCorreccionEstablecimiento($valor); ?>" <?php echo $tipoEstablecimiento === $valor ? 'selected' : ''; ?>>
                            <?php echo escaparCorreccionEstablecimiento($etiqueta); ?>
                        </option>
                    <?php endforeach; ?>
                </select>

                <label for="descripcion">Descripción</label>
                <textarea id="descripcion" name="descripcion" maxlength="5000" rows="5"><?php echo escaparCorreccionEstablecimiento($descripcion); ?></textarea>

                <label for="direccion">Ubicación o dirección general</label>
                <input id="direccion" name="direccion" maxlength="300" required value="<?php echo escaparCorreccionEstablecimiento($direccion); ?>">

                <label for="telefono">Teléfono (opcional)</label>
                <input id="telefono" name="telefono" maxlength="30" value="<?php echo escaparCorreccionEstablecimiento($telefono); ?>">

                <label for="sitio_web">Sitio web (opcional)</label>
                <input id="sitio_web" type="url" name="sitio_web" maxlength="500" value="<?php echo escaparCorreccionEstablecimiento($sitioWeb); ?>">

                <fieldset>
                    <legend>Documentación actualizada</legend>
                    <label for="tipo_documento">Tipo de documento</label>
                    <select id="tipo_documento" name="tipo_documento" required>
                        <option value="">Selecciona un tipo</option>
                        <?php foreach ($tiposDocumento as $valor => $etiqueta): ?>
                            <option value="<?php echo escaparCorreccionEstablecimiento($valor); ?>" <?php echo $tipoDocumento === $valor ? 'selected' : ''; ?>>
                                <?php echo escaparCorreccionEstablecimiento($etiqueta); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>

                    <label for="documentos">Archivos actualizados</label>
                    <input
                        id="documentos"
                        type="file"
                        name="documentos[]"
                        accept=".pdf,.jpg,.jpeg,.png,.webp,application/pdf,image/jpeg,image/png,image/webp"
                        multiple
                        required
                    >
                    <small>Al menos un PDF, JPG, PNG o WEBP; máximo cinco archivos de 10 MB cada uno.</small>
                </fieldset>

                <button class="boton" type="submit">Reenviar a revisión</button>
            </form>
        </section>
    </main>

    <script
        src="<?php echo escaparCorreccionEstablecimiento(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>