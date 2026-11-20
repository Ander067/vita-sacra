<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

function escaparFormularioReporte($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function validarDestinoReporte(
    mysqli $mysqli,
    string $tipo,
    int $id,
    ?int $idUsuario
): ?array {
    if ($tipo === 'publicacion') {
        $consulta = $mysqli->prepare(
            "SELECT id_blog, usr_id, titulo
             FROM blog_publico
             WHERE id_blog = ?
             LIMIT 1"
        );

        $consulta->bind_param('i', $id);
        $consulta->execute();
        $destino = $consulta->get_result()->fetch_assoc();
        $consulta->close();

        if (
            !$destino
            || (
                $idUsuario !== null
                && (int)$destino['usr_id'] === $idUsuario
            )
        ) {
            return null;
        }

        return [
            'tipo' => 'publicacion',
            'id' => (int)$destino['id_blog'],
            'id_blog' => (int)$destino['id_blog'],
            'titulo' => $destino['titulo'],
            'descripcion' => 'Publicación'
        ];
    }

    if ($tipo === 'comentario') {
        $consulta = $mysqli->prepare(
            "SELECT
                cp.id_com,
                cp.usr_id,
                cp.blog_id,
                cp.comentario,
                bp.titulo AS titulo_publicacion
             FROM comentarios_publicos cp
             INNER JOIN blog_publico bp
                ON bp.id_blog = cp.blog_id
             WHERE cp.id_com = ?
             LIMIT 1"
        );

        $consulta->bind_param('i', $id);
        $consulta->execute();
        $destino = $consulta->get_result()->fetch_assoc();
        $consulta->close();

        if (
            !$destino
            || (
                $idUsuario !== null
                && (int)$destino['usr_id'] === $idUsuario
            )
        ) {
            return null;
        }

        return [
            'tipo' => 'comentario',
            'id' => (int)$destino['id_com'],
            'id_blog' => (int)$destino['blog_id'],
            'titulo' => $destino['titulo_publicacion'],
            'descripcion' => $destino['comentario']
        ];
    }

    return null;
}

function redirigirFormularioReporte(
    string $tipo,
    int $id,
    string $ancla = ''
): void {
    $url = RUTA_WEB
        . '/Funciones/reportar_contenido.php?'
        . http_build_query([
            'tipo' => $tipo,
            'id' => $id
        ])
        . $ancla;

    header('Location: ' . $url, true, 303);
    exit;
}

$tipoRecibido = $_POST['tipo'] ?? $_GET['tipo'] ?? '';
$tipo = is_string($tipoRecibido) ? $tipoRecibido : '';

$idRecibido = $_POST['id'] ?? $_GET['id'] ?? null;
$idContenido = is_scalar($idRecibido)
    ? filter_var(
        $idRecibido,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    )
    : false;

if (
    !in_array($tipo, ['publicacion', 'comentario'], true)
    || $idContenido === false
) {
    http_response_code(400);
    exit('El contenido indicado para reportar no es válido.');
}

$idUsuario = null;

if (isset($_SESSION['id_usr']) && verificarUsuarioActual($mysqli)) {
    $idUsuario = (int)$_SESSION['id_usr'];
}

$destino = validarDestinoReporte(
    $mysqli,
    $tipo,
    (int)$idContenido,
    $idUsuario
);

if ($destino === null) {
    http_response_code(404);
    exit('El contenido ya no está disponible para reportarse.');
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if ($idUsuario === null) {
        $_SESSION['flash_reporte'] = [
            'tipo' => 'error',
            'mensaje' => 'Inicia sesión para enviar un reporte.'
        ];

        header(
            'Location: ' . RUTA_WEB . '/Funciones/login.php',
            true,
            303
        );
        exit;
    }

    if (!verificarCSRF($_POST['csrf_token'] ?? '')) {
        $_SESSION['flash_reporte'] = [
            'tipo' => 'error',
            'mensaje' => 'La solicitud venció. Inténtalo nuevamente.'
        ];

        redirigirFormularioReporte($tipo, (int)$idContenido);
    }

    $motivoRecibido = $_POST['motivo'] ?? '';
    $motivo = is_string($motivoRecibido)
        ? trim($motivoRecibido)
        : '';

    if ($motivo === '') {
        $_SESSION['flash_reporte'] = [
            'tipo' => 'error',
            'mensaje' => 'Describe brevemente el motivo del reporte.'
        ];

        redirigirFormularioReporte($tipo, (int)$idContenido);
    }

    if (mb_strlen($motivo, 'UTF-8') > 255) {
        $_SESSION['flash_reporte'] = [
            'tipo' => 'error',
            'mensaje' => 'El motivo no puede superar los 255 caracteres.'
        ];

        redirigirFormularioReporte($tipo, (int)$idContenido);
    }

    if ($tipo === 'publicacion') {
        $insertarReporte = $mysqli->prepare(
            "INSERT INTO reportes (usr_id, blog_id, motivo)
             SELECT ?, bp.id_blog, ?
             FROM blog_publico bp
             WHERE bp.id_blog = ?
             LIMIT 1"
        );

        $insertarReporte->bind_param(
            'isi',
            $idUsuario,
            $motivo,
            $idContenido
        );
    } else {
        $insertarReporte = $mysqli->prepare(
            "INSERT INTO reportes (usr_id, com_id, motivo)
             SELECT ?, cp.id_com, ?
             FROM comentarios_publicos cp
             WHERE cp.id_com = ?
             LIMIT 1"
        );

        $insertarReporte->bind_param(
            'isi',
            $idUsuario,
            $motivo,
            $idContenido
        );
    }

    $insertarReporte->execute();
    $insertado = $insertarReporte->affected_rows === 1;
    $insertarReporte->close();

    $_SESSION['flash_reporte'] = $insertado
        ? [
            'tipo' => 'exito',
            'mensaje' => 'El reporte fue enviado al equipo de moderación.'
        ]
        : [
            'tipo' => 'error',
            'mensaje' => 'El contenido ya no está disponible para reportarse.'
        ];

    redirigirFormularioReporte($tipo, (int)$idContenido);
}

$flash = $_SESSION['flash_reporte'] ?? null;
unset($_SESSION['flash_reporte']);

$csrf = generarCSRF();
$logueado = $idUsuario !== null;

require_once __DIR__ . '/componentes/cabecera.php';

$nombreCabecera = 'Invitado';
$rolCabecera = 'visitante';

if ($logueado) {
    $roles = obtenerRolesActuales($mysqli);

    $consultaUsuario = $mysqli->prepare(
        "SELECT nom_usr
         FROM usuario
         WHERE id_usr = ?
           AND estatus = 'activo'
         LIMIT 1"
    );

    $consultaUsuario->bind_param('i', $idUsuario);
    $consultaUsuario->execute();
    $usuario = $consultaUsuario->get_result()->fetch_assoc();
    $consultaUsuario->close();

    if (in_array('administrador', $roles, true)) {
        $rolCabecera = 'administrador';
        $nombreCabecera = $usuario['nom_usr'] ?? 'Administración';
    } elseif (in_array('autor', $roles, true)) {
        $rolCabecera = 'autor';
        $nombreCabecera = $usuario['nom_usr'] ?? 'Autor';
    } else {
        $rolCabecera = 'visor';
        $nombreCabecera = $usuario['nom_usr'] ?? 'Lector';
    }
}

$csrf = generarCSRF();

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta
        name="description"
        content="Envía a Vita Sacra un reporte de contenido para que el equipo de moderación lo revise."
    >
    <title>Reportar contenido | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparFormularioReporte(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $nombreCabecera,
        $rolCabecera,
        'publicaciones',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin">
            <div>
                <h1>Reportar contenido</h1>
                <p>
                    El equipo de Vita Sacra revisará el reporte. No incluyas
                    información médica personal en la descripción.
                </p>
            </div>
            <span class="insignia-admin">
                <?php echo escaparFormularioReporte($destino['descripcion']); ?>
            </span>
        </section>

        <?php if (is_array($flash)): ?>
            <div
                class="<?php echo ($flash['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>"
                role="status"
            >
                <?php
                echo escaparFormularioReporte($flash['mensaje'] ?? '');
                ?>
            </div>
        <?php endif; ?>

        <section class="seccion-admin">
            <div class="tarjeta-actividad">
                <h2>
                    <?php echo escaparFormularioReporte($destino['titulo']); ?>
                </h2>

                <?php if ($tipo === 'comentario'): ?>
                    <blockquote class="bloque-cita">
                        <?php
                        echo nl2br(
                            escaparFormularioReporte(
                                $destino['descripcion']
                            )
                        );
                        ?>
                    </blockquote>
                <?php else: ?>
                    <p>
                        Estás reportando una publicación.
                    </p>
                <?php endif; ?>

                <?php if (!$logueado): ?>
                    <p>
                        Para enviar un reporte debes iniciar sesión.
                    </p>
                    <a
                        class="boton"
                        href="<?php echo escaparFormularioReporte(RUTA_WEB); ?>/Funciones/login.php"
                    >
                        Iniciar sesión
                    </a>
                <?php else: ?>
                    <form method="POST">
                        <input
                            type="hidden"
                            name="csrf_token"
                            value="<?php echo escaparFormularioReporte($csrf); ?>"
                        >
                        <input
                            type="hidden"
                            name="tipo"
                            value="<?php echo escaparFormularioReporte($tipo); ?>"
                        >
                        <input
                            type="hidden"
                            name="id"
                            value="<?php echo (int)$idContenido; ?>"
                        >

                        <label for="motivo">
                            ¿Por qué reportas este contenido?
                        </label>
                        <textarea
                            id="motivo"
                            name="motivo"
                            rows="4"
                            maxlength="255"
                            required
                        ></textarea>
                        <small>
                            Describe el problema de forma breve (máximo 255
                            caracteres).
                        </small>

                        <p>
                            <button class="boton" type="submit">
                                Enviar reporte
                            </button>
                            <a
                                class="boton boton-secundario"
                                href="<?php echo escaparFormularioReporte(RUTA_WEB); ?>/Funciones/ver_publicacion.php?id=<?php echo (int)$destino['id_blog']; ?>#comentarios"
                            >
                                Cancelar
                            </a>
                        </p>
                    </form>
                <?php endif; ?>
            </div>
        </section>
    </main>

    <script
        src="<?php echo escaparFormularioReporte(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>