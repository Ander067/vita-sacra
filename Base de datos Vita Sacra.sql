-- ============================================================
-- VITA SACRA 1.0.0 - ARCA
-- Base de datos compartida para web y movil
-- MariaDB 12.3.2
-- Version revisada para Aplicaciones Web y Moviles
-- ============================================================

create database `VitaSacra_blog_db`
character set utf8mb4
collate utf8mb4_unicode_ci;

use `VitaSacra_blog_db`;

-- ============================================================
-- 1. IDENTIDAD, USUARIOS Y AUTORIZACION
-- ============================================================

create table roles (
    id_rol int auto_increment primary key,
    nombre varchar(40) not null unique
) engine=innodb;

insert into roles (id_rol, nombre)
values
    (1, 'usuario'),
    (2, 'autor'),
    (3, 'administrador'),
    (4, 'anunciante');

-- tip_usu representa exclusivamente el rol principal.
-- Los roles adicionales se registran en usuario_roles.

create table usuario (
    id_usr int auto_increment primary key,
    nom_usr varchar(100) not null,
    mail varchar(150) not null unique,
    pass varchar(255) not null,
    dir_usr varchar(255) null,
    tip_usu int not null default 1,
    estatus enum('activo', 'suspendido', 'inactivo')
        not null default 'activo',
    fecha_registro datetime not null default current_timestamp,
    foreign key (tip_usu) references roles(id_rol)
) engine=innodb;

-- Esta tabla contiene solamente roles adicionales.
-- El rol principal no debe repetirse aqui.

create table usuario_roles (
    usr_id int not null,
    rol_id int not null,
    asignado_por int null,
    fecha datetime not null default current_timestamp,
    primary key (usr_id, rol_id),
    foreign key (usr_id) references usuario(id_usr),
    foreign key (rol_id) references roles(id_rol),
    foreign key (asignado_por) references usuario(id_usr)
) engine=innodb;

create table solicitudes_rol (
    id_solicitud int auto_increment primary key,
    usr_id int not null,
    rol_id int not null,
    motivo text not null,
    estatus enum('pendiente', 'aprobada', 'rechazada')
        not null default 'pendiente',
    revisado_por int null,
    observacion text null,
    fecha datetime not null default current_timestamp,
    fecha_revision datetime null,
    foreign key (usr_id) references usuario(id_usr),
    foreign key (rol_id) references roles(id_rol),
    foreign key (revisado_por) references usuario(id_usr)
) engine=innodb;

create table historial_roles (
    id_cambio int auto_increment primary key,
    usr_id int not null,
    rol_id int not null,
    accion enum('asignar', 'revocar') not null,
    administrador_id int not null,
    fecha datetime not null default current_timestamp,
    foreign key (usr_id) references usuario(id_usr),
    foreign key (rol_id) references roles(id_rol),
    foreign key (administrador_id) references usuario(id_usr)
) engine=innodb;

create table recuperacion_cuenta (
    id_recuperacion int auto_increment primary key,
    usr_id int not null,
    token_hash char(64) not null unique,
    vence_en datetime not null,
    usado_en datetime null,
    foreign key (usr_id) references usuario(id_usr)
) engine=innodb;

create table passkeys (
    id_passkey int auto_increment primary key,
    usr_id int not null,
    credencial_id varbinary(1024) not null,
    credencial_hash binary(32) not null unique,
    clave_publica blob not null,
    contador bigint unsigned not null default 0,
    fecha datetime not null default current_timestamp,
    foreign key (usr_id) references usuario(id_usr)
) engine=innodb;

-- ============================================================
-- 2. CATEGORIAS, ETIQUETAS Y PUBLICACIONES
-- ============================================================

create table categorias (
    id_categoria int auto_increment primary key,
    nombre varchar(100) not null unique,
    descripcion varchar(255) null,
    activa boolean not null default true
) engine=innodb;

create table etiquetas (
    id_etiqueta int auto_increment primary key,
    nombre varchar(80) not null unique
) engine=innodb;

