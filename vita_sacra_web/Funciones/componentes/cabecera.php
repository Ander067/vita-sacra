<?php

function vitaSacraEscaparCabecera($valor): string
{
    return htmlspecialchars(
        (string)$valor,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function vitaSacraRenderCabecera(
    string $nombreUsuario,
    string $rol,
    string $paginaActual,
    string $csrf
): void {
    $base = rtrim(RUTA_WEB, '/');

    $menus = [
        'administrador' => [
            ['id' => 'inicio', 'texto' => 'Administración', 'ruta' => '/Dashboards/dashboard_admin.php'],
            ['id' => 'crear', 'texto' => 'Crear publicación', 'ruta' => '/Funciones/publicaciones.php'],
            ['id' => 'usuarios', 'texto' => 'Usuarios y roles', 'ruta' => '/Funciones/gestionar_usuarios.php'],
            ['id' => 'solicitudes-rol', 'texto' => 'Solicitudes de rol', 'ruta' => '/Funciones/revisar_solicitudes_rol.php'],
            ['id' => 'revision', 'texto' => 'Revisión editorial', 'ruta' => '/Funciones/revisar_publicaciones.php'],
            ['id' => 'comentarios', 'texto' => 'Comentarios', 'ruta' => '/Funciones/moderar_comentarios.php'],
            ['id' => 'reportes', 'texto' => 'Reportes', 'ruta' => '/Funciones/gestionar_reportes.php'],
            ['id' => 'gestionar', 'texto' => 'Publicaciones', 'ruta' => '/Funciones/gestionar_publicaciones.php'],
            ['id' => 'directorio', 'texto' => 'Directorio', 'ruta' => '/Funciones/establecimientos.php']
        ],
        'autor' => [
            ['id' => 'inicio', 'texto' => 'Mi panel', 'ruta' => '/Dashboards/dashboard_autor.php'],
            ['id' => 'crear', 'texto' => 'Crear borrador', 'ruta' => '/Funciones/publicaciones.php'],
            ['id' => 'gestionar', 'texto' => 'Mis publicaciones', 'ruta' => '/Funciones/gestionar_publicaciones.php'],
            ['id' => 'solicitar-rol', 'texto' => 'Solicitar rol', 'ruta' => '/Funciones/solicitar_rol.php'],
            ['id' => 'visor', 'texto' => 'Explorar', 'ruta' => '/Dashboards/dashboard_visor.php'],
            ['id' => 'directorio', 'texto' => 'Directorio', 'ruta' => '/Funciones/establecimientos.php']
        ],
        'visor' => [
            ['id' => 'inicio', 'texto' => 'Inicio', 'ruta' => '/Dashboards/dashboard_visor.php'],
            ['id' => 'categorias', 'texto' => 'Categorías', 'ruta' => '#categorias'],
            ['id' => 'publicaciones', 'texto' => 'Publicaciones', 'ruta' => '#publicaciones'],
            ['id' => 'directorio', 'texto' => 'Directorio', 'ruta' => '/Funciones/establecimientos.php'],
            ['id' => 'solicitar-rol', 'texto' => 'Solicitar rol', 'ruta' => '/Funciones/solicitar_rol.php']
        ],
        'visitante' => [
            ['id' => 'inicio', 'texto' => 'Inicio', 'ruta' => '/Dashboards/dashboard_visor.php'],
            ['id' => 'categorias', 'texto' => 'Categorías', 'ruta' => '#categorias'],
            ['id' => 'publicaciones', 'texto' => 'Publicaciones', 'ruta' => '#publicaciones'],
            ['id' => 'directorio', 'texto' => 'Directorio', 'ruta' => '/Funciones/establecimientos.php']
        ]
    ];

    if (!isset($menus[$rol])) {
        throw new InvalidArgumentException(
            'Rol de navegación no reconocido.'
        );
    }

    $etiquetasRol = [
        'administrador' => 'Administrador',
        'autor' => 'Autor',
        'visor' => 'Lector',
        'visitante' => 'Explorando como visitante'
    ];

    $logo = $base . '/Recursos/Vita_Sacra/vita_sacra_logo.png';
    $esVisitante = $rol === 'visitante';
    ?>
    <header class="cabecera-global">
        <a
            class="marca-global"
            href="<?php echo vitaSacraEscaparCabecera($base . '/Dashboards/dashboard_visor.php'); ?>"
            aria-label="Vita Sacra, ir al inicio"
        >
            <img
                src="<?php echo vitaSacraEscaparCabecera($logo); ?>"
                alt="Vita Sacra"
                width="130"
                height="86"
            >
        </a>

        <nav class="navegacion-global" aria-label="Navegación principal">
            <?php foreach ($menus[$rol] as $elemento): ?>
                <a
                    href="<?php echo vitaSacraEscaparCabecera($base . $elemento['ruta']); ?>"
                    <?php if ($paginaActual === $elemento['id']): ?>
                        class="activo"
                        aria-current="page"
                    <?php endif; ?>
                >
                    <?php echo vitaSacraEscaparCabecera($elemento['texto']); ?>
                </a>
            <?php endforeach; ?>
        </nav>

        <div class="acciones-global">
            <button
                type="button"
                class="boton boton-secundario boton-tema"
                id="cambiarTema"
                aria-pressed="false"
            >
                Cambiar tema
            </button>

            <?php if ($esVisitante): ?>
                <div class="identidad-global identidad-visitante">
                    <span class="nombre-global">
                        <?php echo vitaSacraEscaparCabecera($nombreUsuario); ?>
                    </span>
                    <span class="rol-global">
                        <?php echo vitaSacraEscaparCabecera($etiquetasRol[$rol]); ?>
                    </span>
                </div>

                <a
                    class="boton boton-secundario"
                    href="<?php echo vitaSacraEscaparCabecera($base . '/Funciones/login.php'); ?>"
                >
                    Iniciar sesión
                </a>
                <a
                    class="boton"
                    href="<?php echo vitaSacraEscaparCabecera($base . '/Funciones/registro.php'); ?>"
                >
                    Crear cuenta
                </a>
            <?php else: ?>
                <details class="menu-cuenta-global">
                    <summary
                        class="identidad-global resumen-cuenta-global"
                        aria-label="Abrir menú de cuenta"
                    >
                        <span class="nombre-global">
                            <?php echo vitaSacraEscaparCabecera($nombreUsuario); ?>
                        </span>
                        <span class="rol-global">
                            <?php echo vitaSacraEscaparCabecera($etiquetasRol[$rol]); ?>
                        </span>
                    </summary>

                    <div class="panel-cuenta-global">
                        <div class="datos-cuenta-global">
                            <strong>
                                <?php echo vitaSacraEscaparCabecera($nombreUsuario); ?>
                            </strong>
                            <span>
                                <?php echo vitaSacraEscaparCabecera($etiquetasRol[$rol]); ?>
                            </span>
                        </div>

                        <form
                            action="<?php echo vitaSacraEscaparCabecera($base . '/Conexiones/cerrar_sesion.php'); ?>"
                            method="POST"
                        >
                            <input
                                type="hidden"
                                name="csrf_token"
                                value="<?php echo vitaSacraEscaparCabecera($csrf); ?>"
                            >
                            <button type="submit" class="boton-cerrar-sesion">
                                Cerrar sesión
                            </button>
                        </form>
                    </div>
                </details>
            <?php endif; ?>
        </div>
    </header>
    <?php
}