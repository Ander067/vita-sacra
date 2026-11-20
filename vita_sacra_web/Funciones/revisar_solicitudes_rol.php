<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereRol($mysqli, 'administrador');

$administradorId = (int)$_SESSION['id_usr'];

function escaparRevisionRoles($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function obtenerNombreRevisionRoles(): string
{
    $nombre = $_SESSION['nom_usr'] ?? 'Administración';

    return is_string($nombre)
        ? $nombre
        : 'Administración';
}

function volverRevisionRoles(): void
{
    header(
        'Location: ' . RUTA_WEB . '/Funciones/revisar_solicitudes_rol.php',
        true,
        303
    );
    exit;
}

function cargarTemasRevisionRoles(
    mysqli $mysqli,
    array $solicitudes
): array {
    if ($solicitudes === []) {
        return [];
    }

    $idsSolicitudes = array_values(array_unique(array_map(
        static fn(array $solicitud): int =>
            (int)$solicitud['id_solicitud'],
        $solicitudes
    )));

    $marcadores = implode(
        ',',
        array_fill(0, count($idsSolicitudes), '?')
    );
    $tipos = str_repeat('i', count($idsSolicitudes));

    $consulta = $mysqli->prepare(
        "SELECT srt.id_solicitud, c.nombre
         FROM solicitudes_rol_temas srt
         INNER JOIN categorias c
            ON c.id_categoria = srt.id_categoria
         WHERE srt.id_solicitud IN ($marcadores)
         ORDER BY c.nombre"
    );

    $argumentos = [];
    $argumentos[] = &$tipos;

    foreach ($idsSolicitudes as $indice => $idSolicitud) {
        $idsSolicitudes[$indice] = (int)$idSolicitud;
        $argumentos[] = &$idsSolicitudes[$indice];
    }

    if (!call_user_func_array(
        [$consulta, 'bind_param'],
        $argumentos
    )) {
        $consulta->close();
        throw new RuntimeException(
            'No se pudieron vincular las solicitudes para cargar sus temas.'
        );
    }

    $consulta->execute();
    $resultado = $consulta->get_result();
    $temasPorSolicitud = [];

    while ($fila = $resultado->fetch_assoc()) {
        $idSolicitud = (int)$fila['id_solicitud'];
        $temasPorSolicitud[$idSolicitud][] = $fila['nombre'];
    }

    $consulta->close();

    return $temasPorSolicitud;
}

function fechaRevisionRoles($fecha): string
{
    if (!is_string($fecha) || $fecha === '') {
        return 'No disponible';
    }

    $marcaTiempo = strtotime($fecha);

    return $marcaTiempo === false
        ? 'No disponible'
        : date('d/m/Y H:i', $marcaTiempo);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $csrfRecibido = $_POST['csrf_token'] ?? '';

    if (
        !is_string($csrfRecibido)
        || !verificarCSRF($csrfRecibido)
    ) {
        $_SESSION['flash_revision_roles'] = [
            'tipo' => 'error',
            'mensaje' => 'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
        ];
        volverRevisionRoles();
    }

    $accionRecibida = $_POST['accion'] ?? '';
    $accion = is_string($accionRecibida)
        ? $accionRecibida
        : '';

    $idRecibido = $_POST['id_solicitud'] ?? null;
    $idSolicitud = is_scalar($idRecibido)
        ? filter_var(
            $idRecibido,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        )
        : false;

    $observacionRecibida = $_POST['observacion'] ?? '';
    $observacion = is_string($observacionRecibida)
        ? trim($observacionRecibida)
        : '';

    if (
        !in_array($accion, ['aprobar', 'rechazar'], true)
        || $idSolicitud === false
    ) {
        $_SESSION['flash_revision_roles'] = [
            'tipo' => 'error',
            'mensaje' => 'La acción o la solicitud seleccionada no es válida.'
        ];
        volverRevisionRoles();
    }

    if (
        $accion === 'rechazar'
        && mb_strlen($observacion, 'UTF-8') < 5
    ) {
        $_SESSION['flash_revision_roles'] = [
            'tipo' => 'error',
            'mensaje' => 'Escribe una observación de al menos 5 caracteres para rechazar la solicitud.'
        ];
        volverRevisionRoles();
    }

    if (mb_strlen($observacion, 'UTF-8') > 2000) {
        $_SESSION['flash_revision_roles'] = [
            'tipo' => 'error',
            'mensaje' => 'La observación no puede superar los 2,000 caracteres.'
        ];
        volverRevisionRoles();
    }

    $idSolicitud = (int)$idSolicitud;
    $mysqli->begin_transaction();

    try {
        $consultaSolicitud = $mysqli->prepare(
            "SELECT
                sr.id_solicitud,
                sr.usr_id,
                sr.rol_id,
                sr.estatus,
                sr.acepta_normas,
                sr.version_normas,
                sr.fecha_aceptacion,
                rol.nombre AS nombre_rol
             FROM solicitudes_rol sr
             INNER JOIN roles rol
                ON rol.id_rol = sr.rol_id
             WHERE sr.id_solicitud = ?
             LIMIT 1
             FOR UPDATE"
        );

        $consultaSolicitud->bind_param('i', $idSolicitud);
        $consultaSolicitud->execute();
        $solicitud = $consultaSolicitud
            ->get_result()
            ->fetch_assoc();
        $consultaSolicitud->close();

        if (!$solicitud) {
            throw new DomainException(
                'No se encontró la solicitud seleccionada.'
            );
        }

        if ($solicitud['estatus'] !== 'pendiente') {
            throw new DomainException(
                'Esta solicitud ya fue revisada.'
            );
        }

        if (strtolower($solicitud['nombre_rol']) !== 'autor') {
            throw new DomainException(
                'El rol solicitado no puede aprobarse desde este flujo.'
            );
        }

        $idUsuario = (int)$solicitud['usr_id'];
        $idRol = (int)$solicitud['rol_id'];

        if ($accion === 'aprobar') {
            if (
                (int)$solicitud['acepta_normas'] !== 1
                || !is_string($solicitud['version_normas'])
                || trim($solicitud['version_normas']) === ''
                || $solicitud['fecha_aceptacion'] === null
            ) {
                throw new DomainException(
                    'No se puede aprobar: la solicitud no tiene una aceptación registrada de las normas editoriales.'
                );
            }

            $consultaTotalTemas = $mysqli->prepare(
                "SELECT COUNT(*) AS total
                 FROM solicitudes_rol_temas
                 WHERE id_solicitud = ?"
            );

            $consultaTotalTemas->bind_param('i', $idSolicitud);
            $consultaTotalTemas->execute();
            $totalTemas = $consultaTotalTemas
                ->get_result()
                ->fetch_assoc();
            $consultaTotalTemas->close();

            if ((int)($totalTemas['total'] ?? 0) < 1) {
                throw new DomainException(
                    'No se puede aprobar: la solicitud no tiene temas de interés registrados.'
                );
            }
        }

        $consultaUsuario = $mysqli->prepare(
            "SELECT estatus, tip_usu
             FROM usuario
             WHERE id_usr = ?
             LIMIT 1
             FOR UPDATE"
        );

        $consultaUsuario->bind_param('i', $idUsuario);
        $consultaUsuario->execute();
        $usuario = $consultaUsuario
            ->get_result()
            ->fetch_assoc();
        $consultaUsuario->close();

        if (!$usuario) {
            throw new DomainException(
                'La cuenta solicitante ya no existe.'
            );
        }

        if ($accion === 'aprobar') {
            if ($usuario['estatus'] !== 'activo') {
                throw new DomainException(
                    'Activa la cuenta antes de aprobar el cambio de rol.'
                );
            }

            if ((int)$usuario['tip_usu'] === $idRol) {
                throw new DomainException(
                    'La cuenta ya tiene ese rol como rol principal.'
                );
            }

            $consultaRolExistente = $mysqli->prepare(
                "SELECT 1
                 FROM usuario_roles
                 WHERE usr_id = ?
                   AND rol_id = ?
                 LIMIT 1"
            );

            $consultaRolExistente->bind_param(
                'ii',
                $idUsuario,
                $idRol
            );
            $consultaRolExistente->execute();
            $rolYaAsignado = $consultaRolExistente
                ->get_result()
                ->fetch_assoc() !== null;
            $consultaRolExistente->close();

            if ($rolYaAsignado) {
                throw new DomainException(
                    'La cuenta ya tiene ese rol asignado.'
                );
            }

            $asignarRol = $mysqli->prepare(
                "INSERT INTO usuario_roles
                    (usr_id, rol_id, asignado_por)
                 VALUES (?, ?, ?)"
            );

            $asignarRol->bind_param(
                'iii',
                $idUsuario,
                $idRol,
                $administradorId
            );
            $asignarRol->execute();
            $asignarRol->close();

            $registrarCambio = $mysqli->prepare(
                "INSERT INTO historial_roles
                    (usr_id, rol_id, accion, administrador_id)
                 VALUES (?, ?, 'asignar', ?)"
            );

            $registrarCambio->bind_param(
                'iii',
                $idUsuario,
                $idRol,
                $administradorId
            );
            $registrarCambio->execute();
            $registrarCambio->close();

            $invalidarSesiones = $mysqli->prepare(
                "UPDATE usuario
                 SET version_sesion = version_sesion + 1
                 WHERE id_usr = ?"
            );

            $invalidarSesiones->bind_param('i', $idUsuario);
            $invalidarSesiones->execute();
            $invalidarSesiones->close();

            $nuevoEstado = 'aprobada';
        } else {
            $nuevoEstado = 'rechazada';
        }

        $actualizarSolicitud = $mysqli->prepare(
            "UPDATE solicitudes_rol
             SET estatus = ?,
                 revisado_por = ?,
                 observacion = ?,
                 fecha_revision = CURRENT_TIMESTAMP
             WHERE id_solicitud = ?
               AND estatus = 'pendiente'"
        );

        $actualizarSolicitud->bind_param(
            'sisi',
            $nuevoEstado,
            $administradorId,
            $observacion,
            $idSolicitud
        );
        $actualizarSolicitud->execute();
        $solicitudActualizada =
            $actualizarSolicitud->affected_rows === 1;
        $actualizarSolicitud->close();

        if (!$solicitudActualizada) {
            throw new DomainException(
                'La solicitud cambió antes de completar la revisión.'
            );
        }

        $mysqli->commit();

        $_SESSION['flash_revision_roles'] = [
            'tipo' => 'exito',
            'mensaje' => $nuevoEstado === 'aprobada'
                ? 'Solicitud aprobada. Se asignó el rol de autor y se invalidaron las sesiones anteriores.'
                : 'Solicitud rechazada. La decisión quedó registrada.'
        ];
    } catch (DomainException $error) {
        $mysqli->rollback();

        $_SESSION['flash_revision_roles'] = [
            'tipo' => 'error',
            'mensaje' => $error->getMessage()
        ];
    } catch (mysqli_sql_exception $error) {
        $mysqli->rollback();
        error_log(
            'Error al revisar solicitud de rol: '
            . $error->getMessage()
        );

        $_SESSION['flash_revision_roles'] = [
            'tipo' => 'error',
            'mensaje' => 'No se pudo completar la revisión. Inténtalo nuevamente.'
        ];
    }

    volverRevisionRoles();
}

$estadoRecibido = $_GET['estado'] ?? 'pendiente';
$estado = is_string($estadoRecibido)
    ? $estadoRecibido
    : 'pendiente';

if (!in_array(
    $estado,
    ['pendiente', 'aprobada', 'rechazada', 'todas'],
    true
)) {
    $estado = 'pendiente';
}

$consultaSolicitudes = $mysqli->prepare(
    "SELECT
        sr.id_solicitud,
        sr.usr_id,
        sr.rol_id,
        sr.motivo,
        sr.estatus,
        sr.observacion,
        sr.fecha,
        sr.fecha_revision,
        sr.acepta_normas,
        sr.version_normas,
        sr.fecha_aceptacion,
        solicitante.nom_usr AS nombre_solicitante,
        solicitante.mail AS correo_solicitante,
        rol.nombre AS nombre_rol,
        revisor.nom_usr AS nombre_revisor
     FROM solicitudes_rol sr
     INNER JOIN usuario solicitante
        ON solicitante.id_usr = sr.usr_id
     INNER JOIN roles rol
        ON rol.id_rol = sr.rol_id
     LEFT JOIN usuario revisor
        ON revisor.id_usr = sr.revisado_por
     WHERE (? = 'todas' OR sr.estatus = ?)
     ORDER BY
        (sr.estatus = 'pendiente') DESC,
        sr.fecha DESC,
        sr.id_solicitud DESC
     LIMIT 100"
);

$consultaSolicitudes->bind_param('ss', $estado, $estado);
$consultaSolicitudes->execute();
$solicitudes = $consultaSolicitudes
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaSolicitudes->close();

$temasPorSolicitud = cargarTemasRevisionRoles(
    $mysqli,
    $solicitudes
);

$consultaPendientes = $mysqli->prepare(
    "SELECT COUNT(*) AS total
     FROM solicitudes_rol
     WHERE estatus = 'pendiente'"
);

$consultaPendientes->execute();
$filaPendientes = $consultaPendientes
    ->get_result()
    ->fetch_assoc();
$consultaPendientes->close();

$totalPendientes = (int)($filaPendientes['total'] ?? 0);
$flash = $_SESSION['flash_revision_roles'] ?? null;
unset($_SESSION['flash_revision_roles']);

$csrf = generarCSRF();

require_once __DIR__ . '/componentes/cabecera.php';

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta
        name="description"
        content="Revisa solicitudes de autor, sus temas de interés y la aceptación de normas editoriales."
    >
    <title>Revisar solicitudes de rol | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparRevisionRoles(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        obtenerNombreRevisionRoles(),
        'administrador',
        'solicitudes-rol',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Solicitudes de rol</h1>
                <p>
                    Revisa la motivación, los temas y la aceptación de normas
                    antes de resolver cada solicitud.
                </p>
            </div>
            <span class="insignia-admin">
                <?php echo $totalPendientes; ?> pendientes
            </span>
        </section>

        <?php if (is_array($flash)): ?>
            <div
                class="<?php echo ($flash['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>"
                role="status"
            >
                <?php
                echo escaparRevisionRoles($flash['mensaje'] ?? '');
                ?>
            </div>
        <?php endif; ?>

        <nav class="enlaces" aria-label="Filtrar solicitudes">
            <?php
            $filtros = [
                'pendiente' => 'Pendientes',
                'aprobada' => 'Aprobadas',
                'rechazada' => 'Rechazadas',
                'todas' => 'Todas'
            ];
            ?>
            <?php foreach ($filtros as $valor => $etiqueta): ?>
                <a
                    class="boton <?php echo $estado === $valor ? '' : 'boton-secundario'; ?>"
                    href="<?php
                    echo escaparRevisionRoles(
                        RUTA_WEB
                        . '/Funciones/revisar_solicitudes_rol.php?estado='
                        . rawurlencode($valor)
                    );
                    ?>"
                    <?php if ($estado === $valor): ?>
                        aria-current="page"
                    <?php endif; ?>
                >
                    <?php echo escaparRevisionRoles($etiqueta); ?>
                </a>
            <?php endforeach; ?>
        </nav>

        <section class="seccion-admin" aria-label="Solicitudes">
            <?php if ($solicitudes === []): ?>
                <article class="tarjeta">
                    <h2>No hay solicitudes en este filtro</h2>
                    <p>Cuando existan solicitudes, aparecerán aquí.</p>
                </article>
            <?php else: ?>
                <?php foreach ($solicitudes as $solicitud): ?>
                    <?php
                    $idSolicitudVista = (int)$solicitud['id_solicitud'];
                    $temas = $temasPorSolicitud[$idSolicitudVista] ?? [];
                    $aceptoNormas =
                        (int)$solicitud['acepta_normas'] === 1
                        && is_string($solicitud['version_normas'])
                        && trim($solicitud['version_normas']) !== ''
                        && $solicitud['fecha_aceptacion'] !== null;
                    $puedeAprobar =
                        $aceptoNormas
                        && $temas !== [];
                    ?>
                    <article class="tarjeta">
                        <p>
                            Estado:
                            <strong>
                                <?php
                                echo escaparRevisionRoles(
                                    ucfirst($solicitud['estatus'])
                                );
                                ?>
                            </strong>
                        </p>

                        <h2>
                            <?php
                            echo escaparRevisionRoles(
                                $solicitud['nombre_solicitante']
                            );
                            ?>
                        </h2>

                        <p>
                            <?php
                            echo escaparRevisionRoles(
                                $solicitud['correo_solicitante']
                            );
                            ?>
                        </p>

                        <p>
                            Rol solicitado:
                            <strong>
                                <?php
                                echo escaparRevisionRoles(
                                    $solicitud['nombre_rol']
                                );
                                ?>
                            </strong>
                        </p>

                        <p>
                            Recibida:
                            <?php
                            echo escaparRevisionRoles(
                                fechaRevisionRoles($solicitud['fecha'])
                            );
                            ?>
                        </p>

                        <h3>Temas de interés</h3>
                        <?php if ($temas === []): ?>
                            <p>No hay temas registrados.</p>
                        <?php else: ?>
                            <p>
                                <?php
                                echo escaparRevisionRoles(
                                    implode(', ', $temas)
                                );
                                ?>
                            </p>
                        <?php endif; ?>

                        <h3>Normas editoriales</h3>
                        <?php if ($aceptoNormas): ?>
                            <p>
                                Aceptadas · versión
                                <?php
                                echo escaparRevisionRoles(
                                    $solicitud['version_normas']
                                );
                                ?>
                                ·
                                <?php
                                echo escaparRevisionRoles(
                                    fechaRevisionRoles(
                                        $solicitud['fecha_aceptacion']
                                    )
                                );
                                ?>
                            </p>
                        <?php else: ?>
                            <p class="mensaje-error">
                                No existe aceptación registrada. Esta solicitud
                                no puede aprobarse.
                            </p>
                        <?php endif; ?>

                        <h3>Motivación</h3>
                        <p>
                            <?php
                            echo nl2br(
                                escaparRevisionRoles(
                                    $solicitud['motivo']
                                )
                            );
                            ?>
                        </p>

                        <?php if ($solicitud['estatus'] === 'pendiente'): ?>
                            <form method="POST">
                                <input
                                    type="hidden"
                                    name="csrf_token"
                                    value="<?php echo escaparRevisionRoles($csrf); ?>"
                                >
                                <input
                                    type="hidden"
                                    name="id_solicitud"
                                    value="<?php echo $idSolicitudVista; ?>"
                                >

                                <label for="observacion-<?php echo $idSolicitudVista; ?>">
                                    Observación
                                </label>
                                <textarea
                                    id="observacion-<?php echo $idSolicitudVista; ?>"
                                    name="observacion"
                                    rows="3"
                                    maxlength="2000"
                                    placeholder="Obligatoria si rechazas; opcional si apruebas"
                                ></textarea>

                                <div class="enlaces">
                                    <?php if ($puedeAprobar): ?>
                                        <button
                                            class="boton"
                                            type="submit"
                                            name="accion"
                                            value="aprobar"
                                        >
                                            Aprobar
                                        </button>
                                    <?php else: ?>
                                        <p class="texto-secundario">
                                            Para aprobar, la solicitud debe
                                            incluir temas y aceptación de
                                            normas.
                                        </p>
                                    <?php endif; ?>

                                    <button
                                        class="boton boton-secundario"
                                        type="submit"
                                        name="accion"
                                        value="rechazar"
                                    >
                                        Rechazar
                                    </button>
                                </div>
                            </form>
                        <?php else: ?>
                            <p>
                                Revisada por:
                                <?php
                                echo escaparRevisionRoles(
                                    $solicitud['nombre_revisor']
                                        ?? 'No disponible'
                                );
                                ?>
                            </p>

                            <p>
                                Fecha de revisión:
                                <?php
                                echo escaparRevisionRoles(
                                    fechaRevisionRoles(
                                        $solicitud['fecha_revision']
                                    )
                                );
                                ?>
                            </p>

                            <?php if (!empty($solicitud['observacion'])): ?>
                                <h3>Observación</h3>
                                <p>
                                    <?php
                                    echo nl2br(
                                        escaparRevisionRoles(
                                            $solicitud['observacion']
                                        )
                                    );
                                    ?>
                                </p>
                            <?php endif; ?>
                        <?php endif; ?>
                    </article>
                <?php endforeach; ?>
            <?php endif; ?>
        </section>
    </main>

    <footer class="pie-admin">
        <p>Vita Sacra · Revisión de solicitudes de rol.</p>
    </footer>

    <script
        src="<?php echo escaparRevisionRoles(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>