create table plantillas (
    id_plantilla int auto_increment primary key,
    nombre varchar(50) not null unique,
    descripcion varchar(255) null
) engine=innodb;

insert into plantillas (id_plantilla, nombre)
values
    (1, 'clasica'),
    (2, 'divulgativa'),
    (3, 'visual');

create table blog (
    id_blog int auto_increment primary key,
    usr_id int not null,
    categoria_id int not null,
    plantilla_id int not null default 1,
    titulo varchar(200) not null,
    `desc` varchar(500) null,
    img varchar(255) null,
    slug varchar(220) not null unique,
    tipo enum(
        'articulo',
        'ficha_medicamento',
        'ficha_producto'
    ) not null default 'articulo',
    estatus enum(
        'borrador',
        'revision',
        'correccion',
        'rechazado',
        'publicado',
        'oculto'
    ) not null default 'borrador',
    version_publica int null,
    fecha_creacion datetime not null default current_timestamp,
    fecha_publicacion datetime null,
    foreign key (usr_id) references usuario(id_usr),
    foreign key (categoria_id) references categorias(id_categoria),
    foreign key (plantilla_id) references plantillas(id_plantilla),
    index idx_blog_estado (estatus, fecha_publicacion),
    index idx_blog_categoria (categoria_id, estatus),
    fulltext key ft_blog (titulo, `desc`)
) engine=innodb;

create table blog_etiquetas (
    blog_id int not null,
    etiqueta_id int not null,
    primary key (blog_id, etiqueta_id),
    foreign key (blog_id) references blog(id_blog),
    foreign key (etiqueta_id) references etiquetas(id_etiqueta)
) engine=innodb;

create table versiones_blog (
    id_version int auto_increment primary key,
    blog_id int not null,
    numero int not null,
    advertencia text null,
    fecha datetime not null default current_timestamp,
    unique key uq_blog_numero (blog_id, numero),
    foreign key (blog_id) references blog(id_blog)
) engine=innodb;

alter table blog
add constraint fk_blog_version_publica
foreign key (id_blog, version_publica)
references versiones_blog(blog_id, numero);

create table revisiones_blog (
    id_revision int auto_increment primary key,
    version_id int not null,
    administrador_id int not null,
    decision enum(
        'aprobada',
        'correccion',
        'rechazada',
        'oculta'
    ) not null,
    observacion text null,
    fecha datetime not null default current_timestamp,
    foreign key (version_id) references versiones_blog(id_version),
    foreign key (administrador_id) references usuario(id_usr)
) engine=innodb;

create table fuentes (
    id_fuente int auto_increment primary key,
    titulo varchar(255) not null,
    autor varchar(255) null,
    url varchar(1000) null,
    anio smallint unsigned null
) engine=innodb;

create table version_fuentes (
    version_id int not null,
    fuente_id int not null,
    primary key (version_id, fuente_id),
    foreign key (version_id) references versiones_blog(id_version),
    foreign key (fuente_id) references fuentes(id_fuente)
) engine=innodb;

-- ============================================================
-- 3. RECURSOS MULTIMEDIA Y MODELOS 3D
-- ============================================================

create table recursos (
    id_recurso int auto_increment primary key,
    usr_id int not null,
    tipo enum(
        'imagen',
        'pdf',
        'video',
        'gif',
        'sticker',
        'modelo_3d'
    ) not null,
    url varchar(1000) not null,
    mime varchar(100) null,
    titulo varchar(180) null,
    licencia varchar(200) null,
    procedencia varchar(500) null,
    estatus enum(
        'pendiente',
        'aprobado',
        'rechazado',
        'oculto'
    ) not null default 'pendiente',
    revisado_por int null,
    fecha_revision datetime null,
    fecha datetime not null default current_timestamp,
    foreign key (usr_id) references usuario(id_usr),
    foreign key (revisado_por) references usuario(id_usr)
) engine=innodb;

