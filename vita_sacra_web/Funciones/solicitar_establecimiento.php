<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';
require_once __DIR__ . '/componentes/cabecera.php';

requiereUsuarioActual($mysqli);

$idUsuario = (int)$_SESSION['id_usr'];
$csrf = generarCSRF();

function escaparSolicitudEstablecimiento($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postSolicitudEstablecimiento(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';
    return is_string($valor) ? trim($valor) : '';
}

function rutaAlmacenPrivadoEstablecimientos(): string
{
    $documentRootRecibido = $_SERVER['DOCUMENT_ROOT'] ?? '';
    $documentRoot = is_string($documentRootRecibido)
        ? realpath($documentRootRecibido)
        : false;

    if ($documentRoot === false) {
        throw new RuntimeException(
            'No se pudo determinar la raíz web para proteger los documentos.'
        );
    }

    $directorio = dirname($documentRoot)
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
            'No se pudo preparar el almacenamiento privado de documentos.'
        );
    }

    $directorioReal = realpath($directorio);
    $raizNormalizada = rtrim(
        strtolower(str_replace('\\', '/', $documentRoot)),
        '/'
    );
    $directorioNormalizado = $directorioReal === false
        ? ''
        : strtolower(str_replace('\\', '/', $directorioReal));

    if (
        $directorioReal === false
        || strpos(
            $directorioNormalizado,
            $raizNormalizada . '/'
        ) === 0
    ) {
        throw new RuntimeException(
            'El almacenamiento de documentos debe estar fuera de la raíz web.'
        );
    }

    return $directorioReal;
}

function recopilarDocumentosSolicitud($entrada): array
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

    $permitidos = [
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
                'Uno de los documentos no se pudo recibir correctamente.'
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

        if (!is_string($mime) || !isset($permitidos[$mime])) {
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
            'extension' => $permitidos[$mime],
            'sha256' => hash_file('sha256', $temporal)
        ];
    }

    if ($documentos === []) {
        throw new DomainException(
            'Adjunta al menos un documento de respaldo.'
        );
    }

    if (count($documentos) > 5) {
        throw new DomainException(
            'Puedes adjuntar hasta cinco documentos por solicitud.'
        );
    }

    return $documentos;
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
$nombre = '';
$tipoEstablecimiento = '';
$descripcion = '';
$direccion = '';
$telefono = '';
$sitioWeb = '';
$tipoDocumento = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $nombre = postSolicitudEstablecimiento('nombre');
    $tipoEstablecimiento = postSolicitudEstablecimiento('tipo');
    $descripcion = postSolicitudEstablecimiento('descripcion');
    $direccion = postSolicitudEstablecimiento('direccion');
    $telefono = postSolicitudEstablecimiento('telefono');
    $sitioWeb = postSolicitudEstablecimiento('sitio_web');
    $tipoDocumento = postSolicitudEstablecimiento('tipo_documento');

    $archivosMovidos = [];

    try {
        if (!verificarCSRF(postSolicitudEstablecimiento('csrf_token'))) {
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
                'La ubicación o dirección general es obligatoria y no puede superar 300 caracteres.'
            );
        }

        if (mb_strlen($telefono, 'UTF-8') > 30) {
            throw new DomainException(
                'El teléfono no puede superar 30 caracteres.'
            );
        }

        if (
            $telefono !== ''
            && !preg_match('/^[0-9+()\-\s.]+$/', $telefono)
        ) {
            throw new DomainException(
                'El teléfono contiene caracteres no válidos.'
            );
        }

        if (mb_strlen($sitioWeb, 'UTF-8') > 500) {
            throw new DomainException(
                'El sitio web no puede superar 500 caracteres.'
            );
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
            throw new DomainException(
                'Selecciona el tipo de documento que adjuntas.'
            );
        }

        $documentos = recopilarDocumentosSolicitud(
            $_FILES['documentos'] ?? null
        );

        $directorioPrivado = rutaAlmacenPrivadoEstablecimientos();

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
            $consultaUsuario = $mysqli->prepare(
                "SELECT estatus
                 FROM usuario
                 WHERE id_usr = ?
                 LIMIT 1
                 FOR UPDATE"
            );
            $consultaUsuario->bind_param('i', $idUsuario);
            $consultaUsuario->execute();
            $usuarioActual = $consultaUsuario
                ->get_result()
                ->fetch_assoc();
            $consultaUsuario->close();

            if (
                !$usuarioActual
                || $usuarioActual['estatus'] !== 'activo'
            ) {
                throw new DomainException(
                    'La cuenta debe estar activa para enviar la solicitud.'
                );
            }

            $latitud = null;
            $longitud = null;
            $estatus = 'pendiente';

            $insertarEstablecimiento = $mysqli->prepare(
                "INSERT INTO establecimientos
                    (
                        solicitante_id,
                        nombre,
                        tipo,
                        descripcion,
                        direccion,
                        latitud,
                        longitud,
                        telefono,
                        sitio_web,
                        estatus,
                        fecha_solicitud
                    )
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)"
            );
            $insertarEstablecimiento->bind_param(
                'issssddsss',
                $idUsuario,
                $nombre,
                $tipoEstablecimiento,
                $descripcion,
                $direccion,
                $latitud,
                $longitud,
                $telefono,
                $sitioWeb,
                $estatus
            );
            $insertarEstablecimiento->execute();
            $idEstablecimiento = (int)$mysqli->insert_id;
            $insertarEstablecimiento->close();

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

            $accion = 'solicitud_creada';
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
                 VALUES (?, ?, ?, NULL, ?, ?)"
            );
            $insertarHistorial->bind_param(
                'iisss',
                $idEstablecimiento,
                $idUsuario,
                $accion,
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
            'mensaje' => 'La solicitud se envió para revisión. Los documentos adjuntos son privados.'
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
            'Vita Sacra: error al registrar solicitud de establecimiento: '
            . $error->getMessage()
        );
        $mensaje = 'No fue posible guardar la solicitud. Revisa los datos e inténtalo nuevamente.';
        $tipoMensaje = 'mensaje-error';
    }
}

