<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereRol($mysqli, 'administrador');

$administradorId = (int)$_SESSION['id_usr'];

function escaparGestionUsuarios($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function obtenerAdministradorActivoRestante(
    mysqli $mysqli,
    int $idExcluido
): int {
    $consulta = $mysqli->prepare(
        "SELECT COUNT(DISTINCT u.id_usr) AS total
         FROM usuario u
         INNER JOIN roles rol_principal
            ON rol_principal.id_rol = u.tip_usu
         WHERE u.estatus = 'activo'
           AND u.id_usr <> ?
           AND (
                rol_principal.nombre = 'administrador'
                OR EXISTS (
                    SELECT 1
                    FROM usuario_roles ur
                    INNER JOIN roles rol_adicional
                        ON rol_adicional.id_rol = ur.rol_id
                    WHERE ur.usr_id = u.id_usr
                      AND rol_adicional.nombre = 'administrador'
                )
           )"
    );

    $consulta->bind_param('i', $idExcluido);
    $consulta->execute();
    $fila = $consulta->get_result()->fetch_assoc();
    $consulta->close();

    return (int)($fila['total'] ?? 0);
}

function cargarUsuarioParaCambio(
    mysqli $mysqli,
    int $idUsuario
): ?array {
    $consulta = $mysqli->prepare(
        "SELECT
            u.id_usr,
            u.tip_usu,
            u.estatus,
            rol.nombre AS rol_principal
         FROM usuario u
         INNER JOIN roles rol
            ON rol.id_rol = u.tip_usu
         WHERE u.id_usr = ?
         LIMIT 1
         FOR UPDATE"
    );

    $consulta->bind_param('i', $idUsuario);
    $consulta->execute();
    $usuario = $consulta->get_result()->fetch_assoc();
    $consulta->close();

    return $usuario ?: null;
}

function registrarCambioRol(
    mysqli $mysqli,
    int $idUsuario,
    int $idRol,
    string $accion,
    int $administradorId
): void {
    $consulta = $mysqli->prepare(
        "INSERT INTO historial_roles
            (usr_id, rol_id, accion, administrador_id)
         VALUES (?, ?, ?, ?)"
    );

    $consulta->bind_param(
        'iisi',
        $idUsuario,
        $idRol,
        $accion,
        $administradorId
    );

    $consulta->execute();
    $consulta->close();
}

function urlGestionUsuarios(
    string $buscar,
    string $estado,
    int $pagina
): string {
    $parametros = [];

    if ($buscar !== '') {
        $parametros['buscar'] = $buscar;
    }

    if ($estado !== '') {
        $parametros['estado'] = $estado;
    }

    if ($pagina > 1) {
        $parametros['pagina'] = $pagina;
    }

    return rtrim(RUTA_WEB, '/')
        . '/Funciones/gestionar_usuarios.php'
        . ($parametros === [] ? '' : '?' . http_build_query($parametros));
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!verificarCSRF($_POST['csrf_token'] ?? '')) {
        $_SESSION['flash_gestion_usuarios'] = [
            'tipo' => 'error',
            'mensaje' => 'La solicitud venció. Actualiza la página e inténtalo nuevamente.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/gestionar_usuarios.php',
            true,
            303
        );
        exit;
    }

    $accionRecibida = $_POST['accion'] ?? '';
    $accion = is_string($accionRecibida) ? $accionRecibida : '';

    $idUsuarioRecibido = $_POST['id_usr'] ?? null;
    $idUsuarioObjetivo = is_scalar($idUsuarioRecibido)
        ? filter_var(
            $idUsuarioRecibido,
            FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]
        )
        : false;

    if (
        !in_array(
            $accion,
            ['suspender', 'activar', 'asignar_rol', 'revocar_rol'],
            true
        )
        || $idUsuarioObjetivo === false
    ) {
        $_SESSION['flash_gestion_usuarios'] = [
            'tipo' => 'error',
            'mensaje' => 'La acción solicitada no es válida.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/gestionar_usuarios.php',
            true,
            303
        );
        exit;
    }

    $idUsuarioObjetivo = (int)$idUsuarioObjetivo;

    if ($idUsuarioObjetivo === $administradorId) {
        $_SESSION['flash_gestion_usuarios'] = [
            'tipo' => 'error',
            'mensaje' => 'No puedes modificar tu propio estado o permisos desde este panel.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/gestionar_usuarios.php',
            true,
            303
        );
        exit;
    }

    $mysqli->begin_transaction();

    try {
        $usuarioObjetivo = cargarUsuarioParaCambio(
            $mysqli,
            $idUsuarioObjetivo
        );

        if ($usuarioObjetivo === null) {
            throw new DomainException('No se encontró la cuenta seleccionada.');
        }

        if ($accion === 'suspender' || $accion === 'activar') {
            $nuevoEstado = $accion === 'suspender'
                ? 'suspendido'
                : 'activo';

            if ($usuarioObjetivo['estatus'] === $nuevoEstado) {
                throw new DomainException(
                    'La cuenta ya tiene ese estado.'
                );
            }

            $esAdministradorObjetivo =
                $usuarioObjetivo['rol_principal'] === 'administrador';

            if (!$esAdministradorObjetivo) {
                $consultaAdminAdicional = $mysqli->prepare(
                    "SELECT EXISTS(
                        SELECT 1
                        FROM usuario_roles ur
                        INNER JOIN roles r
                            ON r.id_rol = ur.rol_id
                        WHERE ur.usr_id = ?
                          AND r.nombre = 'administrador'
                    ) AS es_administrador"
                );

                $consultaAdminAdicional->bind_param(
                    'i',
                    $idUsuarioObjetivo
                );
                $consultaAdminAdicional->execute();
                $filaAdminAdicional = $consultaAdminAdicional
                    ->get_result()
                    ->fetch_assoc();
                $consultaAdminAdicional->close();

                $esAdministradorObjetivo =
                    (int)($filaAdminAdicional['es_administrador'] ?? 0) === 1;
            }

            if (
                $accion === 'suspender'
                && $usuarioObjetivo['estatus'] === 'activo'
                && $esAdministradorObjetivo
                && obtenerAdministradorActivoRestante(
                    $mysqli,
                    $idUsuarioObjetivo
                ) < 1
            ) {
                throw new DomainException(
                    'No se puede suspender al último administrador activo.'
                );
            }

            $actualizarEstado = $mysqli->prepare(
                "UPDATE usuario
                 SET estatus = ?,
                     version_sesion = version_sesion + 1
                 WHERE id_usr = ?"
            );

            $actualizarEstado->bind_param(
                'si',
                $nuevoEstado,
                $idUsuarioObjetivo
            );
            $actualizarEstado->execute();
            $actualizarEstado->close();

            $mysqli->commit();

            $_SESSION['flash_gestion_usuarios'] = [
                'tipo' => 'exito',
                'mensaje' => $nuevoEstado === 'activo'
                    ? 'La cuenta fue reactivada.'
                    : 'La cuenta fue suspendida y sus sesiones quedaron invalidadas.'
            ];
        } else {
            $idRolRecibido = $_POST['rol_id'] ?? null;
            $idRol = is_scalar($idRolRecibido)
                ? filter_var(
                    $idRolRecibido,
                    FILTER_VALIDATE_INT,
                    ['options' => ['min_range' => 1]]
                )
                : false;

            if ($idRol === false) {
                throw new DomainException('El rol seleccionado no es válido.');
            }

            $idRol = (int)$idRol;

            $consultaRol = $mysqli->prepare(
                "SELECT id_rol, nombre
                 FROM roles
                 WHERE id_rol = ?
                 LIMIT 1"
            );

            $consultaRol->bind_param('i', $idRol);
            $consultaRol->execute();
            $rolObjetivo = $consultaRol
                ->get_result()
                ->fetch_assoc();
            $consultaRol->close();

            if (
                !$rolObjetivo
                || $rolObjetivo['nombre'] === 'usuario'
                || $idRol === (int)$usuarioObjetivo['tip_usu']
            ) {
                throw new DomainException(
                    'Solo puedes modificar roles adicionales asignables.'
                );
            }

            $consultaAsignacion = $mysqli->prepare(
                "SELECT 1
                 FROM usuario_roles
                 WHERE usr_id = ?
                   AND rol_id = ?
                 LIMIT 1"
            );

            $consultaAsignacion->bind_param(
                'ii',
                $idUsuarioObjetivo,
                $idRol
            );
            $consultaAsignacion->execute();
            $yaAsignado = $consultaAsignacion
                ->get_result()
                ->fetch_assoc() !== null;
            $consultaAsignacion->close();

            if ($accion === 'asignar_rol') {
                if ($yaAsignado) {
                    throw new DomainException(
                        'Ese rol ya está asignado a la cuenta.'
                    );
                }

                $asignarRol = $mysqli->prepare(
                    "INSERT INTO usuario_roles
                        (usr_id, rol_id, asignado_por)
                     VALUES (?, ?, ?)"
                );

                $asignarRol->bind_param(
                    'iii',
                    $idUsuarioObjetivo,
                    $idRol,
                    $administradorId
                );
                $asignarRol->execute();
                $asignarRol->close();

                registrarCambioRol(
                    $mysqli,
                    $idUsuarioObjetivo,
                    $idRol,
                    'asignar',
                    $administradorId
                );
            } else {
                if (!$yaAsignado) {
                    throw new DomainException(
                        'Ese rol adicional no está asignado a la cuenta.'
                    );
                }

                if (
                    $rolObjetivo['nombre'] === 'administrador'
                    && $usuarioObjetivo['estatus'] === 'activo'
                    && obtenerAdministradorActivoRestante(
                        $mysqli,
                        $idUsuarioObjetivo
                    ) < 1
                ) {
                    throw new DomainException(
                        'No se puede revocar el rol del último administrador activo.'
                    );
                }

                $revocarRol = $mysqli->prepare(
                    "DELETE FROM usuario_roles
                     WHERE usr_id = ?
                       AND rol_id = ?"
                );

                $revocarRol->bind_param(
                    'ii',
                    $idUsuarioObjetivo,
                    $idRol
                );
                $revocarRol->execute();
                $revocado = $revocarRol->affected_rows === 1;
                $revocarRol->close();

                if (!$revocado) {
                    throw new DomainException(
                        'El rol cambió antes de completar la operación.'
                    );
                }

                registrarCambioRol(
                    $mysqli,
                    $idUsuarioObjetivo,
                    $idRol,
                    'revocar',
                    $administradorId
                );
            }

            $invalidarSesiones = $mysqli->prepare(
                "UPDATE usuario
                 SET version_sesion = version_sesion + 1
                 WHERE id_usr = ?"
            );

            $invalidarSesiones->bind_param(
                'i',
                $idUsuarioObjetivo
            );
            $invalidarSesiones->execute();
            $invalidarSesiones->close();

            $mysqli->commit();

            $_SESSION['flash_gestion_usuarios'] = [
                'tipo' => 'exito',
                'mensaje' => $accion === 'asignar_rol'
                    ? 'El rol fue asignado y las sesiones anteriores quedaron invalidadas.'
                    : 'El rol fue revocado y las sesiones anteriores quedaron invalidadas.'
            ];
        }
    } catch (DomainException $error) {
        $mysqli->rollback();

        $_SESSION['flash_gestion_usuarios'] = [
            'tipo' => 'error',
            'mensaje' => $error->getMessage()
        ];
    } catch (mysqli_sql_exception $error) {
        $mysqli->rollback();
        error_log('Error al gestionar usuarios: ' . $error->getMessage());

        $_SESSION['flash_gestion_usuarios'] = [
            'tipo' => 'error',
            'mensaje' => 'No se pudo completar el cambio. Revisa que la cuenta y el rol sigan disponibles.'
        ];
    }

    header(
        'Location: ' . RUTA_WEB . '/Funciones/gestionar_usuarios.php',
        true,
        303
    );
    exit;
}