create table bloques_version (
    id_bloque int auto_increment primary key,
    version_id int not null,
    orden smallint unsigned not null,
    tipo enum(
        'titulo',
        'parrafo',
        'lista',
        'cita',
        'imagen',
        'video',
        'modelo_3d'
    ) not null,
    contenido text null,
    recurso_id int null,
    unique key uq_bloque_orden (version_id, orden),
    foreign key (version_id) references versiones_blog(id_version),
    foreign key (recurso_id) references recursos(id_recurso)
) engine=innodb;

create table version_recursos (
    version_id int not null,
    recurso_id int not null,
    orden smallint unsigned not null default 0,
    primary key (version_id, recurso_id),
    foreign key (version_id) references versiones_blog(id_version),
    foreign key (recurso_id) references recursos(id_recurso)
) engine=innodb;

-- ============================================================
-- 4. COMENTARIOS E INTERACCION COMUNITARIA
-- ============================================================

create table comentarios (
    id_com int auto_increment primary key,
    comentario text not null,
    fecha datetime not null default current_timestamp,
    estatus int not null default 1,
    usr_id int not null,
    blog_id int not null,
    com_padre_id int null,
    foreign key (usr_id) references usuario(id_usr),
    foreign key (blog_id) references blog(id_blog),
    unique key uq_com_blog (id_com, blog_id),
    foreign key (com_padre_id, blog_id)
        references comentarios(id_com, blog_id),
    check (estatus in (0, 1, 2, 3)),
    index idx_comentarios_blog (blog_id, estatus, fecha)
) engine=innodb;

create table comentario_recursos (
    com_id int not null,
    recurso_id int not null,
    primary key (com_id, recurso_id),
    foreign key (com_id) references comentarios(id_com),
    foreign key (recurso_id) references recursos(id_recurso)
) engine=innodb;

create table valoraciones (
    usr_id int not null,
    blog_id int not null,
    estrellas tinyint not null,
    primary key (usr_id, blog_id),
    check (estrellas between 1 and 5),
    foreign key (usr_id) references usuario(id_usr),
    foreign key (blog_id) references blog(id_blog)
) engine=innodb;

create table guardados (
    usr_id int not null,
    blog_id int not null,
    fecha datetime not null default current_timestamp,
    primary key (usr_id, blog_id),
    foreign key (usr_id) references usuario(id_usr),
    foreign key (blog_id) references blog(id_blog)
) engine=innodb;

create table intereses (
    usr_id int not null,
    categoria_id int not null,
    primary key (usr_id, categoria_id),
    foreign key (usr_id) references usuario(id_usr),
    foreign key (categoria_id) references categorias(id_categoria)
) engine=innodb;

create table preferencias (
    usr_id int primary key,
    tema enum('claro', 'oscuro', 'automatico')
        not null default 'automatico',
    foreign key (usr_id) references usuario(id_usr)
) engine=innodb;

create table reportes (
    id_reporte int auto_increment primary key,
    usr_id int not null,
    blog_id int null,
    com_id int null,
    motivo varchar(255) not null,
    estatus enum(
        'pendiente',
        'resuelto',
        'descartado'
    ) not null default 'pendiente',
    administrador_id int null,
    resolucion text null,
    fecha datetime not null default current_timestamp,
    check ((blog_id is not null) <> (com_id is not null)),
    foreign key (usr_id) references usuario(id_usr),
    foreign key (blog_id) references blog(id_blog),
    foreign key (com_id) references comentarios(id_com),
    foreign key (administrador_id) references usuario(id_usr)
) engine=innodb;

create table terminos_moderacion (
    id_termino int auto_increment primary key,
    expresion varchar(150) not null unique,
    accion enum(
        'marcar',
        'censurar',
        'bloquear'
    ) not null default 'marcar',
    activo boolean not null default true
) engine=innodb;