$flash = $_SESSION['flash_solicitud_establecimiento'] ?? null;
unset($_SESSION['flash_solicitud_establecimiento']);

$consultaSolicitudes = $mysqli->prepare(
    "SELECT
        id_establecimiento,
        nombre,
        tipo,
        estatus,
        fecha_solicitud,
        fecha_revision,
        observacion_revision
     FROM establecimientos
     WHERE solicitante_id = ?
     ORDER BY fecha_solicitud DESC, id_establecimiento DESC
     LIMIT 50"
);
$consultaSolicitudes->bind_param('i', $idUsuario);
$consultaSolicitudes->execute();
$solicitudes = $consultaSolicitudes
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaSolicitudes->close();

$etiquetasEstado = [
    'pendiente' => 'Pendiente',
    'correccion' => 'Requiere corrección',
    'aprobado' => 'Aprobado',
    'rechazado' => 'Rechazado',
    'oculto' => 'Oculto'
];

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
    <title>Solicitud de establecimiento | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparSolicitudEstablecimiento(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
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
                <h1>Registrar establecimiento</h1>
                <p>
                    La información y los documentos quedarán pendientes de
                    revisión; no se publicarán hasta que se apruebe la solicitud.
                </p>
            </div>
        </section>

        <?php if ($mensaje !== ''): ?>
            <div class="<?php echo escaparSolicitudEstablecimiento($tipoMensaje); ?>" role="status">
                <?php echo escaparSolicitudEstablecimiento($mensaje); ?>
            </div>
        <?php endif; ?>

        <?php if (is_array($flash)): ?>
            <div class="<?php echo ($flash['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>" role="status">
                <?php echo escaparSolicitudEstablecimiento($flash['mensaje'] ?? ''); ?>
            </div>
        <?php endif; ?>

        <section class="seccion-admin">
            <article class="tarjeta">
                <h2>Datos del establecimiento</h2>

                <form method="POST" enctype="multipart/form-data">
                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?php echo escaparSolicitudEstablecimiento($csrf); ?>"
                    >

                    <label for="nombre">Nombre comercial</label>
                    <input
                        id="nombre"
                        name="nombre"
                        maxlength="180"
                        required
                        value="<?php echo escaparSolicitudEstablecimiento($nombre); ?>"
                    >

                    <label for="tipo">Tipo de establecimiento</label>
                    <select id="tipo" name="tipo" required>
                        <option value="">Selecciona un tipo</option>
                        <?php foreach ($tiposEstablecimiento as $valor => $etiqueta): ?>
                            <option
                                value="<?php echo escaparSolicitudEstablecimiento($valor); ?>"
                                <?php echo $tipoEstablecimiento === $valor ? 'selected' : ''; ?>
                            >
                                <?php echo escaparSolicitudEstablecimiento($etiqueta); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>

                    <label for="descripcion">Descripción</label>
                    <textarea
                        id="descripcion"
                        name="descripcion"
                        maxlength="5000"
                        rows="5"
                    ><?php echo escaparSolicitudEstablecimiento($descripcion); ?></textarea>

                    <label for="direccion">Ubicación o dirección general</label>
                    <input
                        id="direccion"
                        name="direccion"
                        maxlength="300"
                        required
                        value="<?php echo escaparSolicitudEstablecimiento($direccion); ?>"
                    >

                    <label for="telefono">Teléfono de contacto (opcional)</label>
                    <input
                        id="telefono"
                        name="telefono"
                        maxlength="30"
                        value="<?php echo escaparSolicitudEstablecimiento($telefono); ?>"
                    >

                    <label for="sitio_web">Sitio web (opcional)</label>
                    <input
                        id="sitio_web"
                        name="sitio_web"
                        type="url"
                        maxlength="500"
                        placeholder="https://"
                        value="<?php echo escaparSolicitudEstablecimiento($sitioWeb); ?>"
                    >

                    <fieldset>
                        <legend>Documento de respaldo</legend>
                        <p>
                            Adjunta al menos un PDF, JPG, PNG o WEBP, de hasta
                            10 MB por archivo. Los documentos serán privados y
                            solo estarán disponibles para revisión autorizada.
                        </p>

                        <label for="tipo_documento">Tipo de documento</label>
                        <select id="tipo_documento" name="tipo_documento" required>
                            <option value="">Selecciona un tipo</option>
                            <?php foreach ($tiposDocumento as $valor => $etiqueta): ?>
                                <option
                                    value="<?php echo escaparSolicitudEstablecimiento($valor); ?>"
                                    <?php echo $tipoDocumento === $valor ? 'selected' : ''; ?>
                                >
                                    <?php echo escaparSolicitudEstablecimiento($etiqueta); ?>
                                </option>
                            <?php endforeach; ?>
                        </select>

                        <label for="documentos">Archivos (máximo 5)</label>
                        <input
                            id="documentos"
                            type="file"
                            name="documentos[]"
                            accept=".pdf,.jpg,.jpeg,.png,.webp,application/pdf,image/jpeg,image/png,image/webp"
                            multiple
                            required
                        >
                    </fieldset>

                    <p class="mensaje">
                        La revisión documental no certifica licencias, formación
                        profesional, calidad del servicio ni ausencia de fraude.
                        La aprobación no activa publicidad pagada.
                    </p>

                    <button class="boton" type="submit">
                        Enviar a revisión
                    </button>
                </form>
            </article>
        </section>

        <section class="seccion-admin">
            <h2>Mis solicitudes</h2>

            <?php if ($solicitudes === []): ?>
                <article class="tarjeta">
                    <p>Todavía no has enviado solicitudes de establecimiento.</p>
                </article>
            <?php else: ?>
                <div class="actividad-admin">
                    <?php foreach ($solicitudes as $solicitud): ?>
                        <article class="tarjeta-actividad">
                            <h3><?php echo escaparSolicitudEstablecimiento($solicitud['nombre']); ?></h3>
                            <p>
                                Tipo:
                                <?php echo escaparSolicitudEstablecimiento($tiposEstablecimiento[$solicitud['tipo']] ?? $solicitud['tipo']); ?>
                            </p>
                            <p>
                                Estado:
                                <strong>
                                    <?php echo escaparSolicitudEstablecimiento($etiquetasEstado[$solicitud['estatus']] ?? $solicitud['estatus']); ?>
                                </strong>
                            </p>
                            <p>
                                Enviada:
                                <?php echo escaparSolicitudEstablecimiento(date('d/m/Y H:i', strtotime($solicitud['fecha_solicitud']))); ?>
                            </p>

                            <?php if (!empty($solicitud['observacion_revision'])): ?>
                                <h4>Observación administrativa</h4>
                                <p>
                                    <?php echo nl2br(escaparSolicitudEstablecimiento($solicitud['observacion_revision'])); ?>
                                </p>
                            <?php endif; ?>

                            <?php if ($solicitud['estatus'] === 'correccion'): ?>
                                <a
                                    class="boton boton-secundario"
                                    href="<?php echo escaparSolicitudEstablecimiento(RUTA_WEB); ?>/Funciones/corregir_establecimiento.php?id=<?php echo (int)$solicitud['id_establecimiento']; ?>"
                                >
                                    Corregir y reenviar
                                </a>
                            <?php endif; ?>
                        </article>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
        </section>
    </main>

    <script
        src="<?php echo escaparSolicitudEstablecimiento(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>