<?php

require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereRol($mysqli, 'administrador');

$idAdministrador = (int)$_SESSION['id_usr'];

$consultaAdministrador = $mysqli->prepare(
    "SELECT nom_usr
     FROM usuario
     WHERE id_usr = ?
       AND estatus = 'activo'
     LIMIT 1"
);

$consultaAdministrador->bind_param('i', $idAdministrador);
$consultaAdministrador->execute();
$administrador = $consultaAdministrador
    ->get_result()
    ->fetch_assoc();
$consultaAdministrador->close();

if (!$administrador) {
    cerrarSesion();
    header('Location: ' . RUTA_WEB . '/Funciones/login.php');
    exit;
}

$consultasEstadisticas = [
    'usuarios' =>
        "SELECT COUNT(*) AS total FROM usuario",
    'publicaciones' =>
        "SELECT COUNT(*) AS total FROM blog",
    'publicadas' =>
        "SELECT COUNT(*) AS total FROM blog WHERE estatus = 'publicado'",
    'revision' =>
        "SELECT COUNT(*) AS total
         FROM blog
         WHERE estatus = 'revision'
           AND version_publica IS NULL",
    'comentarios' =>
        "SELECT COUNT(*) AS total
         FROM comentarios
         WHERE estatus = 2",
    'reportes' =>
        "SELECT COUNT(*) AS total
         FROM reportes
         WHERE estatus = 'pendiente'",
    'solicitudes' =>
        "SELECT COUNT(*) AS total
         FROM solicitudes_rol
         WHERE estatus = 'pendiente'",
    'recursos' =>
        "SELECT COUNT(*) AS total
         FROM recursos
         WHERE estatus = 'pendiente'"
];

$estadisticas = [];

foreach ($consultasEstadisticas as $clave => $sql) {
    $resultado = $mysqli->query($sql);
    $dato = $resultado->fetch_assoc();
    $estadisticas[$clave] = (int)($dato['total'] ?? 0);
}

$consultaPendientes = $mysqli->prepare(
    "SELECT
        b.id_blog,
        b.titulo,
        b.tipo,
        u.nom_usr,
        c.nombre AS categoria,
        v.numero AS numero_version,
        v.fecha AS fecha_version
     FROM blog b
     INNER JOIN usuario u ON u.id_usr = b.usr_id
     LEFT JOIN categorias c ON c.id_categoria = b.categoria_id
     INNER JOIN versiones_blog v
        ON v.blog_id = b.id_blog
       AND v.numero = (
            SELECT MAX(v2.numero)
            FROM versiones_blog v2
            WHERE v2.blog_id = b.id_blog
       )
     WHERE b.estatus = 'revision'
       AND b.version_publica IS NULL
     ORDER BY v.fecha ASC
     LIMIT 8"
);

$consultaPendientes->execute();
$publicaciones = $consultaPendientes
    ->get_result()
    ->fetch_all(MYSQLI_ASSOC);
$consultaPendientes->close();

$csrf = generarCSRF();