create table evaluaciones_moderacion (
    id_evaluacion int auto_increment primary key,
    com_id int null,
    version_id int null,
    resultado enum(
        'limpio',
        'marcado',
        'censurado',
        'bloqueado'
    ) not null,
    detalle varchar(500) null,
    fecha datetime not null default current_timestamp,
    check ((com_id is not null) <> (version_id is not null)),
    foreign key (com_id) references comentarios(id_com),
    foreign key (version_id) references versiones_blog(id_version)
) engine=innodb;

-- ============================================================
-- 5. ESTABLECIMIENTOS, PROMOCIONES Y PAGOS
-- ============================================================

create table establecimientos (
    id_establecimiento int auto_increment primary key,
    solicitante_id int not null,
    nombre varchar(180) not null,
    tipo varchar(80) not null,
    descripcion text null,
    direccion varchar(300) not null,
    latitud decimal(10,7) null,
    longitud decimal(10,7) null,
    telefono varchar(30) null,
    sitio_web varchar(500) null,
    estatus enum(
        'pendiente',
        'aprobado',
        'rechazado',
        'oculto'
    ) not null default 'pendiente',
    administrador_id int null,
    fecha_revision datetime null,
    foreign key (solicitante_id) references usuario(id_usr),
    foreign key (administrador_id) references usuario(id_usr),
    check (latitud is null or latitud between -90 and 90),
    check (longitud is null or longitud between -180 and 180)
) engine=innodb;

create table espacios_promocionales (
    id_espacio int auto_increment primary key,
    nombre varchar(100) not null unique,
    precio decimal(10,2) not null,
    dias smallint unsigned not null,
    activo boolean not null default true,
    check (precio >= 0 and dias > 0)
) engine=innodb;

create table promociones (
    id_promocion int auto_increment primary key,
    anunciante_id int not null,
    establecimiento_id int null,
    espacio_id int not null,
    recurso_id int null,
    titulo varchar(150) not null,
    url_destino varchar(1000) null,
    estatus enum(
        'pendiente',
        'aprobada',
        'rechazada',
        'activa',
        'finalizada'
    ) not null default 'pendiente',
    administrador_id int null,
    fecha_inicio datetime null,
    fecha_fin datetime null,
    foreign key (anunciante_id) references usuario(id_usr),
    foreign key (establecimiento_id)
        references establecimientos(id_establecimiento),
    foreign key (espacio_id)
        references espacios_promocionales(id_espacio),
    foreign key (recurso_id) references recursos(id_recurso),
    foreign key (administrador_id) references usuario(id_usr),
    check (
        fecha_fin is null
        or fecha_inicio is null
        or fecha_fin > fecha_inicio
    )
) engine=innodb;

-- PayPal se utiliza para aportaciones y promociones.
-- No se registran compras de medicamentos.
-- Los identificadores de orden y captura son unicos.
-- Un pago completado requiere captura y fecha confirmada.

create table pagos (
    id_pago int auto_increment primary key,
    usr_id int not null,
    promocion_id int null,
    tipo enum('aportacion', 'promocion') not null,
    paypal_order_id varchar(150) not null unique,
    paypal_capture_id varchar(150) null unique,
    monto decimal(10,2) not null,
    moneda char(3) not null default 'MXN',
    entorno enum('sandbox', 'produccion')
        not null default 'sandbox',
    estatus enum(
        'creado',
        'aprobado',
        'completado',
        'cancelado',
        'fallido',
        'reembolsado'
    ) not null default 'creado',
    fecha datetime not null default current_timestamp,
    fecha_confirmacion datetime null,
    fecha_actualizacion datetime not null
        default current_timestamp
        on update current_timestamp,
    check (monto > 0),
    check (
        (tipo = 'aportacion' and promocion_id is null)
        or
        (tipo = 'promocion' and promocion_id is not null)
    ),
    check (
        estatus not in ('completado', 'reembolsado')
        or (
            paypal_capture_id is not null
            and fecha_confirmacion is not null
        )
    ),
    foreign key (usr_id) references usuario(id_usr),
    foreign key (promocion_id) references promociones(id_promocion),
    index idx_pagos_usuario (usr_id, fecha),
    index idx_pagos_estado (estatus, fecha)
) engine=innodb;

