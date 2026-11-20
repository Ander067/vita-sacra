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

    if (!$resultado) {
        throw new RuntimeException(
            'No fue posible consultar las estadísticas administrativas.'
        );
    }

    $dato = $resultado->fetch_assoc();
    $estadisticas[$clave] = (int)($dato['total'] ?? 0);
    $resultado->free();
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

require_once __DIR__ . '/../Funciones/componentes/cabecera.php';

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
    <meta
        name="description"
        content="Panel administrativo de Vita Sacra para supervisar publicaciones y actividad."
    >
    <title>Administración | Vita Sacra</title>
    <link
        rel="stylesheet"
        href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Recursos/Estilos/styles.css"
    >
</head>
<body>
    <?php
    vitaSacraRenderCabecera(
        $administrador['nom_usr'],
        'administrador',
        'inicio',
        $csrf
    );
    ?>

    <main class="contenedor-admin">
        <section class="presentacion-admin" aria-labelledby="titulo-admin">
            <div>
                <h1 id="titulo-admin">Panel de administración</h1>
                <p>
                    Bienvenido,
                    <?php echo escaparDashboardAdmin($administrador['nom_usr']); ?>.
                    Desde aquí puedes dar seguimiento a la revisión editorial
                    y a la actividad de la comunidad.
                </p>
            </div>

            <span class="insignia-admin">Administración editorial</span>
        </section>

        <section class="seccion-admin" id="estadisticas">
            <div class="encabezado-seccion-admin">
                <div>
                    <h2>Resumen general</h2>
                    <p class="texto-secundario">
                        Estado actual de la plataforma.
                    </p>
                </div>
            </div>

            <div class="estadisticas">
                <article class="tarjeta-estadistica">
                    <p>Usuarios registrados</p>
                    <strong class="valor-estadistica">
                        <?php echo $estadisticas['usuarios']; ?>
                    </strong>
                </article>

                <article class="tarjeta-estadistica">
                    <p>Publicaciones totales</p>
                    <strong class="valor-estadistica">
                        <?php echo $estadisticas['publicaciones']; ?>
                    </strong>
                </article>

                <article class="tarjeta-estadistica">
                    <p>Publicaciones publicadas</p>
                    <strong class="valor-estadistica">
                        <?php echo $estadisticas['publicadas']; ?>
                    </strong>
                </article>

                <a
                    class="tarjeta-estadistica tarjeta-estadistica-destacada tarjeta-estadistica-enlace"
                    href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php"
                >
                    <p>En revisión</p>
                    <strong class="valor-estadistica">
                        <?php echo $estadisticas['revision']; ?>
                    </strong>
                    <small>Ir a la bandeja de revisión</small>
                </a>
            </div>
        </section>

        <section class="seccion-admin" id="revision">
            <div class="encabezado-seccion-admin">
                <div>
                    <h2>Publicaciones pendientes</h2>
                    <p>
                        Propuestas que esperan una decisión editorial.
                    </p>
                </div>

                <a
                    class="boton"
                    href="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Funciones/revisar_publicaciones.php"
                >
                    Abrir bandeja
                </a>
            </div>

            <div class="tabla-contenedor">
                <table class="tabla-admin">
                    <thead>
                        <tr>
                            <th scope="col">Publicación</th>
                            <th scope="col">Autor</th>
                            <th scope="col">Categoría</th>
                            <th scope="col">Tipo</th>
                            <th scope="col">Versión</th>
                            <th scope="col">Enviada</th>
                            <th scope="col">Acción</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if ($publicaciones !== []): ?>
                            <?php foreach ($publicaciones as $publicacion): ?>
                                <tr>
                                    <td>
                                        <strong>
                                            <?php
                                            echo escaparDashboardAdmin(
                                                $publicacion['titulo']
                                            );
                                            ?>
                                        </strong>
                                    </td>
                                    <td>
                                        <?php
                                        echo escaparDashboardAdmin(
                                            $publicacion['nom_usr']
                                        );
                                        ?>
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
                                        <?php
                                        echo escaparDashboardAdmin(
                                            $publicacion['tipo']
                                        );
                                        ?>
                                    </td>
                                    <td>
                                        <?php
                                        echo (int)$publicacion['numero_version'];
                                        ?>
                                    </td>
                                    <td>
                                        <?php
                                        $marcaTiempo = strtotime(
                                            $publicacion['fecha_version']
                                        );

                                        echo $marcaTiempo
                                            ? escaparDashboardAdmin(
                                                date('d/m/Y H:i', $marcaTiempo)
                                            )
                                            : 'Fecha no disponible';
                                        ?>
                                    </td>
                                    <td>
                                        <a
                                            class="acciones-fila"
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
            <div class="encabezado-seccion-admin">
                <div>
                    <h2>Actividad pendiente</h2>
                    <p>
                        Elementos que pueden requerir seguimiento.
                    </p>
                </div>
            </div>

            <div class="actividad-admin">
                <article class="tarjeta-actividad">
                    <p>Comentarios pendientes</p>
                    <strong><?php echo $estadisticas['comentarios']; ?></strong>
                </article>

                <article class="tarjeta-actividad">
                    <p>Reportes pendientes</p>
                    <strong><?php echo $estadisticas['reportes']; ?></strong>
                </article>

                <article class="tarjeta-actividad">
                    <p>Solicitudes de roles</p>
                    <strong><?php echo $estadisticas['solicitudes']; ?></strong>
                </article>

                <article class="tarjeta-actividad">
                    <p>Recursos pendientes</p>
                    <strong><?php echo $estadisticas['recursos']; ?></strong>
                </article>
            </div>
        </section>
    </main>

    <footer class="pie-admin">
        <p>Vita Sacra · Educación y divulgación responsable en salud.</p>
    </footer>

    <script
        src="<?php echo escaparDashboardAdmin(RUTA_WEB); ?>/Recursos/Scripts/tema.js"
        defer
    ></script>
</body>
</html>