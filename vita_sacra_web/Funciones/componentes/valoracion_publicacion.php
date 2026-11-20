<?php

function vitaSacraEscaparValoracion($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function vitaSacraRenderValoracion(
    mysqli $mysqli,
    int $idBlog,
    ?int $idUsuario,
    string $csrf
): void {
    $consultaPromedio = $mysqli->prepare(
        "SELECT
            COUNT(*) AS total,
            AVG(estrellas) AS promedio
         FROM valoraciones
         WHERE blog_id = ?"
    );

    $consultaPromedio->bind_param('i', $idBlog);
    $consultaPromedio->execute();
    $metricas = $consultaPromedio
        ->get_result()
        ->fetch_assoc();
    $consultaPromedio->close();

    $total = (int)($metricas['total'] ?? 0);
    $promedio = $total > 0
        ? (float)$metricas['promedio']
        : 0.0;

    $miValoracion = null;

    if ($idUsuario !== null) {
        $consultaMia = $mysqli->prepare(
            "SELECT estrellas
             FROM valoraciones
             WHERE usr_id = ?
               AND blog_id = ?
             LIMIT 1"
        );

        $consultaMia->bind_param('ii', $idUsuario, $idBlog);
        $consultaMia->execute();
        $voto = $consultaMia
            ->get_result()
            ->fetch_assoc();
        $consultaMia->close();

        if ($voto) {
            $miValoracion = (int)$voto['estrellas'];
        }
    }

    $flash = $_SESSION['flash_valoracion'] ?? null;
    unset($_SESSION['flash_valoracion']);
    ?>
    <section
        class="seccion-valoracion"
        id="valoracion"
        aria-labelledby="titulo-valoracion"
    >
        <h2 id="titulo-valoracion">Valoración educativa</h2>

        <?php if (is_array($flash)): ?>
            <div
                class="<?php echo ($flash['tipo'] ?? '') === 'exito' ? 'mensaje-exito' : 'mensaje-error'; ?>"
                role="status"
            >
                <?php
                echo vitaSacraEscaparValoracion(
                    $flash['mensaje'] ?? ''
                );
                ?>
            </div>
        <?php endif; ?>

        <?php if ($total === 0): ?>
            <p class="valoracion-promedio">
                Sin valoraciones
            </p>
        <?php else: ?>
            <p class="valoracion-promedio">
                <strong>
                    <?php echo number_format($promedio, 1, '.', ','); ?> / 5
                </strong>
                <span aria-label="<?php echo $total; ?> valoraciones">
                    · <?php echo $total; ?>
                    <?php echo $total === 1 ? 'valoración' : 'valoraciones'; ?>
                </span>
            </p>

            <div
                class="estrellas-resumen"
                aria-label="Promedio de <?php echo number_format($promedio, 1, '.', ','); ?> estrellas"
            >
                <?php for ($estrella = 1; $estrella <= 5; $estrella++): ?>
                    <span
                        class="<?php echo $estrella <= (int)round($promedio) ? 'activa' : ''; ?>"
                        aria-hidden="true"
                    >★</span>
                <?php endfor; ?>
            </div>
        <?php endif; ?>

        <?php if ($idUsuario !== null): ?>
            <p class="texto-secundario">
                <?php if ($miValoracion !== null): ?>
                    Tu valoración actual: <?php echo $miValoracion; ?> de 5.
                    Puedes cambiarla.
                <?php else: ?>
                    ¿Te resultó útil esta publicación?
                <?php endif; ?>
            </p>

            <form
                class="formulario-valoracion"
                action="<?php echo vitaSacraEscaparValoracion(RUTA_WEB); ?>/Funciones/valorar_publicacion.php"
                method="POST"
            >
                <input
                    type="hidden"
                    name="csrf_token"
                    value="<?php echo vitaSacraEscaparValoracion($csrf); ?>"
                >
                <input
                    type="hidden"
                    name="id_blog"
                    value="<?php echo $idBlog; ?>"
                >

                <fieldset class="escala-estrellas">
                    <legend class="sr-only">Selecciona de 1 a 5 estrellas</legend>

                    <?php for ($estrella = 5; $estrella >= 1; $estrella--): ?>
                        <input
                            type="radio"
                            id="estrella-<?php echo $estrella; ?>"
                            name="estrellas"
                            value="<?php echo $estrella; ?>"
                            <?php echo $miValoracion === $estrella ? 'checked' : ''; ?>
                            required
                        >
                        <label
                            for="estrella-<?php echo $estrella; ?>"
                            title="<?php echo $estrella; ?> estrellas"
                        >★</label>
                    <?php endfor; ?>
                </fieldset>

                <button class="boton" type="submit">
                    <?php echo $miValoracion === null ? 'Registrar valoración' : 'Actualizar valoración'; ?>
                </button>
            </form>

            <small class="texto-secundario">
                Las valoraciones expresan utilidad para el usuario y no
                certifican calidad médica ni rigor profesional.
            </small>
        <?php else: ?>
            <p>
                <a
                    class="boton boton-secundario"
                    href="<?php echo vitaSacraEscaparValoracion(RUTA_WEB); ?>/Funciones/login.php"
                >
                    Inicia sesión para valorar
                </a>
            </p>
        <?php endif; ?>
    </section>
    <?php
}