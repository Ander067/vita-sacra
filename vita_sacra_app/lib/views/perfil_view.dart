import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'configuracion_view.dart';
import 'guardados_view.dart';
import 'login_view.dart';

class PerfilView extends StatefulWidget {
  const PerfilView({super.key});

  @override
  State<PerfilView> createState() => _PerfilViewState();
}

class _PerfilViewState extends State<PerfilView> {
  final AuthService _authService = AuthService();
  final ImagePicker _selectorImagen = ImagePicker();

  Usuario? _usuario;
  bool _cargando = true;
  bool _subiendoFoto = false;
  bool _cerrandoSesion = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final Usuario usuario = await _authService.obtenerPerfil();
      if (!mounted) return;

      setState(() {
        _usuario = usuario;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = 'No fue posible cargar el perfil.';
        _cargando = false;
      });
    }
  }

  Future<void> _seleccionarFoto() async {
    if (_subiendoFoto || _usuario == null) return;

    try {
      final XFile? imagen = await _selectorImagen.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (imagen == null || !mounted) return;

      setState(() {
        _subiendoFoto = true;
      });

      final String rutaFoto = await _authService.subirFotoPerfil(
        rutaArchivo: imagen.path,
      );

      if (!mounted) return;

      setState(() {
        _usuario = _usuario!.copyWith(fotoPerfilUrl: rutaFoto);
      });

      _mostrarMensaje('Foto de perfil actualizada.');
    } on ApiException catch (error) {
      if (mounted) _mostrarMensaje(error.mensaje);
    } catch (error) {
      if (mounted) {
        _mostrarMensaje('No fue posible seleccionar o subir la imagen.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _subiendoFoto = false;
        });
      }
    }
  }

  Uri? _crearUriFoto(String? ruta) {
    if (ruta == null || ruta.trim().isEmpty) return null;

    final Uri? recibida = Uri.tryParse(ruta);
    if (recibida != null && recibida.hasScheme) return recibida;

    return ApiConfig.crearUri(ruta);
  }

  String _obtenerInicial(String nombre) {
    final String limpio = nombre.trim();
    return limpio.isEmpty ? 'U' : limpio.substring(0, 1).toUpperCase();
  }

  Future<void> _abrirConfiguracion() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (context) => const ConfiguracionView()),
    );

    if (mounted) {
      await _cargarPerfil();
    }
  }

  Future<void> _abrirGuardados() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (context) => const GuardadosView()),
    );
  }

  void _mostrarPrivacidad() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacidad y protección de datos'),
        content: const Text(
          'El aviso oficial de privacidad aún no está disponible. '
          'Cuando se integre, se mostrará aquí sin sustituir el documento '
          'oficial por texto provisional.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _mostrarAcercaDe() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acerca de Vita Sacra'),
        content: const Text(
          'Vita Sacra\n'
          'Versión 1.0.0 - Arca\n\n'
          'Plataforma de información y divulgación médica.\n\n'
          'El contenido es informativo y no sustituye la valoración '
          'de un profesional de la salud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarCerrarSesion() async {
    if (_cerrandoSesion) return;

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Deseas cerrar tu sesión de Vita Sacra?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (!mounted || confirmar != true) return;
    await _cerrarSesion();
  }

  Future<void> _cerrarSesion() async {
    if (_cerrandoSesion) return;

    setState(() {
      _cerrandoSesion = true;
    });

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final bool servidorConfirmo = await _authService.cerrarSesion();
      if (!mounted) return;

      Navigator.pushAndRemoveUntil<void>(
        context,
        MaterialPageRoute<void>(builder: (context) => const LoginView()),
        (route) => false,
      );

      if (!servidorConfirmo) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'La sesión se cerró en este dispositivo. El servidor no '
              'confirmó todas las revocaciones; se eliminó la biometría local.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _mostrarMensaje('No fue posible cerrar la sesión.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _cerrandoSesion = false;
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Widget _construirAvatar(Usuario usuario) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final Uri? foto = _crearUriFoto(usuario.fotoPerfilUrl);

    return Semantics(
      button: true,
      label: 'Cambiar foto de perfil',
      child: GestureDetector(
        onTap: _subiendoFoto ? null : _seleccionarFoto,
        child: Stack(
          children: [
            ClipOval(
              child: Container(
                width: 124,
                height: 124,
                color: colores.primaryContainer,
                child: foto == null
                    ? Center(
                        child: Text(
                          _obtenerInicial(usuario.nomUsr),
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: colores.onPrimaryContainer,
                          ),
                        ),
                      )
                    : Image.network(
                        foto.toString(),
                        key: ValueKey(foto.toString()),
                        width: 124,
                        height: 124,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              _obtenerInicial(usuario.nomUsr),
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: colores.onPrimaryContainer,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: 20,
                backgroundColor: colores.primary,
                child: _subiendoFoto
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.camera_alt,
                        color: colores.onPrimary,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _crearOpcion({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required VoidCallback onTap,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: Icon(icono, color: colores.primary),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(descripcion, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  void dispose() {
    _authService.cerrarServicio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      appBar: AppBar(
        title: const Text('Mi perfil'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Configuración',
            onPressed: _abrirConfiguracion,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _cargarPerfil,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (context) => const LoginView(),
                            ),
                            (route) => false,
                          );
                        },
                        child: const Text('Ir a iniciar sesión'),
                      ),
                    ],
                  ),
                ),
              )
            : _usuario == null
            ? const Center(child: Text('Perfil no disponible.'))
            : RefreshIndicator(
                onRefresh: _cargarPerfil,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 28),
                    Center(child: _construirAvatar(_usuario!)),
                    const SizedBox(height: 18),
                    Text(
                      _usuario!.nomUsr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        color: colores.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Toca la imagen para cambiar tu foto de perfil.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colores.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: _abrirConfiguracion,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Configuración'),
                    ),
                    const SizedBox(height: 22),
                    _crearOpcion(
                      icono: Icons.bookmarks_outlined,
                      titulo: 'Consultar guardados',
                      descripcion: 'Revisa las publicaciones de tu biblioteca.',
                      onTap: _abrirGuardados,
                    ),
                    _crearOpcion(
                      icono: Icons.shield_outlined,
                      titulo: 'Privacidad y protección de datos',
                      descripcion: 'Consulta la información de privacidad.',
                      onTap: _mostrarPrivacidad,
                    ),
                    _crearOpcion(
                      icono: Icons.info_outline,
                      titulo: 'Acerca de Vita Sacra',
                      descripcion: 'Información y versión de la aplicación.',
                      onTap: _mostrarAcercaDe,
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _cerrandoSesion
                          ? null
                          : _confirmarCerrarSesion,
                      style: TextButton.styleFrom(
                        foregroundColor: colores.error,
                      ),
                      icon: _cerrandoSesion
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.logout),
                      label: Text(
                        _cerrandoSesion
                            ? 'Cerrando sesión...'
                            : 'Cerrar sesión',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
