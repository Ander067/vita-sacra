<?php
require_once __DIR__ . '/../Conexiones/auth.php';
require_once __DIR__ . '/../Conexiones/conexion.php';

requiereUsuarioActual($mysqli);

$id_blog = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT);
if (!$id_blog) {
    header("Location: " . RUTA_WEB . "/Dashboards/dashboard_visor.php");
    exit;
}

$sql = "SELECT bp.id_blog, bp.titulo, bp.`desc`, bp.img, bp.tipo, bp.fecha_publicacion, bp.advertencia, bp.id_version, c.nombre AS categoria 
        FROM blog_publico bp 
        LEFT JOIN categorias c ON bp.categoria_id = c.id_categoria 
        WHERE bp.id_blog = ?";
$stmt = $mysqli->prepare($sql);
$stmt->bind_param("i", $id_blog);
$stmt->execute();
$publicacion = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$publicacion) {
    header("Location: " . RUTA_WEB . "/Dashboards/dashboard_visor.php");
    exit;
}

$id_version = $publicacion['id_version'];

$sql = "SELECT b.id_bloque, b.orden, b.tipo, b.contenido, b.recurso_id, r.url AS recurso_url, r.titulo AS recurso_titulo 
        FROM bloques_version b 
        LEFT JOIN recursos r ON b.recurso_id = r.id_recurso 
        WHERE b.version_id = ? 
        ORDER BY b.orden ASC";
$stmt = $mysqli->prepare($sql);
$stmt->bind_param("i", $id_version);
$stmt->execute();
$bloques = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stmt->close();

$sql = "SELECT f.titulo, f.autor, f.url, f.anio 
        FROM version_fuentes vf 
        INNER JOIN fuentes f ON vf.fuente_id = f.id_fuente 
        WHERE vf.version_id = ? 
        ORDER BY f.titulo ASC";
$stmt = $mysqli->prepare($sql);
$stmt->bind_param("i", $id_version);
$stmt->execute();
$fuentes = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stmt->close();

$sql = "SELECT r.tipo, r.url, r.titulo, r.licencia, r.procedencia, vr.orden 
        FROM version_recursos vr 
        INNER JOIN recursos r ON vr.recurso_id = r.id_recurso 
        WHERE vr.version_id = ? 
        ORDER BY vr.orden ASC";
$stmt = $mysqli->prepare($sql);
$stmt->bind_param("i", $id_version);
$stmt->execute();
$recursos = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stmt->close();
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo htmlspecialchars($publicacion['titulo']); ?> | Vita Sacra</title>
    <link rel="stylesheet" href="<?php echo RUTA_WEB; ?>/Recursos/Estilos/styles_visor.css">
