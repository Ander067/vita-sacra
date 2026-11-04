import 'package:flutter/material.dart';

import '../views/home_view.dart';
import '../views/publicaciones_view.dart';
import '../views/buscar_view.dart';
import '../views/categorias_view.dart';
import '../views/perfil_view.dart';

// Componente principal de navegacion de Vita Sacra.
class AppNavigation extends StatefulWidget {
  // Indice de la pantalla que se mostrara inicialmente.
  final int indiceInicial;

  const AppNavigation({super.key, this.indiceInicial = 0})
    : assert(
        indiceInicial >= 0 && indiceInicial < 5,
        'El indice inicial debe estar entre 0 y 4.',
      );

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation> {
  // Indice de la pantalla seleccionada.
  late int _indiceSeleccionado;

  // Pantallas disponibles en la navegacion inferior.
  final List<Widget> _pantallas = const [
    HomeView(),
    PublicacionesView(),
    BuscarView(),
    CategoriasView(),
    PerfilView(),
  ];

  @override
  void initState() {
    super.initState();

    // Establecer la pantalla inicial.
    _indiceSeleccionado = _validarIndice(widget.indiceInicial);
  }

  @override
  void didUpdateWidget(covariant AppNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detectar cambios externos en la pantalla inicial.
    if (oldWidget.indiceInicial != widget.indiceInicial) {
      // Actualizar el indice sin llamar a setState.
      // Flutter reconstruye el widget despues de este metodo.
      _indiceSeleccionado = _validarIndice(widget.indiceInicial);
    }
  }

  // Validar que el indice corresponda a una pantalla disponible.
  int _validarIndice(int indice) {
    if (indice >= 0 && indice < _pantallas.length) {
      return indice;
    }

    // Mostrar inicio cuando el indice no sea valido.
    return 0;
  }

  // Cambiar la pantalla seleccionada.
  void _cambiarPantalla(int indice) {
    // Validar que el indice exista.
    if (indice < 0 || indice >= _pantallas.length) {
      return;
    }

    // Evitar cambios innecesarios.
    if (indice == _indiceSeleccionado) {
      return;
    }

    // Actualizar la pantalla activa.
    setState(() {
      _indiceSeleccionado = indice;
    });
  }

  // Construir los destinos de navegacion.
  List<NavigationDestination> _crearDestinos() {
    return const [
      // Acceso a la pantalla de inicio.
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Inicio',
      ),

      // Acceso al listado de publicaciones.
      NavigationDestination(
        icon: Icon(Icons.article_outlined),
        selectedIcon: Icon(Icons.article),
        label: 'Publicaciones',
      ),

      // Acceso al buscador.
      NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: 'Buscar',
      ),

      // Acceso a las categorias.
      NavigationDestination(
        icon: Icon(Icons.category_outlined),
        selectedIcon: Icon(Icons.category),
        label: 'Categorías',
      ),

      // Acceso al perfil del usuario.
      NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Perfil',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      // Mantener las pantallas dentro de un mismo contenedor.
      body: IndexedStack(index: _indiceSeleccionado, children: _pantallas),

      // Barra inferior de navegacion.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indiceSeleccionado,

        // Cambiar la pantalla al seleccionar una opcion.
        onDestinationSelected: _cambiarPantalla,

        // Mostrar los nombres de las secciones.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,

        // Aplicar los colores del tema.
        backgroundColor: colores.surface,
        indicatorColor: colores.primaryContainer,

        // Destinos disponibles.
        destinations: _crearDestinos(),
      ),
    );
  }
}
