<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

date_default_timezone_set('America/Mexico_City');

function campoPostLogin(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';

    return is_string($valor) ? $valor : '';
}

function campoGetLogin(string $nombre): string
{
    $valor = $_GET[$nombre] ?? '';

    return is_string($valor) ? $valor : '';
}

function escaparLogin($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

$mensaje = '';
$tipoMensaje = '';

$accionRecibida = campoGetLogin('accion');
$accion = in_array(
    $accionRecibida,
    ['login', 'recuperar', 'restablecer'],
    true
) ? $accionRecibida : 'login';

if (isset($_SESSION['id_usr'])) {
    requiereUsuarioActual($mysqli);

    header('Location: ' . RUTA_WEB . '/Funciones/inicio.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!verificarCSRF(campoPostLogin('csrf_token'))) {
        $mensaje = 'La solicitud no es válida. Actualiza la página e intenta nuevamente.';
        $tipoMensaje = 'mensaje-error';
    } elseif (isset($_POST['iniciar_sesion'])) {
        $correo = strtolower(trim(campoPostLogin('correo')));
        $contrasena = campoPostLogin('contrasena');

        $claveIntento = hash(
            'sha256',
            $correo . '|' . ($_SERVER['REMOTE_ADDR'] ?? '')
        );

        $consultaIntento = $mysqli->prepare(
            "SELECT intentos, bloqueado_hasta
             FROM intentos_login
             WHERE clave = ?
             LIMIT 1"
        );

        $consultaIntento->bind_param('s', $claveIntento);
        $consultaIntento->execute();
        $datosIntento = $consultaIntento->get_result()->fetch_assoc();
        $consultaIntento->close();

        $bloqueado = $datosIntento
            && $datosIntento['bloqueado_hasta'] !== null
            && strtotime($datosIntento['bloqueado_hasta']) > time();

        if ($bloqueado) {
            $mensaje = 'No fue posible iniciar sesión. Intenta nuevamente más tarde.';
            $tipoMensaje = 'mensaje-error';
        } else {
            $consulta = $mysqli->prepare(
                "SELECT
                    id_usr,
                    nom_usr,
                    mail,
                    pass,
                    tip_usu,
                    estatus,
                    version_sesion
                 FROM usuario
                 WHERE mail = ?
                 LIMIT 1"
            );

            $consulta->bind_param('s', $correo);
            $consulta->execute();
            $usuario = $consulta->get_result()->fetch_assoc();
            $consulta->close();

            $credencialesValidas = $usuario
                && $usuario['estatus'] === 'activo'
                && password_verify($contrasena, $usuario['pass']);

            if ($credencialesValidas) {
                if (
                    defined('PASSWORD_ARGON2ID') &&
                    password_needs_rehash(
                        $usuario['pass'],
                        PASSWORD_ARGON2ID
                    )
                ) {
                    $nuevoHash = password_hash(
                        $contrasena,
                        PASSWORD_ARGON2ID
                    );

                    if ($nuevoHash === false) {
                        error_log(
                            'Vita Sacra: no se pudo actualizar el hash de contraseña.'
                        );
                        $mensaje = 'No fue posible iniciar sesión. Intenta nuevamente.';
                        $tipoMensaje = 'mensaje-error';
                    } else {
                        $idUsuario = (int)$usuario['id_usr'];

                        $actualizar = $mysqli->prepare(
                            "UPDATE usuario
                             SET pass = ?
                             WHERE id_usr = ?"
                        );

                        $actualizar->bind_param('si', $nuevoHash, $idUsuario);
                        $actualizar->execute();
                        $actualizar->close();

                        $usuario['pass'] = $nuevoHash;
                    }
                }

                if ($mensaje === '') {
                    $eliminarIntento = $mysqli->prepare(
                        "DELETE FROM intentos_login
                         WHERE clave = ?"
                    );

                    $eliminarIntento->bind_param('s', $claveIntento);
                    $eliminarIntento->execute();
                    $eliminarIntento->close();

                    if (!session_regenerate_id(true)) {
                        error_log(
                            'Vita Sacra: no se pudo regenerar el identificador de sesión.'
                        );
                        $mensaje = 'No fue posible iniciar sesión. Intenta nuevamente.';
                        $tipoMensaje = 'mensaje-error';
                    } else {
                        regenerarCSRF();

                        $idUsuario = (int)$usuario['id_usr'];
                        $idRolPrincipal = (int)$usuario['tip_usu'];

                        $_SESSION['id_usr'] = $idUsuario;
                        $_SESSION['nom_usr'] = $usuario['nom_usr'];
                        $_SESSION['mail'] = $usuario['mail'];
                        $_SESSION['tip_usu'] = $idRolPrincipal;
                        $_SESSION['version_sesion'] =
                            (int)$usuario['version_sesion'];
                        $_SESSION['ultima_actividad'] = time();
                        $_SESSION['roles'] = [$idRolPrincipal];

                        $consultaRoles = $mysqli->prepare(
                            "SELECT rol_id
                             FROM usuario_roles
                             WHERE usr_id = ?"
                        );

                        $consultaRoles->bind_param('i', $idUsuario);
                        $consultaRoles->execute();
                        $resultadoRoles = $consultaRoles->get_result();

                        while ($rol = $resultadoRoles->fetch_assoc()) {
                            $idRol = (int)$rol['rol_id'];

                            if (!in_array($idRol, $_SESSION['roles'], true)) {
                                $_SESSION['roles'][] = $idRol;
                            }
                        }

                        $consultaRoles->close();

                        header(
                            'Location: ' . RUTA_WEB . '/Funciones/inicio.php',
                            true,
                            303
                        );
                        exit;
                    }
                }
            } else {
                $registrarIntento = $mysqli->prepare(
                    "INSERT INTO intentos_login (clave, intentos)
                     VALUES (?, 1)
                     ON DUPLICATE KEY UPDATE intentos = intentos + 1"
                );

                $registrarIntento->bind_param('s', $claveIntento);
                $registrarIntento->execute();
                $registrarIntento->close();

                $consultarIntentos = $mysqli->prepare(
                    "SELECT intentos
                     FROM intentos_login
                     WHERE clave = ?
                     LIMIT 1"
                );

                $consultarIntentos->bind_param('s', $claveIntento);
                $consultarIntentos->execute();
                $datosIntentos = $consultarIntentos
                    ->get_result()
                    ->fetch_assoc();
                $consultarIntentos->close();

                if (
                    $datosIntentos &&
                    (int)$datosIntentos['intentos'] >= 5
                ) {
                    $bloquear = $mysqli->prepare(
                        "UPDATE intentos_login
                         SET bloqueado_hasta =
                             DATE_ADD(NOW(), INTERVAL 15 MINUTE)
                         WHERE clave = ?"
                    );

                    $bloquear->bind_param('s', $claveIntento);
                    $bloquear->execute();
                    $bloquear->close();
                }

                $mensaje = 'Correo o contraseña incorrectos.';
                $tipoMensaje = 'mensaje-error';
            }
        }
    } elseif (isset($_POST['solicitar_recuperacion'])) {
        $correo = strtolower(trim(campoPostLogin('correo')));

        if (
            $correo !== '' &&
            strlen($correo) <= 150 &&
            filter_var($correo, FILTER_VALIDATE_EMAIL)
        ) {
            $consulta = $mysqli->prepare(
                "SELECT id_usr
                 FROM usuario
                 WHERE mail = ?
                   AND estatus = 'activo'
                 LIMIT 1"
            );

            $consulta->bind_param('s', $correo);
            $consulta->execute();
            $usuario = $consulta->get_result()->fetch_assoc();
            $consulta->close();

            if ($usuario) {
                $token = bin2hex(random_bytes(32));
                $tokenHash = hash('sha256', $token);
                $expiracion = date('Y-m-d H:i:s', time() + 1800);
                $idUsuario = (int)$usuario['id_usr'];

                $guardarToken = $mysqli->prepare(
                    "INSERT INTO recuperacion_password
                     (usr_id, token_hash, expira_en)
                     VALUES (?, ?, ?)"
                );

                $guardarToken->bind_param(
                    'iss',
                    $idUsuario,
                    $tokenHash,
                    $expiracion
                );

                $guardarToken->execute();
                $guardarToken->close();

                $nombreServidor = $_SERVER['SERVER_NAME'] ?? 'localhost';
                $esHttps = !empty($_SERVER['HTTPS'])
                    && $_SERVER['HTTPS'] !== 'off';
                $protocolo = $esHttps ? 'https://' : 'http://';

                $enlace = $protocolo
                    . $nombreServidor
                    . RUTA_WEB
                    . '/Funciones/login.php?accion=restablecer&token='
                    . urlencode($token);

                $asunto = 'Recuperación de contraseña - Vita Sacra';
                $contenido =
                    "Para restablecer tu contraseña ingresa al siguiente enlace:\n\n"
                    . $enlace
                    . "\n\nEste enlace expirará en 30 minutos.";

                $cabeceras = "From: Vita Sacra <gafa060712@gmail.com>";

                if (!mail($correo, $asunto, $contenido, $cabeceras)) {
                    error_log(
                        'Vita Sacra: no se pudo enviar un correo de recuperación.'
                    );
                }
            }
        }

        $mensaje = 'Si el correo está registrado, recibirás instrucciones para recuperar tu contraseña.';
        $tipoMensaje = 'mensaje';
        $accion = 'recuperar';
    } elseif (isset($_POST['restablecer_contrasena'])) {
        $token = campoPostLogin('token');
        $contrasena = campoPostLogin('contrasena');
        $confirmarContrasena =
            campoPostLogin('confirmar_contrasena');

        $longitudContrasena = function_exists('mb_strlen')
            ? mb_strlen($contrasena, 'UTF-8')
            : strlen($contrasena);

        if (!preg_match('/\A[a-f0-9]{64}\z/i', $token)) {
            $mensaje = 'El enlace de recuperación no es válido o ha expirado.';
            $tipoMensaje = 'mensaje-error';
        } elseif (
            $longitudContrasena < 12 ||
            $longitudContrasena > 128
        ) {
            $mensaje = 'La contraseña debe tener entre 12 y 128 caracteres.';
            $tipoMensaje = 'mensaje-error';
        } elseif ($contrasena !== $confirmarContrasena) {
            $mensaje = 'Las contraseñas no coinciden.';
            $tipoMensaje = 'mensaje-error';
        } elseif (!defined('PASSWORD_ARGON2ID')) {
            error_log('Vita Sacra: PHP no tiene habilitado Argon2id.');
            $mensaje = 'El restablecimiento no está disponible en este momento.';
            $tipoMensaje = 'mensaje-error';
        } else {
            $tokenHash = hash('sha256', $token);

            $consultaToken = $mysqli->prepare(
                "SELECT id_recuperacion, usr_id
                 FROM recuperacion_password
                 WHERE token_hash = ?
                   AND expira_en > NOW()
                   AND utilizado = 0
                 LIMIT 1"
            );

            $consultaToken->bind_param('s', $tokenHash);
            $consultaToken->execute();
            $datosToken = $consultaToken->get_result()->fetch_assoc();
            $consultaToken->close();

            if (!$datosToken) {
                $mensaje = 'El enlace de recuperación no es válido o ha expirado.';
                $tipoMensaje = 'mensaje-error';
            } else {
                $nuevoHash = password_hash(
                    $contrasena,
                    PASSWORD_ARGON2ID
                );

                if ($nuevoHash === false) {
                    error_log(
                        'Vita Sacra: no se pudo generar el hash de recuperación.'
                    );
                    $mensaje = 'No fue posible actualizar la contraseña.';
                    $tipoMensaje = 'mensaje-error';
                } else {
                    $mysqli->begin_transaction();

                    try {
                        $idUsuario = (int)$datosToken['usr_id'];
                        $idRecuperacion =
                            (int)$datosToken['id_recuperacion'];

                        $actualizarContrasena = $mysqli->prepare(
                            "UPDATE usuario
                             SET pass = ?,
                                 version_sesion = version_sesion + 1
                             WHERE id_usr = ?"
                        );

                        $actualizarContrasena->bind_param(
                            'si',
                            $nuevoHash,
                            $idUsuario
                        );

                        $actualizarContrasena->execute();
                        $actualizarContrasena->close();

                        $utilizarToken = $mysqli->prepare(
                            "UPDATE recuperacion_password
                             SET utilizado = 1
                             WHERE id_recuperacion = ?"
                        );

                        $utilizarToken->bind_param(
                            'i',
                            $idRecuperacion
                        );

                        $utilizarToken->execute();
                        $utilizarToken->close();

                        $mysqli->commit();

                        $mensaje = 'Tu contraseña se actualizó correctamente. Ya puedes iniciar sesión.';
                        $tipoMensaje = 'mensaje';
                        $accion = 'login';
                    } catch (Throwable $error) {
                        $mysqli->rollback();

                        error_log(
                            'Vita Sacra: error al restablecer contraseña, código '
                            . $error->getCode()
                        );

                        $mensaje = 'No fue posible actualizar la contraseña.';
                        $tipoMensaje = 'mensaje-error';
                    }
                }
            }

            $token = '';
        }
    }
}

$token = '';
$tokenValido = false;

if ($accion === 'restablecer') {
    $token = campoPostLogin('token');

    if ($token === '') {
        $token = campoGetLogin('token');
    }

    if (preg_match('/\A[a-f0-9]{64}\z/i', $token)) {
        $tokenHash = hash('sha256', $token);

        $consultaToken = $mysqli->prepare(
            "SELECT id_recuperacion
             FROM recuperacion_password
             WHERE token_hash = ?
               AND expira_en > NOW()
               AND utilizado = 0
             LIMIT 1"
        );

        $consultaToken->bind_param('s', $tokenHash);
        $consultaToken->execute();
        $tokenValido = $consultaToken->get_result()->num_rows > 0;
        $consultaToken->close();
    }
}

if (campoGetLogin('registro') === '1') {
    $mensaje = 'Tu cuenta se registró correctamente. Ya puedes iniciar sesión.';
    $tipoMensaje = 'mensaje';
    $accion = 'login';
}
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vita Sacra | Acceso</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparLogin(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <main class="contenedor">
        <h1>Vita Sacra</h1>
        <p class="subtitulo">Accede a tu cuenta</p>

        <?php if ($mensaje !== ''): ?>
            <div
                class="<?php echo escaparLogin($tipoMensaje); ?>"
                role="status"
                aria-live="polite"
            >
                <?php echo escaparLogin($mensaje); ?>
            </div>
        <?php endif; ?>

        <?php if ($accion === 'recuperar'): ?>
            <h2>Recuperar contraseña</h2>

            <form
                method="POST"
                action="<?php echo escaparLogin(RUTA_WEB); ?>/Funciones/login.php?accion=recuperar"
            >
                <input
                    type="hidden"
                    name="csrf_token"
                    value="<?php echo escaparLogin(generarCSRF()); ?>"
                >

                <label for="correo">Correo electrónico</label>
                <input
                    type="email"
                    id="correo"
                    name="correo"
                    maxlength="150"
                    autocomplete="email"
                    required
                >

                <button type="submit" name="solicitar_recuperacion">
                    Enviar instrucciones
                </button>
            </form>

            <div class="enlaces">
                <a href="<?php echo escaparLogin(RUTA_WEB); ?>/Funciones/login.php">
                    Volver al inicio de sesión
                </a>
            </div>

        <?php elseif ($accion === 'restablecer'): ?>
            <h2>Restablecer contraseña</h2>

            <?php if ($tokenValido): ?>
                <form
                    method="POST"
                    action="<?php echo escaparLogin(RUTA_WEB); ?>/Funciones/login.php?accion=restablecer"
                >
                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?php echo escaparLogin(generarCSRF()); ?>"
                    >

                    <input
                        type="hidden"
                        name="token"
                        value="<?php echo escaparLogin($token); ?>"
                    >

                    <label for="contrasena">Nueva contraseña</label>
                    <input
                        type="password"
                        id="contrasena"
                        name="contrasena"
                        minlength="12"
                        maxlength="128"
                        autocomplete="new-password"
                        required
                    >

                    <label for="confirmar_contrasena">Confirmar contraseña</label>
                    <input
                        type="password"
                        id="confirmar_contrasena"
                        name="confirmar_contrasena"
                        minlength="12"
                        maxlength="128"
                        autocomplete="new-password"
                        required
                    >

                    <button type="submit" name="restablecer_contrasena">
                        Actualizar contraseña
                    </button>
                </form>
            <?php else: ?>
                <p class="mensaje-error" role="alert">
                    El enlace de recuperación no es válido o ha expirado.
                </p>
            <?php endif; ?>

            <div class="enlaces">
                <a href="<?php echo escaparLogin(RUTA_WEB); ?>/Funciones/login.php">
                    Volver al inicio de sesión
                </a>
            </div>

        <?php else: ?>
            <h2>Iniciar sesión</h2>

            <form
                method="POST"
                action="<?php echo escaparLogin(RUTA_WEB); ?>/Funciones/login.php"
            >
                <input
                    type="hidden"
                    name="csrf_token"
                    value="<?php echo escaparLogin(generarCSRF()); ?>"
                >

                <label for="correo">Correo electrónico</label>
                <input
                    type="email"
                    id="correo"
                    name="correo"
                    maxlength="150"
                    autocomplete="email"
                    required
                >

                <label for="contrasena">Contraseña</label>
                <input
                    type="password"
                    id="contrasena"
                    name="contrasena"
                    maxlength="128"
                    autocomplete="current-password"
                    required
                >

                <button type="submit" name="iniciar_sesion">
                    Ingresar
                </button>
            </form>

            <div class="enlaces">
                <a href="<?php echo escaparLogin(RUTA_WEB); ?>/Funciones/login.php?accion=recuperar">
                    ¿Olvidaste tu contraseña?
                </a>

                <a href="<?php echo escaparLogin(RUTA_WEB); ?>/Funciones/registro.php">
                    Crear una cuenta
                </a>
            </div>
        <?php endif; ?>
    </main>
</body>
</html>