</head>
<body>
    <header class="encabezado">
        <div class="contenedor encabezado-contenido">
            <a href="<?php echo RUTA_WEB; ?>/Dashboards/dashboard_visor.php" class="logo">Vita Sacra</a>
            <nav class="navegacion">
                <a href="<?php echo RUTA_WEB; ?>/Dashboards/dashboard_visor.php">Inicio</a>
            </nav>
        </div>
    </header>

    <main class="contenedor detalle-publicacion">
        <a href="<?php echo RUTA_WEB; ?>/Dashboards/dashboard_visor.php" class="enlace-regresar">Volver a publicaciones</a>
        
        <article class="articulo-completo">
            <div class="articulo-encabezado">
                <span class="categoria-publicacion"><?php echo htmlspecialchars($publicacion['categoria'] ?? 'Sin categoria'); ?></span>
                <h1><?php echo htmlspecialchars($publicacion['titulo']); ?></h1>
                <p class="articulo-descripcion"><?php echo htmlspecialchars($publicacion['desc']); ?></p>
                <div class="articulo-metadata">
                    <span><?php echo htmlspecialchars($publicacion['tipo']); ?></span>
                    <span><?php echo !empty($publicacion['fecha_publicacion']) ? date('d/m/Y', strtotime($publicacion['fecha_publicacion'])) : 'Fecha no disponible'; ?></span>
                </div>
            </div>

            <?php if (!empty($publicacion['img'])): ?>
                <?php 
                $imagen = $publicacion['img'];
                if (!filter_var($imagen, FILTER_VALIDATE_URL)) {
                    $imagen = RUTA_WEB . '/' . ltrim($imagen, '/');
                }
                ?>
                <div class="articulo-imagen-principal">
                    <img src="<?php echo htmlspecialchars($imagen); ?>" alt="<?php echo htmlspecialchars($publicacion['titulo']); ?>">
                </div>
            <?php endif; ?>

            <?php if (!empty($publicacion['advertencia'])): ?>
                <div class="advertencia-medica">
                    <strong>Advertencia medica</strong>
                    <p><?php echo htmlspecialchars($publicacion['advertencia']); ?></p>
                </div>
            <?php endif; ?>

            <section class="contenido-articulo">
                <?php if (count($bloques) > 0): ?>
                    <?php foreach ($bloques as $bloque): ?>
                        <?php if ($bloque['tipo'] == 'titulo'): ?>
                            <h2><?php echo htmlspecialchars($bloque['contenido']); ?></h2>
                        <?php elseif ($bloque['tipo'] == 'parrafo'): ?>
                            <p class="bloque-parrafo"><?php echo nl2br(htmlspecialchars($bloque['contenido'])); ?></p>
                        <?php elseif ($bloque['tipo'] == 'lista'): ?>
                            <ul class="bloque-lista">
                                <?php foreach (preg_split('/\r\n|\r|\n/', $bloque['contenido']) as $elemento): ?>
                                    <?php if (trim($elemento) != ''): ?>
                                        <li><?php echo htmlspecialchars($elemento); ?></li>
                                    <?php endif; ?>
                                <?php endforeach; ?>
                            </ul>
                        <?php elseif ($bloque['tipo'] == 'cita'): ?>
                            <blockquote class="bloque-cita"><?php echo nl2br(htmlspecialchars($bloque['contenido'])); ?></blockquote>
                        <?php elseif ($bloque['tipo'] == 'imagen'): ?>
                            <?php 
                            $imagen = !empty($bloque['recurso_url']) ? $bloque['recurso_url'] : $bloque['contenido'];
                            if (!filter_var($imagen, FILTER_VALIDATE_URL)) {
                                $imagen = RUTA_WEB . '/' . ltrim($imagen, '/');
                            }
                            ?>
                            <?php if (!empty($imagen)): ?>
                                <figure class="bloque-imagen">
                                    <img src="<?php echo htmlspecialchars($imagen); ?>" alt="Imagen de la publicacion">
                                    <?php if (!empty($bloque['recurso_titulo'])): ?>
                                        <figcaption><?php echo htmlspecialchars($bloque['recurso_titulo']); ?></figcaption>
                                    <?php endif; ?>
                                </figure>
                            <?php endif; ?>
                        <?php elseif ($bloque['tipo'] == 'video' || $bloque['tipo'] == 'modelo_3d'): ?>
                            <?php $url = !empty($bloque['recurso_url']) ? $bloque['recurso_url'] : $bloque['contenido']; ?>
                            <?php if (!empty($url)): ?>
                                <div class="bloque-recurso">
                                    <a href="<?php echo htmlspecialchars($url); ?>" target="_blank" rel="noopener noreferrer">
                                        <?php echo $bloque['tipo'] == 'video' ? 'Ver video relacionado' : 'Consultar modelo 3D'; ?>
                                    </a>
                                </div>
                            <?php endif; ?>
                        <?php endif; ?>
                    <?php endforeach; ?>
                <?php else: ?>
                    <p>Esta publicacion no cuenta con contenido disponible.</p>
                <?php endif; ?>
            </section>

            <?php if (count($recursos) > 0): ?>
                <section class="seccion-recursos">
                    <h2>Recursos relacionados</h2>
                    <ul>
                        <?php foreach ($recursos as $recurso): ?>
                            <?php 
                            $url = $recurso['url'];
                            if (!filter_var($url, FILTER_VALIDATE_URL)) {
                                $url = RUTA_WEB . '/' . ltrim($url, '/');
                            }
                            ?>
                            <li>
                                <a href="<?php echo htmlspecialchars($url); ?>" target="_blank" rel="noopener noreferrer">
                                    <?php echo htmlspecialchars($recurso['titulo'] ?: 'Consultar recurso'); ?>
                                </a>
                                <?php if (!empty($recurso['licencia'])): ?>
                                    <span>Licencia: <?php echo htmlspecialchars($recurso['licencia']); ?></span>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ul>
                </section>
            <?php endif; ?>

            <?php if (count($fuentes) > 0): ?>
                <section class="seccion-fuentes">
                    <h2>Fuentes de informacion</h2>
                    <ol>
                        <?php foreach ($fuentes as $fuente): ?>
                            <li>
                                <strong><?php echo htmlspecialchars($fuente['titulo']); ?></strong>
                                <?php if (!empty($fuente['autor'])): ?> — <?php echo htmlspecialchars($fuente['autor']); ?><?php endif; ?>
                                <?php if (!empty($fuente['anio'])): ?> (<?php echo htmlspecialchars($fuente['anio']); ?>)<?php endif; ?>
                                <?php if (!empty($fuente['url'])): ?>
                                    <a href="<?php echo htmlspecialchars($fuente['url']); ?>" target="_blank" rel="noopener noreferrer">Consultar fuente</a>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ol>
                </section>
            <?php endif; ?>
        </article>
    </main>

    <footer class="pie-pagina">
        <p>Vita Sacra | Informacion para el cuidado de la salud</p>
    </footer>
</body>
</html>