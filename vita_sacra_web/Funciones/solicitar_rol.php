<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereUsuarioActual($mysqli);

$idUsuario = (int)$_SESSION['id_usr'];
$rolesActuales = obtenerRolesActuales($mysqli);
$versionNormas = '1.0';

function escaparSolicitudRol($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function fechaSolicitudRol($fecha): string
{
    if (!is_string($fecha) || $fecha === '') {
        return 'No disponible';
    }

    $marcaTiempo = strtotime($fecha);

    return $marcaTiempo === false
        ? 'No disponible'
        : date('d/m/Y H:i', $marcaTiempo);
}

function redirigirSolicitudRol(): void
{
    header(
        'Location: ' . RUTA_WEB . '/Funciones/solicitar_rol.php',
        true,
        303
    );
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $csrfRecibido = $_POST['csrf_token'] ?? '';

    if (
        !is_string($csrfRecibido)
        || !verificarCSRF($csrfRecibido)
    ) {
        $_SESSION['flash_solicitud_rol'] = [
            'tipo' => 'error',
            'mensaje' => 'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
        ];
        redirigirSolicitudRol();
    }

    $idRolRecibido = $_POST['rol_id'] ?? null;
    $idRol = is_scalar($idRolRecibido)
        ? filter_var(
            $idRolRecibido,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        )
        : false;

    $motivoRecibido = $_POST['motivo'] ?? '';
    $motivo = is_string($motivoRecibido)
        ? trim($motivoRecibido)
        : '';

    $aceptaNormasRecibido = $_POST['acepta_normas'] ?? '';
    $aceptaNormas = is_string($aceptaNormasRecibido)
        && $aceptaNormasRecibido === '1';

    $temasRecibidos = $_POST['temas_interes'] ?? [];
    $temasInvalidos = !is_array($temasRecibidos);
    $temasSeleccionados = [];

    if (is_array($temasRecibidos)) {
        foreach ($temasRecibidos as $temaRecibido) {
            $idTema = is_scalar($temaRecibido)
                ? filter_var(
                    $temaRecibido,
                    FILTER_VALIDATE_INT,
                    ['options' => ['min_range' => 1]]
                )
                : false;

            if ($idTema === false) {
                $temasInvalidos = true;
                break;
            }

            $temasSeleccionados[] = (int)$idTema;
        }
    }

    $temasSeleccionados = array_values(
        array_unique($temasSeleccionados)
    );

    $tipoFlash = 'error';
    $mensajeFlash = '';

    if ($idRol === false) {
        $mensajeFlash = 'El rol solicitado no es válido.';
    } elseif (mb_strlen($motivo, 'UTF-8') < 10) {
        $mensajeFlash = 'Explica tu solicitud con al menos 10 caracteres.';
    } elseif (mb_strlen($motivo, 'UTF-8') > 2000) {
        $mensajeFlash = 'El motivo no puede superar los 2,000 caracteres.';
    } elseif ($temasInvalidos) {
        $mensajeFlash = 'La selección de temas contiene datos no válidos.';
    } elseif ($temasSeleccionados === []) {
        $mensajeFlash = 'Selecciona al menos un tema de interés.';
    } elseif (!$aceptaNormas) {
        $mensajeFlash = 'Debes aceptar las normas editoriales para enviar la solicitud.';
    } else {
        $idRol = (int)$idRol;
        $mysqli->begin_transaction();

        try {
            $bloqueoUsuario = $mysqli->prepare(
                "SELECT estatus
                 FROM usuario
                 WHERE id_usr = ?
                 LIMIT 1
                 FOR UPDATE"
            );

            $bloqueoUsuario->bind_param('i', $idUsuario);
            $bloqueoUsuario->execute();
            $usuario = $bloqueoUsuario
                ->get_result()
                ->fetch_assoc();
            $bloqueoUsuario->close();

            if (!$usuario || $usuario['estatus'] !== 'activo') {
                throw new DomainException(
                    'La cuenta debe estar activa para solicitar un rol.'
                );
            }

            $consultaRol = $mysqli->prepare(
                "SELECT id_rol
                 FROM roles
                 WHERE id_rol = ?
                   AND LOWER(nombre) = 'autor'
                 LIMIT 1"
            );

            $consultaRol->bind_param('i', $idRol);
            $consultaRol->execute();
            $rol = $consultaRol->get_result()->fetch_assoc();
            $consultaRol->close();

            if (!$rol) {
                throw new DomainException(
                    'El rol solicitado no está disponible.'
                );
            }

            $rolesVigentes = obtenerRolesActuales($mysqli);

            if (in_array('autor', $rolesVigentes, true)) {
                throw new DomainException(
                    'Tu cuenta ya cuenta con el rol de autor.'
                );
            }

            $consultaPendiente = $mysqli->prepare(
                "SELECT id_solicitud
                 FROM solicitudes_rol
                 WHERE usr_id = ?
                   AND rol_id = ?
                   AND estatus = 'pendiente'
                 LIMIT 1"
            );

            $consultaPendiente->bind_param(
                'ii',
                $idUsuario,
                $idRol
            );
            $consultaPendiente->execute();
            $solicitudExistente = $consultaPendiente
                ->get_result()
                ->fetch_assoc();
            $consultaPendiente->close();

            if ($solicitudExistente) {
                throw new DomainException(
                    'Ya tienes una solicitud pendiente para ese rol.'
                );
            }

            $resultadoCategorias = $mysqli->query(
                "SELECT id_categoria
                 FROM categorias
                 WHERE activa = 1"
            );

            $categoriasActivas = array_map(
                'intval',
                array_column(
                    $resultadoCategorias->fetch_all(MYSQLI_ASSOC),
                    'id_categoria'
                )
            );

            if (array_diff($temasSeleccionados, $categoriasActivas) !== []) {
                throw new DomainException(
                    'Uno o más temas ya no están disponibles. Actualiza la página e inténtalo nuevamente.'
                );
            }

            $insertarSolicitud = $mysqli->prepare(
                "INSERT INTO solicitudes_rol
                    (
                        usr_id,
                        rol_id,
                        motivo,
                        acepta_normas,
                        version_normas,
                        fecha_aceptacion
                    )
                 VALUES (?, ?, ?, 1, ?, CURRENT_TIMESTAMP)"
            );

            $insertarSolicitud->bind_param(
                'iiss',
                $idUsuario,
                $idRol,
                $motivo,
                $versionNormas
            );
            $insertarSolicitud->execute();
            $idSolicitud = (int)$mysqli->insert_id;
            $insertarSolicitud->close();

            $insertarTema = $mysqli->prepare(
                "INSERT INTO solicitudes_rol_temas
                    (id_solicitud, id_categoria)
                 VALUES (?, ?)"
            );

            foreach ($temasSeleccionados as $idCategoria) {
                $insertarTema->bind_param(
                    'ii',
                    $idSolicitud,
                    $idCategoria
                );
                $insertarTema->execute();
            }

            $insertarTema->close();
            $mysqli->commit();

            $tipoFlash = 'exito';
            $mensajeFlash = 'Tu solicitud de rol de autor fue enviada para revisión.';
        } catch (DomainException $error) {
            $mysqli->rollback();
            $mensajeFlash = $error->getMessage();
        } catch (mysqli_sql_exception $error) {
            $mysqli->rollback();
            error_log(
                'Error al crear solicitud de rol: '
                . $error->getMessage()
            );
            $mensajeFlash = 'No se pudo guardar la solicitud. Inténtalo nuevamente.';
        }
    }

    $_SESSION['flash_solicitud_rol'] = [
        'tipo' => $tipoFlash,
        'mensaje' => $mensajeFlash
    ];

    if ($tipoFlash !== 'exito') {
        $_SESSION['flash_solicitud_rol']['form'] = [
            'motivo' => $motivo,
            'temas' => $temasSeleccionados,
            'acepta_normas' => $aceptaNormas
        ];
    }

    redirigirSolicitudRol();
}

$consultaRolAutor = $mysqli->prepare(
    "SELECT id_rol, nombre
     FROM roles
     WHERE LOWER(nombre) = 'autor'
     LIMIT 1"
);

$consultaRolAutor->execute();
$rolAutor = $consultaRolAutor->get_result()->fetch_assoc();
$consultaRolAutor->close();

$categorias = $mysqli->query(
    "SELECT id_categoria, nombre, descripcion
     FROM categorias
     WHERE activa = 1
     ORDER BY nombre"
)->fetch_all(MYSQLI_ASSOC);

$consultaSolicitudes = $mysqli->prepare(
    "SELECT
        sr.id_solicitud,
        sr.motivo,
        sr.estatus,
        sr.observacion,
        sr.fecha,
        sr.fecha_revision,
        sr.acepta_normas,
        sr.version_normas,
        sr.fecha_aceptacion,
        rol.nombre AS rol,
        revisor.nom_usr AS nombre_revisor
     FROM solicitudes_rol sr
     INNER JOIN roles rol
        ON rol.id_rol = sr.rol_id
     LEFT JOIN usuario revisor
        ON revisor.id_usr = sr.revisado_por
     WHERE sr.usr_id = ?
     ORDER BY sr.fecha DESC, sr.id_solicitud DESC
     LIMIT 50"
);

$consultaSolicitudes->bind_param('i', $idUsuario);
$consultaSolicitudes->execute();
$solicitudes = $consultaSolicitudes
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaSolicitudes->close();

$temasPorSolicitud = [];

$consultaTemas = $mysqli->prepare(
    "SELECT srt.id_solicitud, c.nombre
     FROM solicitudes_rol_temas srt
     INNER JOIN categorias c
        ON c.id_categoria = srt.id_categoria
     INNER JOIN solicitudes_rol sr
        ON sr.id_solicitud = srt.id_solicitud
     WHERE sr.usr_id = ?
     ORDER BY c.nombre"
);

$consultaTemas->bind_param('i', $idUsuario);
$consultaTemas->execute();
$resultadoTemas = $consultaTemas->get_result();

while ($tema = $resultadoTemas->fetch_assoc()) {
    $idSolicitudTema = (int)$tema['id_solicitud'];
    $temasPorSolicitud[$idSolicitudTema][] = $tema['nombre'];
}

$consultaTemas->close();

$flash = $_SESSION['flash_solicitud_rol'] ?? null;
unset($_SESSION['flash_solicitud_rol']);

$formAnterior = is_array($flash['form'] ?? null)
    ? $flash['form']
    : [];

$motivoAnterior = is_string($formAnterior['motivo'] ?? null)
    ? $formAnterior['motivo']
    : '';

$temasAnteriores = is_array($formAnterior['temas'] ?? null)
    ? array_map('intval', $formAnterior['temas'])
    : [];

$aceptaNormasAnterior = ($formAnterior['acepta_normas'] ?? false) === true;

$csrf = generarCSRF();

$rolCabecera = in_array('administrador', $rolesActuales, true)
    ? 'administrador'
    : (
        in_array('autor', $rolesActuales, true)
            ? 'autor'
            : 'visor'
    );

$nombreCabecera = $_SESSION['nom_usr'] ?? 'Mi cuenta';
if (!is_string($nombreCabecera)) {
    $nombreCabecera = 'Mi cuenta';
}

require_once __DIR__ . '/componentes/cabecera.php';

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta
        name="description"
        content="Solicita el rol de autor y consulta el estado de tus solicitudes en Vita Sacra."
    >
    <title>Solicitud de autor | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparSolicitudRol(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreCabecera,
        $rolCabecera,
        'solicitar-rol',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Solicitud de autor</h1>
                <p>
                    Solicita acceso para crear contenido educativo.
                    La aprobación no representa una acreditación médica.
                </p>
            </div>
        </section>

        <?php if (is_array($flash)): ?>
            <div
                class="<?php echo ($flash['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>"
                role="status"
            >
                <?php
                echo escaparSolicitudRol($flash['mensaje'] ?? '');
                ?>
            </div>
        <?php endif; ?>

        <?php if (!in_array('autor', $rolesActuales, true)): ?>
            <section class="seccion-admin">
                <article class="tarjeta-actividad">
                    <h2>Solicitar rol de autor</h2>

                    <?php if (!$rolAutor): ?>
                        <p>
                            El rol de autor no está configurado en la base
                            de datos.
                        </p>
                    <?php elseif ($categorias === []): ?>
                        <p>
                            No hay temas disponibles para seleccionar.
                            Inténtalo más tarde.
                        </p>
                    <?php else: ?>
                        <p>
                            Selecciona los temas sobre los que deseas crear
                            contenido y explica cómo usarás fuentes confiables.
                        </p>

                        <form method="POST">
                            <input
                                type="hidden"
                                name="csrf_token"
                                value="<?php echo escaparSolicitudRol($csrf); ?>"
                            >
                            <input
                                type="hidden"
                                name="rol_id"
                                value="<?php echo (int)$rolAutor['id_rol']; ?>"
                            >

                            <label for="motivo">
                                Motivación para solicitar el rol
                            </label>
                            <textarea
                                id="motivo"
                                name="motivo"
                                rows="5"
                                minlength="10"
                                maxlength="2000"
                                required
                            ><?php echo escaparSolicitudRol($motivoAnterior); ?></textarea>

                            <fieldset>
                                <legend>Temas de interés</legend>
                                <p>
                                    Selecciona uno o más temas relacionados con
                                    el contenido que deseas crear.
                                </p>

                                <?php foreach ($categorias as $categoria): ?>
                                    <?php
                                    $idCategoria = (int)$categoria['id_categoria'];
                                    ?>
                                    <label>
                                        <input
                                            type="checkbox"
                                            name="temas_interes[]"
                                            value="<?php echo $idCategoria; ?>"
                                            <?php
                                            echo in_array(
                                                $idCategoria,
                                                $temasAnteriores,
                                                true
                                            ) ? 'checked' : '';
                                            ?>
                                        >
                                        <?php
                                        echo escaparSolicitudRol(
                                            $categoria['nombre']
                                        );
                                        ?>
                                        <?php if (!empty($categoria['descripcion'])): ?>
                                            — <?php
                                            echo escaparSolicitudRol(
                                                $categoria['descripcion']
                                            );
                                            ?>
                                        <?php endif; ?>
                                    </label>
                                <?php endforeach; ?>
                            </fieldset>

                            <fieldset>
                                <legend>Normas editoriales</legend>
                                <ul>
                                    <li>
                                        El contenido debe ser educativo y
                                        utilizar fuentes confiables.
                                    </li>
                                    <li>
                                        No debe presentarse como diagnóstico,
                                        prescripción ni sustituto de atención
                                        profesional.
                                    </li>
                                    <li>
                                        La aprobación como autor no acredita
                                        formación médica o profesional.
                                    </li>
                                    <li>
                                        Las publicaciones quedan sujetas a
                                        revisión editorial antes de publicarse.
                                    </li>
                                </ul>

                                <label>
                                    <input
                                        type="checkbox"
                                        name="acepta_normas"
                                        value="1"
                                        required
                                        <?php echo $aceptaNormasAnterior ? 'checked' : ''; ?>
                                    >
                                    Acepto las normas editoriales para autores
                                    (versión <?php
                                    echo escaparSolicitudRol($versionNormas);
                                    ?>).
                                </label>
                            </fieldset>

                            <button class="boton" type="submit">
                                Enviar solicitud
                            </button>
                        </form>
                    <?php endif; ?>
                </article>
            </section>
        <?php else: ?>
            <section class="seccion-admin">
                <article class="tarjeta-actividad">
                    <h2>Ya tienes el rol de autor</h2>
                    <p>
                        Puedes gestionar tus borradores desde
                        <a
                            href="<?php
                            echo escaparSolicitudRol(
                                RUTA_WEB . '/Funciones/gestionar_publicaciones.php'
                            );
                            ?>"
                        >Mis publicaciones</a>.
                    </p>
                </article>
            </section>
        <?php endif; ?>

        <section class="seccion-admin">
            <h2>Mis solicitudes</h2>

            <?php if ($solicitudes === []): ?>
                <article class="tarjeta-actividad">
                    <p>Todavía no has enviado solicitudes de rol.</p>
                </article>
            <?php else: ?>
                <div class="actividad-admin">
                    <?php foreach ($solicitudes as $solicitud): ?>
                        <?php
                        $idSolicitud = (int)$solicitud['id_solicitud'];
                        $estadoSolicitud = (string)$solicitud['estatus'];

                        $etiquetasEstado = [
                            'pendiente' => 'Pendiente',
                            'aprobada' => 'Aprobada',
                            'rechazada' => 'Rechazada'
                        ];

                        $temasSolicitud = $temasPorSolicitud[$idSolicitud] ?? [];
                        ?>
                        <article class="tarjeta-actividad">
                            <p>
                                Estado:
                                <strong>
                                    <?php
                                    echo escaparSolicitudRol(
                                        $etiquetasEstado[$estadoSolicitud]
                                            ?? $estadoSolicitud
                                    );
                                    ?>
                                </strong>
                            </p>

                            <h3>
                                Rol solicitado:
                                <?php
                                echo escaparSolicitudRol($solicitud['rol']);
                                ?>
                            </h3>

                            <p>
                                Enviada:
                                <?php
                                echo escaparSolicitudRol(
                                    fechaSolicitudRol($solicitud['fecha'])
                                );
                                ?>
                            </p>

                            <p>
                                Temas:
                                <?php if ($temasSolicitud === []): ?>
                                    No registrados en esta solicitud.
                                <?php else: ?>
                                    <?php
                                    echo escaparSolicitudRol(
                                        implode(', ', $temasSolicitud)
                                    );
                                    ?>
                                <?php endif; ?>
                            </p>

                            <p>
                                Aceptación de normas:
                                <?php
                                echo (int)$solicitud['acepta_normas'] === 1
                                    ? 'Sí'
                                    : 'No registrada';
                                ?>
                            </p>

                            <?php if ($solicitud['acepta_normas']): ?>
                                <p>
                                    Versión aceptada:
                                    <?php
                                    echo escaparSolicitudRol(
                                        $solicitud['version_normas']
                                            ?? 'No disponible'
                                    );
                                    ?>
                                    ·
                                    <?php
                                    echo escaparSolicitudRol(
                                        fechaSolicitudRol(
                                            $solicitud['fecha_aceptacion']
                                        )
                                    );
                                    ?>
                                </p>
                            <?php endif; ?>

                            <h3>Motivación</h3>
                            <p>
                                <?php
                                echo nl2br(
                                    escaparSolicitudRol(
                                        $solicitud['motivo']
                                    )
                                );
                                ?>
                            </p>

                            <?php if ($estadoSolicitud !== 'pendiente'): ?>
                                <p>
                                    Revisión:
                                    <?php
                                    echo escaparSolicitudRol(
                                        fechaSolicitudRol(
                                            $solicitud['fecha_revision']
                                        )
                                    );
                                    ?>
                                </p>

                                <?php if (!empty($solicitud['nombre_revisor'])): ?>
                                    <p>
                                        Revisó:
                                        <?php
                                        echo escaparSolicitudRol(
                                            $solicitud['nombre_revisor']
                                        );
                                        ?>
                                    </p>
                                <?php endif; ?>

                                <?php if (!empty($solicitud['observacion'])): ?>
                                    <h3>Observación</h3>
                                    <p>
                                        <?php
                                        echo nl2br(
                                            escaparSolicitudRol(
                                                $solicitud['observacion']
                                            )
                                        );
                                        ?>
                                    </p>
                                <?php endif; ?>
                            <?php endif; ?>
                        </article>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
        </section>
    </main>

    <footer class="pie-admin">
        <p>Vita Sacra · Solicitudes de rol.</p>
    </footer>

    <script
        src="<?php echo escaparSolicitudRol(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>