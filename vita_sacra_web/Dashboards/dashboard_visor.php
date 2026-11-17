<?php
require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereUsuarioActual($mysqli);

$consulta = $mysqli->prepare(
    "SELECT u.tip_usu,
            EXISTS(
                SELECT 1
                FROM usuario_roles ur
                WHERE ur.usr_id = u.id_usr
                AND ur.rol_id = 3
            ) AS rol_adicional,
            u.nom_usr
     FROM usuario u
     WHERE u.id_usr = ?
     AND u.estatus = 'activo'
     LIMIT 1"
);
$consulta->bind_param('i', $_SESSION['id_usr']);
$consulta->execute();
$usuario = $consulta->get_result()->fetch_assoc();
$consulta->close();

$esAdministrador = $usuario && ((int)$usuario['tip_usu'] === 3 || (int)$usuario['rol_adicional'] === 1);
if ($esAdministrador) {
    header('Location: ' . RUTA_WEB . '/Dashboards/dashboard_admin.php');
    exit;
}

$consulta = $mysqli->prepare("SELECT id_categoria, nombre FROM categorias WHERE activa = 1 ORDER BY nombre ASC");
$consulta->execute();
$resultadoCategorias = $consulta->get_result();
$categorias = [];
while ($categoria = $resultadoCategorias->fetch_assoc()) {
    $categorias[] = $categoria;
}
$consulta->close();

$busqueda = trim($_GET['buscar'] ?? '');
$categoriaSeleccionada = filter_input(INPUT_GET, 'categoria', FILTER_VALIDATE_INT);
if ($categoriaSeleccionada === false || $categoriaSeleccionada === null) {
    $categoriaSeleccionada = 0;
}

$consulta = $mysqli->prepare(
    "SELECT bp.id_blog, bp.titulo, bp.`desc`, bp.img, bp.tipo, bp.fecha_publicacion, bp.advertencia, c.nombre AS categoria
     FROM blog_publico bp
     LEFT JOIN categorias c ON c.id_categoria = bp.categoria_id
     WHERE (? = '' OR bp.titulo LIKE CONCAT('%', ?, '%') OR bp.`desc` LIKE CONCAT('%', ?, '%'))
     AND (? = 0 OR bp.categoria_id = ?)
     ORDER BY bp.fecha_publicacion DESC
     LIMIT 9"
);
$consulta->bind_param('sssii', $busqueda, $busqueda, $busqueda, $categoriaSeleccionada, $categoriaSeleccionada);
$consulta->execute();
$resultadoPublicaciones = $consulta->get_result();
$publicaciones = [];
while ($publicacion = $resultadoPublicaciones->fetch_assoc()) {
    $publicaciones[] = $publicacion;
}
$consulta->close();

$consulta = $mysqli->prepare(
    "SELECT COUNT(*) AS total
     FROM guardados g
     INNER JOIN blog_publico bp ON bp.id_blog = g.blog_id
     WHERE g.usr_id = ?"
);
$consulta->bind_param('i', $_SESSION['id_usr']);
$consulta->execute();
$guardados = $consulta->get_result()->fetch_assoc();
$consulta->close();

$totalGuardados = (int)$guardados['total'];
$csrf = generarCSRF();

function escapar($valor) {
    return htmlspecialchars((string)$valor, ENT_QUOTES, 'UTF-8');
}

