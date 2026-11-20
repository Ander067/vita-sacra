<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';
require_once __DIR__ . '/componentes/cabecera.php';

requiereRol($mysqli, 'administrador');

$idAdministrador = (int)$_SESSION['id_usr'];

function escaparRevisionEstablecimiento($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postRevisionEstablecimiento(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';
    return is_string($valor) ? trim($valor) : '';
}

function volverRevisionEstablecimiento(string $mensaje = ''): void
{
    $destino = RUTA_WEB . '/Funciones/revisar_establecimientos.php';

    if ($mensaje !== '') {
        $destino .= '?mensaje=' . rawurlencode($mensaje);
    }

    header('Location: ' . $destino, true, 303);
    exit;
}

function directorioPrivadoEstablecimientos(): string
{
    $documentRootRecibido = $_SERVER['DOCUMENT_ROOT'] ?? '';
    $documentRoot = is_string($documentRootRecibido)
        ? realpath($documentRootRecibido)
        : false;

    if ($documentRoot === false) {
        throw new RuntimeException('No se pudo determinar la raíz web.');
    }

    $directorio = dirname($documentRoot)
        . DIRECTORY_SEPARATOR
        . 'vitasacra_privado'
        . DIRECTORY_SEPARATOR
        . 'establecimientos';

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
        || strpos($directorioNormalizado, $raizNormalizada . '/') === 0
    ) {
        throw new RuntimeException(
            'El almacenamiento privado no está disponible o está dentro de la raíz web.'
        );
    }

    return $directorioReal;
}

function servirDocumentoPrivado(mysqli $mysqli): void
{
    $idRecibido = $_GET['documento'] ?? null;
    $idDocumento = is_scalar($idRecibido)
        ? filter_var(
            $idRecibido,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        )
        : false;

    if ($idDocumento === false) {
        http_response_code(404);
        exit;
    }

    $consulta = $mysqli->prepare(
        "SELECT
            clave_almacenamiento,
            nombre_original,
            mime,
            tamano_bytes
         FROM documentos_establecimiento
         WHERE id_documento = ?
         LIMIT 1"
    );
    $consulta->bind_param('i', $idDocumento);
    $consulta->execute();
    $documento = $consulta->get_result()->fetch_assoc();
    $consulta->close();

    if (!$documento) {
        http_response_code(404);
        exit;
    }

    $clave = (string)$documento['clave_almacenamiento'];

    if (!preg_match('/^[a-f0-9]{32}\.(pdf|jpg|png|webp)$/', $clave)) {
        http_response_code(404);
        exit;
    }

    $directorio = directorioPrivadoEstablecimientos();
    $ruta = realpath($directorio . DIRECTORY_SEPARATOR . $clave);
    $prefijo = rtrim(
        strtolower(str_replace('\\', '/', $directorio)),
        '/'
    ) . '/';
    $rutaNormalizada = $ruta === false
        ? ''
        : strtolower(str_replace('\\', '/', $ruta));

    if (
        $ruta === false
        || strpos($rutaNormalizada, $prefijo) !== 0
        || !is_file($ruta)
    ) {
        http_response_code(404);
        exit;
    }

    $nombre = preg_replace(
        '/[\r\n"\\\\]/',
        '_',
        (string)$documento['nombre_original']
    );
    $nombre = $nombre !== '' ? $nombre : 'documento';

    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: private, no-store, max-age=0');
    header('Content-Type: application/octet-stream');
    header(
        'Content-Disposition: attachment; filename="documento"; filename*=UTF-8\'\''
        . rawurlencode($nombre)
    );
    header('Content-Length: ' . (string)filesize($ruta));

    readfile($ruta);
    exit;
}

if (isset($_GET['documento'])) {
    servirDocumentoPrivado($mysqli);
}