-- Los eventos de PayPal permiten registrar notificaciones.
-- paypal_event_id evita procesar dos veces el mismo evento.
-- La autenticidad de cada webhook se verifica desde PHP.

create table eventos_pago (
    id_evento bigint auto_increment primary key,
    paypal_event_id varchar(150) not null unique,
    pago_id int null,
    tipo_evento varchar(120) not null,
    recibido_en datetime not null default current_timestamp,
    procesado_en datetime null,
    resultado enum(
        'pendiente',
        'procesado',
        'ignorado',
        'error'
    ) not null default 'pendiente',
    foreign key (pago_id) references pagos(id_pago),
    index idx_eventos_estado (resultado, recibido_en)
) engine=innodb;

-- ============================================================
-- 6. VISTAS DE CONSULTA PUBLICA
-- ============================================================

create or replace view blog_publico as
select
    b.id_blog,
    b.usr_id,
    b.categoria_id,
    b.titulo,
    b.`desc`,
    b.img,
    b.slug,
    b.tipo,
    b.fecha_publicacion,
    v.advertencia,
    v.id_version
from blog b
join versiones_blog v
    on v.blog_id = b.id_blog
    and v.numero = b.version_publica
where b.estatus = 'publicado';

create or replace view comentarios_publicos as
select
    c.id_com,
    c.blog_id,
    c.usr_id,
    c.comentario,
    c.fecha,
    c.com_padre_id
from comentarios c
join blog b
    on b.id_blog = c.blog_id
where c.estatus = 1
and b.estatus = 'publicado';

create or replace view establecimientos_publicos as
select
    id_establecimiento,
    nombre,
    tipo,
    descripcion,
    direccion,
    latitud,
    longitud,
    telefono,
    sitio_web
from establecimientos
where estatus = 'aprobado';

-- ============================================================
-- 7. VALIDACION DE ROLES PRINCIPALES Y ADICIONALES
-- ============================================================

-- Los siguientes triggers impiden repetir el rol principal
-- dentro de la tabla de roles adicionales.
-- Tambien impiden cambiar el rol principal a uno que
-- ya este registrado como adicional.

delimiter $$

create trigger validar_usuario_rol_insert
before insert on usuario_roles
for each row
begin
    declare rol_principal int;

    select tip_usu
    into rol_principal
    from usuario
    where id_usr = new.usr_id;

    if new.rol_id = rol_principal then
        signal sqlstate '45000'
        set message_text =
            'El rol adicional no puede ser el rol principal';
    end if;
end$$

create trigger validar_usuario_rol_update
before update on usuario_roles
for each row
begin
    declare rol_principal int;

    select tip_usu
    into rol_principal
    from usuario
    where id_usr = new.usr_id;

    if new.rol_id = rol_principal then
        signal sqlstate '45000'
        set message_text =
            'El rol adicional no puede ser el rol principal';
    end if;
end$$

create trigger validar_rol_principal_update
before update on usuario
for each row
begin
    if new.tip_usu <> old.tip_usu then
        if exists (
            select 1
            from usuario_roles
            where usr_id = new.id_usr
            and rol_id = new.tip_usu
        ) then
            signal sqlstate '45000'
            set message_text =
                'El nuevo rol principal ya existe como adicional';
        end if;
    end if;
end$$

delimiter ;

-- ============================================================
-- 8. COMPROBACION DE LA BASE DE DATOS
-- ============================================================

select database() as base_datos_actual;

select count(*) as total_tablas
from information_schema.tables
where table_schema = 'VitaSacra_blog_db'
and table_type = 'BASE TABLE';

select count(*) as total_vistas
from information_schema.views
where table_schema = 'VitaSacra_blog_db';

select count(*) as total_triggers
from information_schema.triggers
where trigger_schema = 'VitaSacra_blog_db';

show tables;

show triggers;

select id_rol, nombre
from roles
order by id_rol;

select id_plantilla, nombre
from plantillas
order by id_plantilla;