function rutaImagenPublicacion($imagen) {
    if (empty($imagen)) {
        return '';
    }
    if (filter_var($imagen, FILTER_VALIDATE_URL)) {
        return $imagen;
    }
    $nombreImagen = basename(str_replace('\\', '/', $imagen));
    return RUTA_WEB . '/Recursos/uploads/publicaciones/' . rawurlencode($nombreImagen);
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Inicio | Vita Sacra</title>
    <link rel="stylesheet" href="<?php echo RUTA_WEB; ?>/Recursos/Estilos/styles.css">
    <link rel="stylesheet" href="<?php echo RUTA_WEB; ?>/Recursos/Estilos/styles_visor.css">
</head>
<body>
    <header class="encabezado-visor">
        <div class="logo-visor">
            <h1>Vita Sacra</h1>
            <p>Informacion para cuidar tu salud</p>
        </div>
        <nav class="navegacion-visor">
            <a href="<?php echo RUTA_WEB; ?>/Dashboards/dashboard_visor.php">Inicio</a>
            <a href="#categorias">Categorias</a>
            <a href="#publicaciones">Publicaciones</a>
        </nav>
        <div class="usuario-visor">
            <span><?php echo escapar($usuario['nom_usr']); ?></span>
            <form action="<?php echo RUTA_WEB; ?>/Conexiones/cerrar_sesion.php" method="POST">
                <input type="hidden" name="csrf_token" value="<?php echo escapar($csrf); ?>">
                <button type="submit">Cerrar sesion</button>
            </form>
        </div>
    </header>

    <main class="contenido-visor">
        <section class="bienvenida-visor">
            <h2>Bienvenido a Vita Sacra</h2>
            <p>Explora informacion sobre salud, consulta publicaciones medicas y descubre contenido que puede ayudarte a conocer mejor diferentes temas relacionados con el bienestar.</p>
            <p>Tienes <strong><?php echo $totalGuardados; ?></strong> publicaciones guardadas.</p>
            <button type="button" class="boton-secundario boton-tema" id="cambiarTema">Cambiar tema</button>
        </section>

        <section class="seccion-visor" id="categorias">
            <h2>Explorar categorias</h2>
            <div class="categorias">
                <?php if (count($categorias) > 0): ?>
                    <?php foreach ($categorias as $categoria): ?>
                        <a class="tarjeta-categoria" href="<?php echo RUTA_WEB; ?>/Dashboards/dashboard_visor.php?categoria=<?php echo (int)$categoria['id_categoria']; ?>#publicaciones">
                            <h3><?php echo escapar($categoria['nombre']); ?></h3>
                        </a>
                    <?php endforeach; ?>
                <?php else: ?>
                    <p class="mensaje-vacio">No hay categorias disponibles actualmente.</p>
                <?php endif; ?>
            </div>
        </section>

        <section class="seccion-visor" id="publicaciones">
            <h2>Publicaciones recientes</h2>
            <form class="buscador-visor" method="GET" action="<?php echo RUTA_WEB; ?>/Dashboards/dashboard_visor.php#publicaciones">
                <input type="text" name="buscar" placeholder="Buscar informacion medica..." value="<?php echo escapar($busqueda); ?>">
                <select name="categoria">
                    <option value="0">Todas las categorias</option>
                    <?php foreach ($categorias as $categoria): ?>
                        <option value="<?php echo (int)$categoria['id_categoria']; ?>" <?php echo $categoriaSeleccionada === (int)$categoria['id_categoria'] ? 'selected' : ''; ?>>
                            <?php echo escapar($categoria['nombre']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>
                <button type="submit">Buscar</button>
            </form>

            <div class="publicaciones">
                <?php if (count($publicaciones) > 0): ?>
                    <?php foreach ($publicaciones as $publicacion): ?>
                        <article class="tarjeta-publicacion">
                            <?php if (!empty($publicacion['img'])): ?>
                                <img src="<?php echo escapar(rutaImagenPublicacion($publicacion['img'])); ?>" alt="<?php echo escapar($publicacion['titulo']); ?>" class="imagen-publicacion">
                            <?php else: ?>
                                <div class="imagen-publicacion"></div>
                            <?php endif; ?>

                            <div class="contenido-publicacion">
                                <span class="etiqueta"><?php echo escapar($publicacion['categoria'] ?? 'General'); ?></span>
                                <h3><?php echo escapar($publicacion['titulo']); ?></h3>
                                <p>
                                    <?php
                                    $descripcion = strip_tags($publicacion['desc'] ?? '');
                                    echo escapar(mb_strimwidth($descripcion, 0, 150, '...'));
                                    ?>
                                </p>
                                <div class="informacion-publicacion">
                                    <span><?php echo escapar($publicacion['tipo']); ?></span>
                                    <span><?php echo escapar($publicacion['fecha_publicacion']); ?></span>
                                </div>
                                <?php if (!empty($publicacion['advertencia'])): ?>
                                    <div class="advertencia">
                                        <strong>Advertencia:</strong>
                                        <?php echo escapar($publicacion['advertencia']); ?>
                                    </div>
                                <?php endif; ?>
                                <a href="<?php echo RUTA_WEB; ?>/Funciones/ver_publicacion.php?id=<?php echo (int)$publicacion['id_blog']; ?>" class="btn-leer-publicacion">Leer publicacion</a>
                            </div>
                        </article>
                    <?php endforeach; ?>
                <?php else: ?>
                    <p class="mensaje-vacio">No se encontraron publicaciones disponibles.</p>
                <?php endif; ?>
            </div>
        </section>
    </main>

    <footer class="pie-visor">
        <p>Vita Sacra | Informacion y divulgacion sobre salud.</p>
        <p>El contenido publicado tiene fines informativos y no sustituye la valoracion de un profesional de la salud.</p>
    </footer>

    <script>
        document.getElementById('cambiarTema').addEventListener('click', function() {
            document.body.classList.toggle('tema-oscuro');
        });
    </script>
</body>
</html>