$mensaje = '';
$tipoMensaje = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $idRecibido = postRevisionEstablecimiento('id_establecimiento');
    $idEstablecimiento = filter_var(
        $idRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );
    $decision = postRevisionEstablecimiento('decision');
    $observacion = postRevisionEstablecimiento('observacion');
    $csrfRecibido = postRevisionEstablecimiento('csrf_token');

    if (!verificarCSRF($csrfRecibido)) {
        $_SESSION['flash_revision_establecimientos'] = [
            'tipo' => 'error',
            'mensaje' => 'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
        ];
        volverRevisionEstablecimiento();
    }

    if ($idEstablecimiento === false) {
        $_SESSION['flash_revision_establecimientos'] = [
            'tipo' => 'error',
            'mensaje' => 'El establecimiento seleccionado no es válido.'
        ];
        volverRevisionEstablecimiento();
    }

    $decisionesPermitidas = [
        'aprobar',
        'correccion',
        'rechazar',
        'ocultar'
    ];

    if (!in_array($decision, $decisionesPermitidas, true)) {
        $_SESSION['flash_revision_establecimientos'] = [
            'tipo' => 'error',
            'mensaje' => 'Selecciona una decisión válida.'
        ];
        volverRevisionEstablecimiento();
    }

    if (
        in_array($decision, ['correccion', 'rechazar', 'ocultar'], true)
        && mb_strlen($observacion, 'UTF-8') < 5
    ) {
        $_SESSION['flash_revision_establecimientos'] = [
            'tipo' => 'error',
            'mensaje' => 'Escribe una observación de al menos 5 caracteres para esta decisión.'
        ];
        volverRevisionEstablecimiento();
    }

    if (mb_strlen($observacion, 'UTF-8') > 5000) {
        $_SESSION['flash_revision_establecimientos'] = [
            'tipo' => 'error',
            'mensaje' => 'La observación no puede superar los 5,000 caracteres.'
        ];
        volverRevisionEstablecimiento();
    }

    $documentosConfirmados = $_POST['documentos_validos'] ?? [];
    if (!is_array($documentosConfirmados)) {
        $documentosConfirmados = [];
    }

    $idsDocumentosConfirmados = [];
    foreach ($documentosConfirmados as $idRecibido) {
        $id = is_scalar($idRecibido)
            ? filter_var(
                $idRecibido,
                FILTER_VALIDATE_INT,
                ['options' => ['min_range' => 1]]
            )
            : false;

        if ($id === false) {
            $_SESSION['flash_revision_establecimientos'] = [
                'tipo' => 'error',
                'mensaje' => 'La selección de documentos no es válida.'
            ];
            volverRevisionEstablecimiento();
        }

        $idsDocumentosConfirmados[] = (int)$id;
    }

    $idsDocumentosConfirmados = array_values(
        array_unique($idsDocumentosConfirmados)
    );

    $idEstablecimiento = (int)$idEstablecimiento;
    $mysqli->begin_transaction();

    try {
        $bloqueo = $mysqli->prepare(
            "SELECT estatus
             FROM establecimientos
             WHERE id_establecimiento = ?
             LIMIT 1
             FOR UPDATE"
        );
        $bloqueo->bind_param('i', $idEstablecimiento);
        $bloqueo->execute();
        $establecimiento = $bloqueo->get_result()->fetch_assoc();
        $bloqueo->close();

        if (!$establecimiento) {
            throw new DomainException('No se encontró el establecimiento.');
        }

        $estadoAnterior = (string)$establecimiento['estatus'];

        if ($decision === 'ocultar') {
            if ($estadoAnterior !== 'aprobado') {
                throw new DomainException(
                    'Solo se puede ocultar un establecimiento aprobado.'
                );
            }
            $estadoNuevo = 'oculto';
            $accion = 'ocultada';
        } elseif ($decision === 'aprobar') {
            if (!in_array($estadoAnterior, ['pendiente', 'correccion', 'oculto'], true)) {
                throw new DomainException(
                    'El estado actual no permite aprobar este expediente.'
                );
            }

            $consultaDocumentos = $mysqli->prepare(
                "SELECT id_documento, estatus
                 FROM documentos_establecimiento
                 WHERE establecimiento_id = ?
                 ORDER BY id_documento"
            );
            $consultaDocumentos->bind_param('i', $idEstablecimiento);
            $consultaDocumentos->execute();
            $documentos = $consultaDocumentos
                ->get_result()
                ->fetch_all(MYSQLI_ASSOC);
            $consultaDocumentos->close();

            $idsDocumentos = array_map(
                static fn(array $documento): int =>
                    (int)$documento['id_documento'],
                $documentos
            );
            sort($idsDocumentos);
            sort($idsDocumentosConfirmados);

            if (
                $documentos === []
                || $idsDocumentos !== $idsDocumentosConfirmados
            ) {
                throw new DomainException(
                    'Para aprobar, confirma todos los documentos del expediente.'
                );
            }

            $validarDocumentos = $mysqli->prepare(
                "UPDATE documentos_establecimiento
                 SET estatus = 'validado',
                     validado_por = ?,
                     observacion_validacion = NULL,
                     fecha_revision = CURRENT_TIMESTAMP
                 WHERE establecimiento_id = ?"
            );
            $validarDocumentos->bind_param(
                'ii',
                $idAdministrador,
                $idEstablecimiento
            );
            $validarDocumentos->execute();
            $validarDocumentos->close();

            $estadoNuevo = 'aprobado';
            $accion = 'aprobada';
        } elseif ($decision === 'correccion') {
            if (!in_array($estadoAnterior, ['pendiente', 'correccion'], true)) {
                throw new DomainException(
                    'No se pueden solicitar correcciones en el estado actual.'
                );
            }
            $estadoNuevo = 'correccion';
            $accion = 'correccion_solicitada';
        } else {
            if (!in_array($estadoAnterior, ['pendiente', 'correccion'], true)) {
                throw new DomainException(
                    'No se puede rechazar el expediente en su estado actual.'
                );
            }
            $estadoNuevo = 'rechazado';
            $accion = 'rechazada';
        }

        $actualizar = $mysqli->prepare(
            "UPDATE establecimientos
             SET estatus = ?,
                 administrador_id = ?,
                 fecha_revision = CURRENT_TIMESTAMP,
                 observacion_revision = ?
             WHERE id_establecimiento = ?"
        );
        $actualizar->bind_param(
            'sisi',
            $estadoNuevo,
            $idAdministrador,
            $observacion,
            $idEstablecimiento
        );
        $actualizar->execute();
        $actualizar->close();

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
            $idAdministrador,
            $accion,
            $estadoAnterior,
            $estadoNuevo,
            $observacion
        );
        $insertarHistorial->execute();
        $insertarHistorial->close();

        $mysqli->commit();

        $_SESSION['flash_revision_establecimientos'] = [
            'tipo' => 'exito',
            'mensaje' => 'La decisión administrativa quedó registrada.'
        ];
    } catch (DomainException $error) {
        $mysqli->rollback();
        $_SESSION['flash_revision_establecimientos'] = [
            'tipo' => 'error',
            'mensaje' => $error->getMessage()
        ];
    } catch (Throwable $error) {
        $mysqli->rollback();
        error_log(
            'Vita Sacra: error al revisar establecimiento: '
            . $error->getMessage()
        );
        $_SESSION['flash_revision_establecimientos'] = [
            'tipo' => 'error',
            'mensaje' => 'No se pudo registrar la decisión. Inténtalo nuevamente.'
        ];
    }

    volverRevisionEstablecimiento();
}

