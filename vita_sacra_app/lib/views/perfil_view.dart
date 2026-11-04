import 'package:flutter/material.dart';

import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'configuracion_view.dart';
import 'guardados_view.dart';
import 'recomendaciones_view.dart';
import 'login_view.dart';

// Pantalla para consultar el perfil del usuario.
class PerfilView extends StatefulWidget {
  const PerfilView({super.key});

  @override
  State<PerfilView> createState() => _PerfilViewState();
}

class _PerfilViewState extends State<PerfilView> {
  // Servicio encargado de la autenticacion.
  final AuthService _authService = AuthService();

  // Informacion del usuario autenticado.
  Usuario? _usuario;

  // Variables de estado.
  bool _cargando = true;
  bool _cerrandoSesion = false;
  bool _requiereSesion = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Consultar los datos del perfil.
    _cargarPerfil();
  }

  // Obtener el perfil del usuario desde FastAPI.
  Future<void> _cargarPerfil() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _cargando = true;
      _requiereSesion = false;
      _error = null;
    });

    try {
      // Verificar que exista una sesion.
      final bool tieneToken = await _authService.tieneToken();

      if (!mounted) {
        return;
      }

      if (!tieneToken) {
        setState(() {
          _usuario = null;
          _requiereSesion = true;
          _cargando = false;
        });

        return;
      }

      // Consultar el perfil mediante AuthService.
      final Usuario usuario = await _authService.obtenerPerfil();

      if (!mounted) {
        return;
      }

      // Guardar los datos recibidos.
      setState(() {
        _usuario = usuario;
        _requiereSesion = false;
        _error = null;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      // Identificar cuando el servidor rechaza la sesion.
      if (error.codigoEstado == 401) {
        setState(() {
          _usuario = null;
          _requiereSesion = true;
          _error = null;
          _cargando = false;
        });

        return;
      }

      // Mostrar el error de comunicacion con FastAPI.
      setState(() {
        _usuario = null;
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      // Mostrar un mensaje para errores inesperados.
      setState(() {
        _usuario = null;
        _error = 'No fue posible cargar el perfil.';
        _cargando = false;
      });
    }
  }

  // Obtener la inicial del nombre.
  String _obtenerInicial(String nombre) {
    final String texto = nombre.trim();

    if (texto.isEmpty) {
      return 'U';
    }

    return texto.substring(0, 1).toUpperCase();
  }

  // Mostrar mensajes informativos.
  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Abrir la biblioteca de publicaciones guardadas.
  void _abrirGuardados() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GuardadosView()),
    );
  }

  // Abrir las recomendaciones personalizadas.
  void _abrirRecomendaciones() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RecomendacionesView()),
    );
  }

  // Abrir la pantalla de configuracion.
  void _abrirConfiguracion() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ConfiguracionView()),
    );
  }

  // Confirmar el cierre de sesion.
  Future<void> _confirmarCerrarSesion() async {
    if (_cerrandoSesion) {
      return;
    }

    // Solicitar confirmacion al usuario.
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cerrar sesion'),
          content: const Text('¿Deseas cerrar tu sesion de Vita Sacra?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Cerrar sesion'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmar != true) {
      return;
    }

    // Ejecutar el cierre de sesion.
    await _cerrarSesion();
  }

  // Cerrar la sesion del usuario.
  Future<void> _cerrarSesion() async {
    if (_cerrandoSesion) {
      return;
    }

    setState(() {
      _cerrandoSesion = true;
    });

    try {
      // Eliminar la sesion mediante AuthService.
      await _authService.cerrarSesion();

      if (!mounted) {
        return;
      }

      // Regresar a la pantalla de inicio de sesion.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginView()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('No fue posible cerrar la sesion.');
    } finally {
      if (mounted) {
        setState(() {
          _cerrandoSesion = false;
        });
      }
    }
  }

  // Construir una fila de informacion personal.
  Widget _crearDato({
    required IconData icono,
    required String etiqueta,
    required String valor,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 22, color: colores.primary),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 5),

              Text(
                valor,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colores.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Construir una opcion de navegacion.
  Widget _crearOpcion({
    required IconData icono,
    required String titulo,
    required VoidCallback onTap,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icono, color: colores.primary),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  // Construir los datos del perfil.
  Widget _construirPerfil() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Recuperar el usuario cargado.
    final Usuario usuario = _usuario!;

    // Obtener los datos principales desde el modelo Usuario.
    final String nombre = usuario.nomUsr;
    final String correo = usuario.mail;

    return RefreshIndicator(
      onRefresh: _cargarPerfil,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Encabezado con el avatar del usuario.
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: colores.primaryContainer,
                  child: Text(
                    _obtenerInicial(nombre),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: colores.onPrimaryContainer,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Nombre del usuario.
                Text(
                  nombre,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: colores.primary,
                  ),
                ),

                const SizedBox(height: 6),

                // Correo electronico.
                Text(
                  correo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colores.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 12),

                // Indicador de cuenta registrada.
                Chip(
                  avatar: const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text(
                    usuario.estaActivo
                        ? 'Cuenta activa'
                        : 'Cuenta ${usuario.estatus}',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 26),

          // Seccion de informacion personal.
          Text(
            'Informacion de la cuenta',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colores.onSurface,
            ),
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colores.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Nombre registrado.
                _crearDato(
                  icono: Icons.person_outline,
                  etiqueta: 'Nombre',
                  valor: nombre,
                ),

                const Divider(height: 28),

                // Correo registrado.
                _crearDato(
                  icono: Icons.email_outlined,
                  etiqueta: 'Correo electronico',
                  valor: correo,
                ),

                const Divider(height: 28),

                // Rol principal del usuario.
                _crearDato(
                  icono: Icons.badge_outlined,
                  etiqueta: 'Rol principal',
                  valor: usuario.nombreRol,
                ),

                // Mostrar la direccion si esta registrada.
                if (usuario.dirUsr != null &&
                    usuario.dirUsr!.trim().isNotEmpty) ...[
                  const Divider(height: 28),

                  _crearDato(
                    icono: Icons.location_on_outlined,
                    etiqueta: 'Direccion',
                    valor: usuario.dirUsr!,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 26),

          // Seccion de actividad personal.
          Text(
            'Mi actividad',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colores.onSurface,
            ),
          ),

          const SizedBox(height: 14),

          // Acceso a publicaciones guardadas.
          _crearOpcion(
            icono: Icons.bookmark_outline,
            titulo: 'Publicaciones guardadas',
            onTap: _abrirGuardados,
          ),

          // Acceso a recomendaciones.
          _crearOpcion(
            icono: Icons.auto_awesome_outlined,
            titulo: 'Mis recomendaciones',
            onTap: _abrirRecomendaciones,
          ),

          // Acceso a configuracion.
          _crearOpcion(
            icono: Icons.settings_outlined,
            titulo: 'Configuracion',
            onTap: _abrirConfiguracion,
          ),

          const SizedBox(height: 20),

          // Boton para cerrar sesion.
          OutlinedButton.icon(
            onPressed: _cerrandoSesion ? null : _confirmarCerrarSesion,
            icon: _cerrandoSesion
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: Text(
              _cerrandoSesion ? 'Cerrando sesion...' : 'Cerrar sesion',
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Construir los mensajes de estado.
  Widget _construirEstado({
    required IconData icono,
    required String titulo,
    required String descripcion,
    bool mostrarReintento = false,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 55, color: colores.primary),

            const SizedBox(height: 14),

            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colores.onSurface,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              descripcion,
              textAlign: TextAlign.center,
              style: TextStyle(color: colores.onSurfaceVariant),
            ),

            if (mostrarReintento) ...[
              const SizedBox(height: 18),

              OutlinedButton.icon(
                onPressed: _cargarPerfil,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Construir el contenido de la pantalla.
  Widget _construirContenido() {
    // Mostrar indicador de carga.
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Mostrar mensaje si no existe una sesion.
    if (_requiereSesion) {
      return _construirEstado(
        icono: Icons.lock_outline,
        titulo: 'Inicia sesion',
        descripcion:
            'Necesitas iniciar sesion para '
            'consultar tu perfil.',
      );
    }

    // Mostrar errores de consulta.
    if (_error != null) {
      return _construirEstado(
        icono: Icons.error_outline,
        titulo: 'No se pudo cargar el perfil',
        descripcion: _error!,
        mostrarReintento: true,
      );
    }

    // Comprobar que existan datos del usuario.
    if (_usuario == null) {
      return _construirEstado(
        icono: Icons.person_off_outlined,
        titulo: 'Perfil no disponible',
        descripcion: 'No se encontro informacion del usuario.',
      );
    }

    // Mostrar los datos del usuario.
    return _construirPerfil();
  }

  @override
  void dispose() {
    // Liberar el servicio de autenticacion.
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior del perfil.
      appBar: AppBar(
        title: const Text('Mi perfil'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar perfil',
            onPressed: _cargando ? null : _cargarPerfil,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      // Contenido del perfil.
      body: SafeArea(child: _construirContenido()),
    );
  }
}
