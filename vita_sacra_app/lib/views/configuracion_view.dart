import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import 'cambiar_contrasena_view.dart';
import 'informacion_cuenta_view.dart';
import 'intereses_view.dart';
import 'solicitud_rol_view.dart';

class ConfiguracionView extends StatefulWidget {
  const ConfiguracionView({super.key});

  @override
  State<ConfiguracionView> createState() => _ConfiguracionViewState();
}

class _ConfiguracionViewState extends State<ConfiguracionView> {
  final AuthService _authService = AuthService();

  bool _cargando = true;
  bool _sesionIniciada = false;

  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    try {
      final bool tieneToken = await _authService.tieneToken();
      if (!mounted) return;

      setState(() {
        _sesionIniciada = tieneToken;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _sesionIniciada = false;
        _cargando = false;
      });
    }
  }

  ThemeMode _obtenerTemaActual() {
    return VitaSacraApp.of(context)?.temaActual ?? ThemeMode.system;
  }

  Future<void> _cambiarTema(ThemeMode tema) async {
    final VitaSacraAppState? aplicacion = VitaSacraApp.of(context);
    if (aplicacion == null) return;

    try {
      await aplicacion.cambiarTema(tema);
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje('No fue posible guardar la preferencia del tema.');
    }
  }

  Future<bool> _pedirSesion() async {
    if (_sesionIniciada) return true;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inicia sesión'),
        content: const Text('Esta opción requiere una sesión iniciada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );

    return false;
  }

  Future<void> _abrirInformacionCuenta() async {
    if (!await _pedirSesion() || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => const InformacionCuentaView(),
      ),
    );

    if (mounted) {
      await _verificarSesion();
    }
  }

  Future<void> _abrirSolicitudRol() async {
    if (!await _pedirSesion() || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (context) => const SolicitudRolView()),
    );

    if (mounted) {
      await _verificarSesion();
    }
  }

  Future<void> _mostrarSeguridad() async {
    if (!await _pedirSesion() || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => const CambiarContrasenaView(),
      ),
    );

    if (mounted) {
      await _verificarSesion();
    }
  }

  Future<void> _abrirIntereses() async {
    if (!await _pedirSesion() || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (context) => const InteresesView()),
    );

    if (mounted) {
      await _verificarSesion();
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
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

  Widget _crearOpcionTema({
    required ThemeMode valor,
    required String titulo,
    required IconData icono,
    required ThemeMode temaActual,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final bool seleccionado = temaActual == valor;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _cambiarTema(valor),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: seleccionado ? colores.primary : colores.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: seleccionado ? colores.primary : colores.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icono,
                size: 22,
                color: seleccionado ? colores.onPrimary : colores.onSurface,
              ),
              const SizedBox(height: 7),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: seleccionado ? colores.onPrimary : colores.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirApariencia() {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final ThemeMode temaActual = _obtenerTemaActual();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: colores.primary),
              const SizedBox(width: 10),
              const Text(
                'Tema de la aplicación',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _crearOpcionTema(
                valor: ThemeMode.light,
                titulo: 'Claro',
                icono: Icons.light_mode_outlined,
                temaActual: temaActual,
              ),
              const SizedBox(width: 8),
              _crearOpcionTema(
                valor: ThemeMode.dark,
                titulo: 'Oscuro',
                icono: Icons.dark_mode_outlined,
                temaActual: temaActual,
              ),
              const SizedBox(width: 8),
              _crearOpcionTema(
                valor: ThemeMode.system,
                titulo: 'Sistema',
                icono: Icons.brightness_auto_outlined,
                temaActual: temaActual,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'La apariencia seleccionada se aplica a toda la aplicación '
            'y se conserva al reiniciarla.',
            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _construirContenido() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Configuración',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: colores.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Administra tu cuenta y personaliza la aplicación.',
          style: TextStyle(color: colores.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        Text(
          'Apariencia',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        _construirApariencia(),
        const SizedBox(height: 28),
        Text(
          'Personalización',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        _crearOpcion(
          icono: Icons.tune_outlined,
          titulo: 'Mis intereses',
          descripcion:
              'Elige categorías para personalizar tus recomendaciones.',
          onTap: _abrirIntereses,
        ),
        const SizedBox(height: 18),
        Text(
          'Cuenta y seguridad',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        _crearOpcion(
          icono: Icons.person_outline,
          titulo: 'Información de mi cuenta',
          descripcion: 'Consultar y editar nombre y domicilio opcional.',
          onTap: _abrirInformacionCuenta,
        ),
        _crearOpcion(
          icono: Icons.assignment_outlined,
          titulo: 'Solicitar rol adicional',
          descripcion: 'Solicita Autor o Anunciante para revisión.',
          onTap: _abrirSolicitudRol,
        ),
        _crearOpcion(
          icono: Icons.lock_outline,
          titulo: 'Seguridad de la cuenta',
          descripcion: 'Cambiar la contraseña de la cuenta.',
          onTap: _mostrarSeguridad,
        ),
        const SizedBox(height: 24),
      ],
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
      appBar: AppBar(title: const Text('Configuración'), centerTitle: true),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _construirContenido(),
      ),
    );
  }
}
