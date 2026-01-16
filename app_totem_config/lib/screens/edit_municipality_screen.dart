// lib/screens/edit_municipality_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/municipality.dart';
import '../services/database_service.dart';

class EditMunicipalityScreen extends ConsumerStatefulWidget {
  final Municipality muni;
  const EditMunicipalityScreen({Key? key, required this.muni})
      : super(key: key);

  @override
  ConsumerState<EditMunicipalityScreen> createState() =>
      _EditMunicipalityScreenState();
}

class _EditMunicipalityScreenState
    extends ConsumerState<EditMunicipalityScreen> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.muni.name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName = _ctrl.text.trim();
    if (newName.isEmpty || newName == widget.muni.name) return;
    await DatabaseService.instance.updateMunicipality(
      municipalidadId: widget.muni.id,
      newName: newName,
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar Municipalidad')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('ID: ${widget.muni.id}'),
            TextField(
              controller: _ctrl,
              decoration:
                  const InputDecoration(labelText: 'Nuevo nombre'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