function escaparDashboardAdmin($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Panel administrativo | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
    <link
        rel="stylesheet"
        href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Recursos/Estilos/styles_admin.css"
    >
</head>
<body>
    <div class="panel-admin">
        <aside class="menu-lateral">
            <div class="logo-admin">
                <h2>Vita Sacra</h2>
                <p>Panel administrativo</p>
            </div>

            <nav class="navegacion" aria-label="Navegación administrativa">
                <a
                    href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Dashboards/dashboard_admin.php"
                    class="activo"
                >
                    Inicio
                </a>

                <a href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Funciones/publicaciones.php">
                    Crear publicación
                </a>

                <a href="#estadisticas">Estadísticas</a>

                <a href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php">
                    Revisar publicaciones
                    (<?php echo $estadisticas['revision']; ?>)
                </a>

                <a href="#actividad">Actividad pendiente</a>

                <a href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Funciones/gestionar_publicaciones.php">
                    Gestionar publicaciones
                </a>
            </nav>

            <form
                action="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Conexiones/cerrar_sesion.php"
                method="POST"
            >
                <input
                    type="hidden"
                    name="csrf_token"
                    value="<?php echo escaparDashboardAdmin($csrf); ?>"
                >
                <button type="submit" class="boton-secundario">
                    Cerrar sesión
                </button>
            </form>
        </aside>

        <main class="contenido-admin">
            <header class="encabezado-admin">
                <div>
                    <h1>Panel de administración</h1>
                    <p>
                        Bienvenido,
                        <?php echo escaparDashboardAdmin($administrador['nom_usr']); ?>.
                    </p>
                </div>

                <div class="usuario-admin">
                    <span>Administrador</span>
                    <button
                        type="button"
                        class="boton-secundario boton-tema"
                        id="cambiarTema"
                    >
                        Cambiar tema
                    </button>
                </div>
            </header>

            <section class="seccion-admin" id="estadisticas">
                <h2>Resumen general</h2>

                <div class="estadisticas">
                    <article class="tarjeta-estadistica">
                        <p>Usuarios registrados</p>
                        <h3><?php echo $estadisticas['usuarios']; ?></h3>
                    </article>

                    <article class="tarjeta-estadistica">
                        <p>Publicaciones totales</p>
                        <h3><?php echo $estadisticas['publicaciones']; ?></h3>
                    </article>

                    <article class="tarjeta-estadistica">
                        <p>Publicaciones publicadas</p>
                        <h3><?php echo $estadisticas['publicadas']; ?></h3>
                    </article>

                    <article class="tarjeta-estadistica">
                        <p>En revisión</p>
                        <h3><?php echo $estadisticas['revision']; ?></h3>
                    </article>
                </div>
            </section>

            <section class="seccion-admin" id="revision">
                <h2>Publicaciones pendientes de revisión</h2>

                <p>
                    <a href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php">
                        Abrir bandeja de revisión
                    </a>
                </p>

                <div class="tabla-contenedor">
                    <table>
                        <thead>
                            <tr>
                                <th>Título</th>
                                <th>Autor</th>
                                <th>Categoría</th>
                                <th>Tipo</th>
                                <th>Versión</th>
                                <th>Enviada</th>
                                <th>Acción</th>
                            </tr>
                        </thead>

                        <tbody>
                            <?php if ($publicaciones !== []): ?>
                                <?php foreach ($publicaciones as $publicacion): ?>
                                    <tr>
                                        <td>
                                            <?php echo escaparDashboardAdmin($publicacion['titulo']); ?>
                                        </td>
                                        <td>
                                            <?php echo escaparDashboardAdmin($publicacion['nom_usr']); ?>
                                        </td>
                                        <td>
                                            <?php
                                            echo escaparDashboardAdmin(
                                                $publicacion['categoria']
                                                    ?? 'Sin categoría'
                                            );
                                            ?>
                                        </td>
                                        <td>
                                            <?php echo escaparDashboardAdmin($publicacion['tipo']); ?>
                                        </td>
                                        <td>
                                            <?php echo (int)$publicacion['numero_version']; ?>
                                        </td>
                                        <td>
                                            <?php
                                            echo escaparDashboardAdmin(
                                                date(
                                                    'd/m/Y H:i',
                                                    strtotime($publicacion['fecha_version'])
                                                )
                                            );
                                            ?>
                                        </td>
                                        <td>
                                            <a
                                                href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php?id=<?php echo (int)$publicacion['id_blog']; ?>"
                                            >
                                                Revisar
                                            </a>
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            <?php else: ?>
                                <tr>
                                    <td colspan="7" class="mensaje-vacio">
                                        No hay publicaciones pendientes de revisión.
                                    </td>
                                </tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </section>

            <section class="seccion-admin" id="actividad">
                <h2>Actividad pendiente</h2>

                <div class="estadisticas">
                    <article class="tarjeta-estadistica">
                        <p>Comentarios pendientes</p>
                        <h3><?php echo $estadisticas['comentarios']; ?></h3>
                    </article>

                    <article class="tarjeta-estadistica">
                        <p>Reportes pendientes</p>
                        <h3><?php echo $estadisticas['reportes']; ?></h3>
                    </article>

                    <article class="tarjeta-estadistica">
                        <p>Solicitudes de roles</p>
                        <h3><?php echo $estadisticas['solicitudes']; ?></h3>
                    </article>

                    <article class="tarjeta-estadistica">
                        <p>Recursos pendientes</p>
                        <h3><?php echo $estadisticas['recursos']; ?></h3>
                    </article>
                </div>
            </section>
        </main>
    </div>

    <script>
        document
            .getElementById('cambiarTema')
            .addEventListener('click', function () {
                document.body.classList.toggle('tema-oscuro');
            });
    </script>
</body>
</html>