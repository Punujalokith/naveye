import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../services/database_service.dart';
import '../../models/person_model.dart';

class PeopleListScreen extends StatefulWidget {
  const PeopleListScreen({super.key});
  @override
  State<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends State<PeopleListScreen> {
  List<Person> _persons = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadPersons(); }

  Future<void> _loadPersons() async {
    final persons = await DatabaseService.instance.getAllPersons();
    setState(() { _persons = persons; _loading = false; });
  }

  Future<void> _deletePerson(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Person', style: TextStyle(color: AppColors.white)),
        content: Text('Remove $name from NavEye?', style: const TextStyle(color: AppColors.greyLight)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.instance.deletePerson(id);
      _loadPersons();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18), onPressed: () => Navigator.pop(context)),
        title: const Text('Known People'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: AppColors.yellow),
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
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.people_outline, color: AppColors.grey, size: 64),
                  const SizedBox(height: 16),
                  const Text('No people saved yet', style: TextStyle(color: AppColors.grey, fontSize: 16)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.pushNamed(context, AppRoutes.peopleCapture);
                      _loadPersons();
                    },
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Add Person'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _persons.length,
                  itemBuilder: (_, i) {
                    final p = _persons[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
                          child: Center(child: Text(p.name[0].toUpperCase(), style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w700))),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                          Text('Added ${p.createdAt.day}/${p.createdAt.month}/${p.createdAt.year}', style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                        ])),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                          onPressed: () => _deletePerson(p.id!, p.name),
                        ),
                      ]),
                    );
                  },
                ),
    );
  }
}
