import 'package:flutter/material.dart';

import '../models/registered_face.dart';
import '../services/face_storage_service.dart';

class RegisteredListScreen extends StatefulWidget {
  const RegisteredListScreen({super.key});

  @override
  State<RegisteredListScreen> createState() => _RegisteredListScreenState();
}

class _RegisteredListScreenState extends State<RegisteredListScreen> {
  List<RegisteredFace> _faces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final faces = await FaceStorageService.instance.loadAll();
    setState(() {
      _faces = faces;
      _loading = false;
    });
  }

  Future<void> _delete(String id) async {
    await FaceStorageService.instance.deleteFace(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registered Faces')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _faces.isEmpty
              ? const Center(child: Text('No faces registered yet.'))
              : ListView.builder(
                  itemCount: _faces.length,
                  itemBuilder: (context, index) {
                    final f = _faces[index];
                    return ListTile(
                      title: Text(f.name),
                      subtitle: Text(
                          'vector length: ${f.embedding.length} • '
                          'registered ${f.registeredAt}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _delete(f.id),
                      ),
                    );
                  },
                ),
    );
  }
}
