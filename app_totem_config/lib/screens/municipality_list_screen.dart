// lib/screens/municipality_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/municipality.dart';
import '../services/database_service.dart';
import 'totem_list_screen.dart';
import 'edit_municipality_screen.dart';

/// Provider para todas las municipalidades
final municipalitiesProvider = FutureProvider<List<Municipality>>((ref) {
  return DatabaseService.instance.fetchMunicipalities();
});

class MunicipalityListScreen extends ConsumerWidget {
  const MunicipalityListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muniAsync = ref.watch(municipalitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Municipalidades')),
      body: muniAsync.when(
        data: (munis) {
          if (munis.isEmpty) {
            return const Center(child: Text('No hay municipalidades'));
          }
          return ListView.builder(
            itemCount: munis.length,
            itemBuilder: (_, i) {
              final m = munis[i];
              return ListTile(
                leading: const Icon(Icons.location_city),
                title: Text(m.name),
                subtitle: Text('ID: ${m.id} - Tótems: ${m.totemCount}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.totemCount == 0)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () async {
                          final updated = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditMunicipalityScreen(muni: m),
                            ),
                          );
                          if (updated == true) {
                            // Riverpod 2: invalidate o refresh (ambos sirven)
                            ref.invalidate(municipalitiesProvider);
                          }
                        },
                      ),
                    if (m.totemCount == 0)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Eliminar Municipalidad'),
                              content:
                                  Text('¿Eliminar "${m.name}"? No tiene tótems.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            try {
                              await DatabaseService.instance
                                  .deleteMunicipality(m.id);
                              ref.invalidate(municipalitiesProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Eliminada "${m.name}".'),
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Error al eliminar: ${_humanizeSqlError(e)}',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () {
                  Navigator
                      .push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TotemListScreen(municipalidad: m),
                        ),
                      )
                      .then((created) {
                    if (created == true) {
                      ref.invalidate(municipalitiesProvider);
                    }
                  });
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: ${_humanizeSqlError(e)}')),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Crear nueva Municipalidad',
        child: const Icon(Icons.add),
        onPressed: () async {
          final created = await showDialog<bool>(
            context: context,
            builder: (_) => const _NewMunicipalityDialog(),
          );
          if (created == true) {
            ref.invalidate(municipalitiesProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Municipalidad creada.')),
            );
          }
        },
      ),
    );
  }
}

/// Traduce errores comunes de SQL Server a mensajes entendibles
String _humanizeSqlError(Object e) {
  final s = e.toString();
  if (s.contains('2627') || s.contains('2601')) {
    return 'Nombre duplicado (índice/UNIQUE).';
  }
  if (s.contains('229')) return 'Permiso denegado.';
  if (s.contains('208')) return 'Tabla/objeto no existe.';
  if (s.contains('18456')) return 'Login inválido.';
  if (s.contains('53') || s.contains('11001')) return 'Servidor no accesible.';
  if (s.contains('4060')) return 'No se puede abrir la base de datos.';
  return s;
}

class _NewMunicipalityDialog extends ConsumerStatefulWidget {
  const _NewMunicipalityDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<_NewMunicipalityDialog> createState() =>
      _NewMunicipalityDialogState();
}

class _NewMunicipalityDialogState
    extends ConsumerState<_NewMunicipalityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear nueva Municipalidad'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre Municipalidad',
                ),
                maxLength: 80,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Ingresa un nombre';
                  if (t.length < 3) return 'Mínimo 3 caracteres';
                  return null;
                },
                enabled: !_busy,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _busy
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    final name = _nameCtrl.text.trim();
                    final id =
                        await DatabaseService.instance.createMunicipality(name);
                    if (id <= 0) {
                      throw Exception('Insert no devolvió ID (>0).');
                    }
                    if (mounted) Navigator.pop(context, true);
                  } catch (e) {
                    setState(() {
                      _error = _humanizeSqlError(e);
                      _busy = false;
                    });
                  }
                },
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}