$flash = $_SESSION['flash_gestion_usuarios'] ?? null;
unset($_SESSION['flash_gestion_usuarios']);

$buscarRecibido = $_GET['buscar'] ?? '';
$buscar = is_string($buscarRecibido)
    ? trim(mb_substr($buscarRecibido, 0, 100, 'UTF-8'))
    : '';

$estadoRecibido = $_GET['estado'] ?? '';
$estado = is_string($estadoRecibido)
    ? $estadoRecibido
    : '';

if (!in_array($estado, ['', 'activo', 'suspendido', 'inactivo'], true)) {
    $estado = '';
}

$paginaRecibida = $_GET['pagina'] ?? '1';
$pagina = is_scalar($paginaRecibida)
    ? filter_var(
        $paginaRecibida,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

if ($pagina === false) {
    $pagina = 1;
}

$usuariosPorPagina = 20;

$consultaTotal = $mysqli->prepare(
    "SELECT COUNT(*) AS total
     FROM usuario u
     WHERE (? = '' OR u.estatus = ?)
       AND (
            ? = ''
            OR u.nom_usr LIKE CONCAT('%', ?, '%')
            OR u.mail LIKE CONCAT('%', ?, '%')
       )"
);

$consultaTotal->bind_param(
    'sssss',
    $estado,
    $estado,
    $buscar,
    $buscar,
    $buscar
);

$consultaTotal->execute();
$datosTotal = $consultaTotal->get_result()->fetch_assoc();
$consultaTotal->close();

$totalUsuarios = (int)($datosTotal['total'] ?? 0);
$totalPaginas = max(
    1,
    (int)ceil($totalUsuarios / $usuariosPorPagina)
);

$pagina = min($pagina, $totalPaginas);
$desplazamiento = ($pagina - 1) * $usuariosPorPagina;

$consultaUsuarios = $mysqli->prepare(
    "SELECT
        u.id_usr,
        u.nom_usr,
        u.mail,
        u.estatus,
        u.fecha_registro,
        u.tip_usu,
        rol_principal.nombre AS rol_principal,
        GROUP_CONCAT(
            DISTINCT CONCAT(rol_adicional.id_rol, '|', rol_adicional.nombre)
            ORDER BY rol_adicional.nombre
            SEPARATOR ','
        ) AS roles_adicionales
     FROM usuario u
     INNER JOIN roles rol_principal
        ON rol_principal.id_rol = u.tip_usu
     LEFT JOIN usuario_roles ur
        ON ur.usr_id = u.id_usr
     LEFT JOIN roles rol_adicional
        ON rol_adicional.id_rol = ur.rol_id
     WHERE (? = '' OR u.estatus = ?)
       AND (
            ? = ''
            OR u.nom_usr LIKE CONCAT('%', ?, '%')
            OR u.mail LIKE CONCAT('%', ?, '%')
       )
     GROUP BY
        u.id_usr,
        u.nom_usr,
        u.mail,
        u.estatus,
        u.fecha_registro,
        u.tip_usu,
        rol_principal.nombre
     ORDER BY u.fecha_registro DESC, u.id_usr DESC
     LIMIT ? OFFSET ?"
);

$consultaUsuarios->bind_param(
    'sssssii',
    $estado,
    $estado,
    $buscar,
    $buscar,
    $buscar,
    $usuariosPorPagina,
    $desplazamiento
);

$consultaUsuarios->execute();
$usuarios = $consultaUsuarios
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaUsuarios->close();

$consultaRoles = $mysqli->prepare(
    "SELECT id_rol, nombre
     FROM roles
     WHERE nombre <> 'usuario'
     ORDER BY nombre ASC"
);

$consultaRoles->execute();
$rolesAsignables = $consultaRoles
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaRoles->close();

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
        content="Administra las cuentas, el estado y los roles adicionales de Vita Sacra."
    >
    <title>Usuarios y roles | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparGestionUsuarios(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        'Administración',
        'administrador',
        'usuarios',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Usuarios y permisos</h1>
                <p>
                    Consulta las cuentas y administra sus roles adicionales.
                    Los cambios de permisos invalidan las sesiones anteriores.
                </p>
            </div>
            <span class="insignia-admin">
                <?php echo $totalUsuarios; ?> cuentas
            </span>
        </section>

        <?php if (is_array($flash)): ?>
            <div
                class="<?php echo ($flash['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>"
                role="status"
            >
                <?php echo escaparGestionUsuarios($flash['mensaje'] ?? ''); ?>
            </div>
        <?php endif; ?>

        <section class="seccion-admin">
            <form
                class="tarjeta-actividad"
                method="GET"
                action="<?php echo escaparGestionUsuarios(RUTA_WEB); ?>/Funciones/gestionar_usuarios.php"
            >
                <div class="buscador-publicaciones">
                    <div>
                        <label for="buscar">Buscar usuario</label>
                        <input
                            id="buscar"
                            type="search"
                            name="buscar"
                            maxlength="100"
                            placeholder="Nombre o correo"
                            value="<?php echo escaparGestionUsuarios($buscar); ?>"
                        >
                    </div>

                    <div>
                        <label for="estado">Estado</label>
                        <select id="estado" name="estado">
                            <option value="">Todos</option>
                            <option
                                value="activo"
                                <?php echo $estado === 'activo' ? 'selected' : ''; ?>
                            >
                                Activo
                            </option>
                            <option
                                value="suspendido"
                                <?php echo $estado === 'suspendido' ? 'selected' : ''; ?>
                            >
                                Suspendido
                            </option>
                            <option
                                value="inactivo"
                                <?php echo $estado === 'inactivo' ? 'selected' : ''; ?>
                            >
                                Inactivo
                            </option>
                        </select>
                    </div>

                    <button class="boton" type="submit">Buscar</button>
                </div>
            </form>
        </section>

        <section class="seccion-admin" aria-label="Cuentas de usuario">
            <?php if ($usuarios === []): ?>
                <div class="tarjeta-actividad">
                    <h2>No hay cuentas para mostrar</h2>
                    <p>Prueba con otros términos o filtros.</p>
                </div>
            <?php else: ?>
                <div class="actividad-admin">
                    <?php foreach ($usuarios as $usuario): ?>
                        <?php
                        $idObjetivo = (int)$usuario['id_usr'];
                        $esCuentaPropia = $idObjetivo === $administradorId;
                        $rolesAdicionales = [];

                        if (!empty($usuario['roles_adicionales'])) {
                            foreach (
                                explode(',', $usuario['roles_adicionales'])
                                as $rolCodificado
                            ) {
                                $partes = explode('|', $rolCodificado, 2);

                                if (count($partes) === 2) {
                                    $rolesAdicionales[] = [
                                        'id' => (int)$partes[0],
                                        'nombre' => $partes[1]
                                    ];
                                }
                            }
                        }

                        $fechaRegistro = strtotime($usuario['fecha_registro']);
                        ?>
                        <article class="tarjeta-actividad">
                            <p>
                                <span class="estado">
                                    <?php
                                    echo escaparGestionUsuarios(
                                        ucfirst($usuario['estatus'])
                                    );
                                    ?>
                                </span>
                                <?php if ($esCuentaPropia): ?>
                                    <span class="etiqueta">Tu cuenta</span>
                                <?php endif; ?>
                            </p>

                            <h2>
                                <?php
                                echo escaparGestionUsuarios($usuario['nom_usr']);
                                ?>
                            </h2>
                            <p>
                                <?php echo escaparGestionUsuarios($usuario['mail']); ?>
                            </p>
                            <p>
                                Rol principal:
                                <strong>
                                    <?php
                                    echo escaparGestionUsuarios(
                                        $usuario['rol_principal']
                                    );
                                    ?>
                                </strong>
                            </p>
                            <p>
                                Registro:
                                <?php
                                echo $fechaRegistro === false
                                    ? 'Fecha no disponible'
                                    : escaparGestionUsuarios(
                                        date('d/m/Y', $fechaRegistro)
                                    );
                                ?>
                            </p>

                            <?php if ($rolesAdicionales !== []): ?>
                                <h3>Roles adicionales</h3>

                                <div class="enlaces">
                                    <?php foreach ($rolesAdicionales as $rolAdicional): ?>
                                        <span class="etiqueta">
                                            <?php
                                            echo escaparGestionUsuarios(
                                                $rolAdicional['nombre']
                                            );
                                            ?>
                                        </span>

                                        <?php if (!$esCuentaPropia): ?>
                                            <form method="POST">
                                                <input
                                                    type="hidden"
                                                    name="csrf_token"
                                                    value="<?php echo escaparGestionUsuarios($csrf); ?>"
                                                >
                                                <input
                                                    type="hidden"
                                                    name="accion"
                                                    value="revocar_rol"
                                                >
                                                <input
                                                    type="hidden"
                                                    name="id_usr"
                                                    value="<?php echo $idObjetivo; ?>"
                                                >
                                                <input
                                                    type="hidden"
                                                    name="rol_id"
                                                    value="<?php echo $rolAdicional['id']; ?>"
                                                >
                                                <p>
                                                    <button
                                                        class="boton boton-secundario"
                                                        type="submit"
                                                    >
                                                        Revocar <?php
                                                        echo escaparGestionUsuarios(
                                                            $rolAdicional['nombre']
                                                        );
                                                        ?>
                                                    </button>
                                                </p>
                                            </form>
                                        <?php endif; ?>
                                    <?php endforeach; ?>
                                </div>
                            <?php else: ?>
                                <p class="texto-secundario">
                                    No tiene roles adicionales.
                                </p>
                            <?php endif; ?>

                            <?php if (!$esCuentaPropia): ?>
                                <form method="POST">
                                    <input
                                        type="hidden"
                                        name="csrf_token"
                                        value="<?php echo escaparGestionUsuarios($csrf); ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="accion"
                                        value="asignar_rol"
                                    >
                                    <input
                                        type="hidden"
                                        name="id_usr"
                                        value="<?php echo $idObjetivo; ?>"
                                    >

                                    <label for="rol-<?php echo $idObjetivo; ?>">
                                        Asignar rol adicional
                                    </label>
                                    <select
                                        id="rol-<?php echo $idObjetivo; ?>"
                                        name="rol_id"
                                        required
                                    >
                                        <option value="">
                                            Selecciona un rol
                                        </option>
                                        <?php foreach ($rolesAsignables as $rol): ?>
                                            <?php
                                            if (
                                                (int)$rol['id_rol']
                                                === (int)$usuario['tip_usu']
                                            ) {
                                                continue;
                                            }
                                            ?>
                                            <option value="<?php echo (int)$rol['id_rol']; ?>">
                                                <?php
                                                echo escaparGestionUsuarios(
                                                    $rol['nombre']
                                                );
                                                ?>
                                            </option>
                                        <?php endforeach; ?>
                                    </select>
                                    <p>
                                        <button class="boton" type="submit">
                                            Asignar rol
                                        </button>
                                    </p>
                                </form>

                                <form method="POST">
                                    <input
                                        type="hidden"
                                        name="csrf_token"
                                        value="<?php echo escaparGestionUsuarios($csrf); ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="id_usr"
                                        value="<?php echo $idObjetivo; ?>"
                                    >

                                    <?php if ($usuario['estatus'] === 'activo'): ?>
                                        <input
                                            type="hidden"
                                            name="accion"
                                            value="suspender"
                                        >
                                        <p>
                                            <button
                                                class="boton boton-secundario"
                                                type="submit"
                                            >
                                                Suspender cuenta
                                            </button>
                                        </p>
                                    <?php else: ?>
                                        <input
                                            type="hidden"
                                            name="accion"
                                            value="activar"
                                        >
                                        <p>
                                            <button class="boton" type="submit">
                                                Reactivar cuenta
                                            </button>
                                        </p>
                                    <?php endif; ?>
                                </form>
                            <?php else: ?>
                                <p class="texto-secundario">
                                    Por seguridad, no puedes cambiar tu propia
                                    cuenta desde esta pantalla.
                                </p>
                            <?php endif; ?>
                        </article>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
        </section>

        <?php if ($totalPaginas > 1): ?>
            <nav class="enlaces" aria-label="Paginación de usuarios">
                <?php if ($pagina > 1): ?>
                    <a
                        class="boton boton-secundario"
                        href="<?php
                        echo escaparGestionUsuarios(
                            urlGestionUsuarios(
                                $buscar,
                                $estado,
                                $pagina - 1
                            )
                        );
                        ?>"
                    >
                        Anterior
                    </a>
                <?php endif; ?>

                <span class="texto-secundario">
                    Página <?php echo $pagina; ?> de <?php echo $totalPaginas; ?>
                </span>

                <?php if ($pagina < $totalPaginas): ?>
                    <a
                        class="boton boton-secundario"
                        href="<?php
                        echo escaparGestionUsuarios(
                            urlGestionUsuarios(
                                $buscar,
                                $estado,
                                $pagina + 1
                            )
                        );
                        ?>"
                    >
                        Siguiente
                    </a>
                <?php endif; ?>
            </nav>
        <?php endif; ?>
    </main>

    <footer class="pie-admin">
        <p>Vita Sacra · Administración de cuentas y permisos.</p>
    </footer>
    <script
        src="<?php echo htmlspecialchars(RUTA_WEB, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>