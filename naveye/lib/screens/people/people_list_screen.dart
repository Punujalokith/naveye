import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../services/database_service.dart';
import '../../services/tts_service.dart';
import '../../models/person_model.dart';

class PeopleListScreen extends StatefulWidget {
  const PeopleListScreen({super.key});
  @override
  State<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends State<PeopleListScreen> {
  List<Person> _persons = [];
  // Pre-computed file existence so we don't call existsSync() inside build
  final Map<int, bool> _imageExists = {};
  bool _loading = true;
  final TtsService _tts = TtsService();

  @override
  void initState() {
    super.initState();
    _tts.init();
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final persons = await DatabaseService.instance.getAllPersons();
    // Pre-compute image file existence off the main thread build path
    final exists = <int, bool>{};
    for (final p in persons) {
      if (p.id != null && p.imagePath.isNotEmpty) {
        exists[p.id!] = File(p.imagePath).existsSync();
      }
    }
    _imageExists
      ..clear()
      ..addAll(exists);
    // BUG-C3 FIX: widget may be disposed while awaiting DB / file I/O above.
    if (!mounted) return;
    setState(() { _persons = persons; _loading = false; });

    // Announce how many people are saved
    if (persons.isEmpty) {
      await _tts.speak('No people saved yet. Tap the add button to add a person.');
    } else {
      final names = persons.map((p) => p.name).join(', ');
      await _tts.speak('${persons.length} ${persons.length == 1 ? "person" : "people"} saved: $names');
    }
  }

  Future<void> _deletePerson(int id, String name) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Person', style: TextStyle(color: AppColors.white)),
        content: Text('Remove $name from NavEye?\nNavEye will no longer recognise them.',
          style: const TextStyle(color: AppColors.greyLight, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      // BUG-25 FIX: set loading before async delete so rapid taps can't
      // hit stale indices while the list is reloading.
      setState(() => _loading = true);
      await DatabaseService.instance.deletePerson(id);
      // BUG-C2 FIX: widget may be disposed while awaiting DB delete.
      if (!mounted) return;
      await _tts.speakNow('$name removed.');
      await _loadPersons();
    }
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Known People${_persons.isNotEmpty ? " (${_persons.length})" : ""}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: AppColors.yellow),
            tooltip: 'Add Person',
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.peopleCapture);
              _loadPersons();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.yellow))
          : _persons.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.people_outline, color: AppColors.grey, size: 72),
        const SizedBox(height: 20),
        const Text('No people saved yet',
          style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
          'Add people so NavEye can recognise\nand announce their name.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () async {
            await Navigator.pushNamed(context, AppRoutes.peopleCapture);
            _loadPersons();
          },
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Add Person', style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.yellow, foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _persons.length,
      itemBuilder: (_, i) {
        final p = _persons[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            onTap: () => _tts.speakNow('${p.name}, added ${p.createdAt.day} ${_month(p.createdAt.month)} ${p.createdAt.year}'),
            leading: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.greyDark, width: 1.5),
              ),
              child: ClipOval(
                child: p.imagePath.isNotEmpty && (_imageExists[p.id] ?? false)
                    ? Image.file(File(p.imagePath), fit: BoxFit.cover, width: 52, height: 52)
                    : Center(
                        child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: AppColors.yellow, fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
              ),
            ),
            title: Text(p.name,
              style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Added ${p.createdAt.day} ${_month(p.createdAt.month)} ${p.createdAt.year}',
                style: const TextStyle(color: AppColors.grey, fontSize: 12),
              ),
              if (p.embedding.isNotEmpty)
                const Text('Face recognised ✓',
                  style: TextStyle(color: AppColors.green, fontSize: 11)),
              if (p.embedding.isEmpty)
                const Text('Face not yet processed',
                  style: TextStyle(color: AppColors.grey, fontSize: 11)),
            ]),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 22),
              onPressed: p.id == null ? null : () => _deletePerson(p.id!, p.name),
            ),
          ),
        );
      },
    );
  }

  String _month(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m];
}
