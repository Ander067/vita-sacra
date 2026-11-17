<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

if (isset($_SESSION['id_usr'])) {
    requiereUsuarioActual($mysqli);

    header('Location: ' . RUTA_WEB . '/Funciones/inicio.php');
    exit;
}

function escaparRegistro($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function campoPostRegistro(string $nombre): string
{
    $valor = $_POST[$nombre] ?? '';

    return is_string($valor) ? $valor : '';
}

$mensaje = '';
$nombre = '';
$correo = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!verificarCSRF($_POST['csrf_token'] ?? '')) {
        $mensaje = 'La solicitud no es válida. Actualiza la página e intenta nuevamente.';
    } else {
        $nombre = trim(campoPostRegistro('nombre'));
        $correo = strtolower(trim(campoPostRegistro('correo')));
        $contrasena = campoPostRegistro('contrasena');
        $confirmar = campoPostRegistro('confirmar');

        if (
            $nombre === '' ||
            $correo === '' ||
            $contrasena === '' ||
            $confirmar === ''
        ) {
            $mensaje = 'Completa todos los campos.';
        } elseif (
            mb_strlen($nombre, 'UTF-8') < 3 ||
            mb_strlen($nombre, 'UTF-8') > 100
        ) {
            $mensaje = 'El nombre debe tener entre 3 y 100 caracteres.';
        } elseif (
            !filter_var($correo, FILTER_VALIDATE_EMAIL) ||
            mb_strlen($correo, 'UTF-8') > 150
        ) {
            $mensaje = 'Ingresa un correo electrónico válido.';
        } elseif (
            mb_strlen($contrasena, 'UTF-8') < 8 ||
            mb_strlen($contrasena, 'UTF-8') > 128
        ) {
            $mensaje = 'La contraseña debe tener entre 8 y 128 caracteres.';
        } elseif ($contrasena !== $confirmar) {
            $mensaje = 'Las contraseñas no coinciden.';
        } elseif (!defined('PASSWORD_ARGON2ID')) {
            error_log('Vita Sacra: PHP no tiene habilitado Argon2id.');
            $mensaje = 'El registro no está disponible en este momento.';
        } else {
            try {
                $nombreRol = 'usuario';

                $consultaRol = $mysqli->prepare(
                    'SELECT id_rol
                     FROM roles
                     WHERE nombre = ?
                     LIMIT 1'
                );
                $consultaRol->bind_param('s', $nombreRol);
                $consultaRol->execute();

                $filaRol = $consultaRol->get_result()->fetch_assoc();
                $consultaRol->close();

                if (!$filaRol) {
                    error_log('Vita Sacra: no está configurado el rol usuario.');
                    $mensaje = 'El registro no está disponible en este momento.';
                } else {
                    $consultaDuplicado = $mysqli->prepare(
                        'SELECT id_usr
                         FROM usuario
                         WHERE LOWER(mail) = ?
                         LIMIT 1'
                    );
                    $consultaDuplicado->bind_param('s', $correo);
                    $consultaDuplicado->execute();

                    $correoExiste =
                        $consultaDuplicado->get_result()->num_rows > 0;

                    $consultaDuplicado->close();

                    if ($correoExiste) {
                        $mensaje =
                            'No fue posible completar el registro. Verifica los datos o utiliza otro correo.';
                    } else {
                        $hash = password_hash(
                            $contrasena,
                            PASSWORD_ARGON2ID
                        );

                        if ($hash === false) {
                            error_log('Vita Sacra: no se pudo generar el hash.');
                            $mensaje =
                                'El registro no está disponible en este momento.';
                        } else {
                            $idRol = (int)$filaRol['id_rol'];

                            $insertar = $mysqli->prepare(
                                "INSERT INTO usuario (
                                    nom_usr,
                                    mail,
                                    pass,
                                    tip_usu,
                                    estatus,
                                    correo_verificado
                                )
                                VALUES (?, ?, ?, ?, 'activo', 0)"
                            );

                            $insertar->bind_param(
                                'sssi',
                                $nombre,
                                $correo,
                                $hash,
                                $idRol
                            );

                            $insertar->execute();
                            $insertar->close();

                            header(
                                'Location: ' .
                                RUTA_WEB .
                                '/Funciones/login.php?registro=1',
                                true,
                                303
                            );
                            exit;
                        }
                    }
                }
            } catch (mysqli_sql_exception $error) {
                if ((int)$error->getCode() === 1062) {
                    $mensaje =
                        'No fue posible completar el registro. Verifica los datos o utiliza otro correo.';
                } else {
                    error_log(
                        'Vita Sacra: error al registrar usuario, codigo ' .
                        $error->getCode()
                    );
                    $mensaje =
                        'No fue posible completar el registro. Intenta nuevamente.';
                }
            }
        }
    }
}