$estadoRecibido = $_GET['estado'] ?? 'pendiente';
$estado = is_string($estadoRecibido) ? $estadoRecibido : 'pendiente';
$estadosPermitidos = [
    'pendiente',
    'correccion',
    'aprobado',
    'rechazado',
    'oculto',
    'todos'
];

if (!in_array($estado, $estadosPermitidos, true)) {
    $estado = 'pendiente';
}

$idDetalleRecibido = $_GET['id'] ?? null;
$idDetalle = is_scalar($idDetalleRecibido)
    ? filter_var(
        $idDetalleRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

$idDetalle = $idDetalle === false ? null : (int)$idDetalle;

$condicionEstado = $estado === 'todos' ? '%' : $estado;

$consultaLista = $mysqli->prepare(
    "SELECT
        e.id_establecimiento,
        e.nombre,
        e.tipo,
        e.direccion,
        e.estatus,
        e.fecha_solicitud,
        u.nom_usr AS solicitante,
        (
            SELECT COUNT(*)
            FROM documentos_establecimiento d
            WHERE d.establecimiento_id = e.id_establecimiento
        ) AS total_documentos
     FROM establecimientos e
     INNER JOIN usuario u
        ON u.id_usr = e.solicitante_id
     WHERE (? = '%' OR e.estatus = ?)
     ORDER BY
        (e.estatus = 'pendiente') DESC,
        e.fecha_solicitud ASC,
        e.id_establecimiento DESC
     LIMIT 100"
);
$consultaLista->bind_param(
    'ss',
    $condicionEstado,
    $condicionEstado
);
$consultaLista->execute();
$establecimientos = $consultaLista
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaLista->close();

$detalle = null;
$documentos = [];
$historial = [];

if ($idDetalle !== null) {
    $consultaDetalle = $mysqli->prepare(
        "SELECT
            e.*,
            u.nom_usr AS solicitante,
            u.mail AS correo_solicitante
         FROM establecimientos e
         INNER JOIN usuario u
            ON u.id_usr = e.solicitante_id
         WHERE e.id_establecimiento = ?
         LIMIT 1"
    );
    $consultaDetalle->bind_param('i', $idDetalle);
    $consultaDetalle->execute();
    $detalle = $consultaDetalle->get_result()->fetch_assoc();
    $consultaDetalle->close();

    if ($detalle) {
        $consultaDocumentos = $mysqli->prepare(
            "SELECT
                id_documento,
                tipo_documento,
                nombre_original,
                mime,
                tamano_bytes,
                estatus,
                fecha,
                observacion_validacion
             FROM documentos_establecimiento
             WHERE establecimiento_id = ?
             ORDER BY fecha, id_documento"
        );
        $consultaDocumentos->bind_param('i', $idDetalle);
        $consultaDocumentos->execute();
        $documentos = $consultaDocumentos
            ->get_result()
            ->fetch_all(MYSQLI_ASSOC);
        $consultaDocumentos->close();

        $consultaHistorial = $mysqli->prepare(
            "SELECT
                h.accion,
                h.estado_anterior,
                h.estado_nuevo,
                h.observacion,
                h.fecha,
                u.nom_usr AS actor
             FROM historial_establecimientos h
             INNER JOIN usuario u
                ON u.id_usr = h.actor_id
             WHERE h.establecimiento_id = ?
             ORDER BY h.fecha DESC, h.id_evento DESC"
        );
        $consultaHistorial->bind_param('i', $idDetalle);
        $consultaHistorial->execute();
        $historial = $consultaHistorial
            ->get_result()
            ->fetch_all(MYSQLI_ASSOC);
        $consultaHistorial->close();
    }
}

$flash = $_SESSION['flash_revision_establecimientos'] ?? null;
unset($_SESSION['flash_revision_establecimientos']);
$csrf = generarCSRF();

$nombreCabecera = $_SESSION['nom_usr'] ?? 'Administración';
$nombreCabecera = is_string($nombreCabecera)
    ? $nombreCabecera
    : 'Administración';
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Revisión de establecimientos | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparRevisionEstablecimiento(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreCabecera,
        'administrador',
        '',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Revisión de establecimientos</h1>
                <p>Consulta los datos y documentos privados antes de resolver cada expediente.</p>
            </div>
        </section>

        <nav class="enlaces" aria-label="Filtrar expedientes">
            <?php foreach ([
                'pendiente' => 'Pendientes',
                'correccion' => 'Correcciones',
                'aprobado' => 'Aprobados',
                'rechazado' => 'Rechazados',
                'oculto' => 'Ocultos',
                'todos' => 'Todos'
            ] as $valor => $etiqueta): ?>
                <a
                    class="boton <?php echo $estado === $valor ? '' : 'boton-secundario'; ?>"
                    href="<?php echo escaparRevisionEstablecimiento(RUTA_WEB); ?>/Funciones/revisar_establecimientos.php?estado=<?php echo rawurlencode($valor); ?>"
                    <?php echo $estado === $valor ? 'aria-current="page"' : ''; ?>
                >
                    <?php echo escaparRevisionEstablecimiento($etiqueta); ?>
                </a>
            <?php endforeach; ?>
        </nav>

        <?php if (is_array($flash)): ?>
            <div
                class="<?php echo ($flash['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>"
                role="status"
            >
                <?php echo escaparRevisionEstablecimiento($flash['mensaje'] ?? ''); ?>
            </div>
        <?php endif; ?>

        <?php if ($detalle): ?>
            <article class="tarjeta">
                <h2><?php echo escaparRevisionEstablecimiento($detalle['nombre']); ?></h2>
                <p><strong>Solicitante:</strong> <?php echo escaparRevisionEstablecimiento($detalle['solicitante']); ?></p>
                <p><strong>Correo:</strong> <?php echo escaparRevisionEstablecimiento($detalle['correo_solicitante']); ?></p>
                <p><strong>Tipo:</strong> <?php echo escaparRevisionEstablecimiento($detalle['tipo']); ?></p>
                <p><strong>Descripción:</strong><br><?php echo nl2br(escaparRevisionEstablecimiento($detalle['descripcion'] ?? '')); ?></p>
                <p><strong>Dirección:</strong> <?php echo escaparRevisionEstablecimiento($detalle['direccion']); ?></p>
                <p><strong>Teléfono:</strong> <?php echo escaparRevisionEstablecimiento($detalle['telefono'] ?? 'No proporcionado'); ?></p>

                <?php
                $sitio = (string)($detalle['sitio_web'] ?? '');
                $sitioValido = filter_var($sitio, FILTER_VALIDATE_URL)
                    && in_array(
                        strtolower((string)parse_url($sitio, PHP_URL_SCHEME)),
                        ['http', 'https'],
                        true
                    );
                ?>
                <p>
                    <strong>Sitio web:</strong>
                    <?php if ($sitioValido): ?>
                        <a href="<?php echo escaparRevisionEstablecimiento($sitio); ?>" target="_blank" rel="noopener noreferrer">
                            <?php echo escaparRevisionEstablecimiento($sitio); ?>
                        </a>
                    <?php else: ?>
                        No proporcionado
                    <?php endif; ?>
                </p>

                <p><strong>Estado:</strong> <?php echo escaparRevisionEstablecimiento($detalle['estatus']); ?></p>
                <p><strong>Enviado:</strong> <?php echo escaparRevisionEstablecimiento($detalle['fecha_solicitud']); ?></p>

                <h3>Documentos privados</h3>
                <?php if ($documentos === []): ?>
                    <p>No hay documentos adjuntos.</p>
                <?php else: ?>
                    <ul>
                        <?php foreach ($documentos as $documento): ?>
                            <li>
                                <?php echo escaparRevisionEstablecimiento($documento['tipo_documento']); ?>
                                — <?php echo escaparRevisionEstablecimiento($documento['nombre_original']); ?>
                                (<?php echo escaparRevisionEstablecimiento($documento['estatus']); ?>,
                                <?php echo number_format((int)$documento['tamano_bytes'] / 1024, 1); ?> KB)
                                <a href="<?php echo escaparRevisionEstablecimiento(RUTA_WEB); ?>/Funciones/revisar_establecimientos.php?documento=<?php echo (int)$documento['id_documento']; ?>">
                                    Descargar privado
                                </a>
                                <?php if ($detalle['estatus'] === 'pendiente' || $detalle['estatus'] === 'correccion'): ?>
                                    <label>
                                        <input
                                            type="checkbox"
                                            form="form-decision"
                                            name="documentos_validos[]"
                                            value="<?php echo (int)$documento['id_documento']; ?>"
                                        >
                                        Confirmo que este documento fue revisado
                                    </label>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ul>
                <?php endif; ?>

                <?php if ($detalle['estatus'] === 'pendiente' || $detalle['estatus'] === 'correccion'): ?>
                    <form id="form-decision" method="POST">
                        <input type="hidden" name="csrf_token" value="<?php echo escaparRevisionEstablecimiento($csrf); ?>">
                        <input type="hidden" name="id_establecimiento" value="<?php echo (int)$detalle['id_establecimiento']; ?>">

                        <label for="decision">Decisión</label>
                        <select id="decision" name="decision" required>
                            <option value="">Selecciona una decisión</option>
                            <option value="aprobar">Aprobar establecimiento</option>
                            <option value="correccion">Solicitar correcciones</option>
                            <option value="rechazar">Rechazar expediente</option>
                        </select>

                        <label for="observacion">Observación (obligatoria para corrección o rechazo)</label>
                        <textarea id="observacion" name="observacion" rows="4" maxlength="5000"></textarea>

                        <button class="boton" type="submit">Registrar decisión</button>
                    </form>
                <?php elseif ($detalle['estatus'] === 'aprobado'): ?>
                    <form method="POST">
                        <input type="hidden" name="csrf_token" value="<?php echo escaparRevisionEstablecimiento($csrf); ?>">
                        <input type="hidden" name="id_establecimiento" value="<?php echo (int)$detalle['id_establecimiento']; ?>">
                        <input type="hidden" name="decision" value="ocultar">
                        <label for="observacion-ocultar">Motivo para ocultar</label>
                        <textarea id="observacion-ocultar" name="observacion" rows="3" maxlength="5000" required></textarea>
                        <button class="boton boton-secundario" type="submit">Ocultar establecimiento</button>
                    </form>
                <?php endif; ?>

                <?php if (!empty($detalle['observacion_revision'])): ?>
                    <h3>Observación administrativa</h3>
                    <p><?php echo nl2br(escaparRevisionEstablecimiento($detalle['observacion_revision'])); ?></p>
                <?php endif; ?>

                <?php if ($historial !== []): ?>
                    <h3>Historial</h3>
                    <ol>
                        <?php foreach ($historial as $evento): ?>
                            <li>
                                <?php echo escaparRevisionEstablecimiento($evento['accion']); ?>
                                — <?php echo escaparRevisionEstablecimiento($evento['estado_anterior'] ?? 'nuevo'); ?>
                                → <?php echo escaparRevisionEstablecimiento($evento['estado_nuevo']); ?>
                                — <?php echo escaparRevisionEstablecimiento($evento['actor']); ?>
                                — <?php echo escaparRevisionEstablecimiento($evento['fecha']); ?>
                                <?php if (!empty($evento['observacion'])): ?>
                                    <p><?php echo nl2br(escaparRevisionEstablecimiento($evento['observacion'])); ?></p>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ol>
                <?php endif; ?>
            </article>
        <?php else: ?>
            <section class="seccion-admin">
                <h2>Expedientes</h2>

                <?php if ($establecimientos === []): ?>
                    <article class="tarjeta">
                        <p>No hay expedientes en este filtro.</p>
                    </article>
                <?php else: ?>
                    <div class="actividad-admin">
                        <?php foreach ($establecimientos as $establecimiento): ?>
                            <article class="tarjeta-actividad">
                                <h3><?php echo escaparRevisionEstablecimiento($establecimiento['nombre']); ?></h3>
                                <p>Solicitante: <?php echo escaparRevisionEstablecimiento($establecimiento['solicitante']); ?></p>
                                <p>Tipo: <?php echo escaparRevisionEstablecimiento($establecimiento['tipo']); ?></p>
                                <p>Estado: <?php echo escaparRevisionEstablecimiento($establecimiento['estatus']); ?></p>
                                <p>Documentos: <?php echo (int)$establecimiento['total_documentos']; ?></p>
                                <a class="boton boton-secundario" href="<?php echo escaparRevisionEstablecimiento(RUTA_WEB); ?>/Funciones/revisar_establecimientos.php?id=<?php echo (int)$establecimiento['id_establecimiento']; ?>&amp;estado=<?php echo rawurlencode($estado); ?>">
                                    Revisar expediente
                                </a>
                            </article>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>
            </section>
        <?php endif; ?>
    </main>

    <script
        src="<?php echo escaparRevisionEstablecimiento(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>