$csrf = generarCSRF();

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Registro | Vita Sacra</title>
    <link rel="stylesheet" href="<?php echo RUTA_WEB; ?>/Recursos/Estilos/styles.css">
</head>
<body>
    <main class="contenedor">
        <h1>Crear cuenta</h1>
        <p class="subtitulo">Vita Sacra</p>

        <?php if ($mensaje !== ''): ?>
            <div class="mensaje mensaje-error" role="alert" aria-live="assertive">
                <?php echo escaparRegistro($mensaje); ?>
            </div>
        <?php endif; ?>

        <form
            method="POST"
            action="<?php echo RUTA_WEB; ?>/Funciones/registro.php"
            id="formularioRegistro"
            novalidate
        >
            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escaparRegistro($csrf); ?>"
            >

            <label for="nombre">Nombre</label>
            <input
                type="text"
                id="nombre"
                name="nombre"
                value="<?php echo escaparRegistro($nombre); ?>"
                minlength="3"
                maxlength="100"
                autocomplete="name"
                required
                aria-describedby="ayudaNombre"
            >
            <small id="ayudaNombre">Escribe entre 3 y 100 caracteres.</small>

            <label for="correo">Correo electrónico</label>
            <input
                type="email"
                id="correo"
                name="correo"
                value="<?php echo escaparRegistro($correo); ?>"
                maxlength="150"
                autocomplete="email"
                required
            >

            <label for="contrasena">Contraseña</label>
            <input
                type="password"
                id="contrasena"
                name="contrasena"
                minlength="8"
                maxlength="128"
                autocomplete="new-password"
                required
                aria-describedby="ayudaContrasena"
            >
            <small id="ayudaContrasena">Debe tener entre 8 y 128 caracteres.</small>

            <label for="confirmar">Confirmar contraseña</label>
            <input
                type="password"
                id="confirmar"
                name="confirmar"
                minlength="8"
                maxlength="128"
                autocomplete="new-password"
                required
            >

            <button type="submit">Registrarme</button>
        </form>

        <noscript>
            <p class="mensaje">
                JavaScript está desactivado; el servidor seguirá validando los datos.
            </p>
        </noscript>

        <div class="enlace">
            ¿Ya tienes una cuenta?
            <a href="<?php echo RUTA_WEB; ?>/Funciones/login.php">
                Iniciar sesión
            </a>
        </div>
    </main>

    <script>
        const formulario = document.getElementById('formularioRegistro');
        const campoNombre = document.getElementById('nombre');
        const campoCorreo = document.getElementById('correo');
        const campoContrasena = document.getElementById('contrasena');
        const campoConfirmar = document.getElementById('confirmar');

        formulario.addEventListener('input', function(evento) {
            if (evento.target instanceof HTMLInputElement) {
                evento.target.setCustomValidity('');
            }
        });

        formulario.addEventListener('submit', function(evento) {
            const campos = [
                campoNombre,
                campoCorreo,
                campoContrasena,
                campoConfirmar
            ];

            campos.forEach(function(campo) {
                campo.setCustomValidity('');
            });

            campoNombre.value = campoNombre.value.trim();
            campoCorreo.value = campoCorreo.value.trim().toLowerCase();

            const longitudNombre = Array.from(campoNombre.value).length;
            const longitudContrasena = Array.from(campoContrasena.value).length;

            if (longitudNombre < 3 || longitudNombre > 100) {
                campoNombre.setCustomValidity(
                    'El nombre debe tener entre 3 y 100 caracteres.'
                );
            }

            if (
                campoCorreo.value === '' ||
                campoCorreo.value.length > 150 ||
                !campoCorreo.checkValidity()
            ) {
                campoCorreo.setCustomValidity(
                    'Ingresa un correo electrónico válido.'
                );
            }

            if (longitudContrasena < 8 || longitudContrasena > 128) {
                campoContrasena.setCustomValidity(
                    'La contraseña debe tener entre 8 y 128 caracteres.'
                );
            }

            if (campoConfirmar.value === '') {
                campoConfirmar.setCustomValidity(
                    'Confirma tu contraseña.'
                );
            } else if (campoContrasena.value !== campoConfirmar.value) {
                campoConfirmar.setCustomValidity(
                    'Las contraseñas no coinciden.'
                );
            }

            if (!formulario.checkValidity()) {
                evento.preventDefault();
                formulario.reportValidity();
            }
        });
    </script>
</body>
</html>