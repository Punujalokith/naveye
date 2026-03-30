import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../../services/database_service.dart';
import '../../models/person_model.dart';

class PeopleEnterNameScreen extends StatefulWidget {
  const PeopleEnterNameScreen({super.key});
  @override
  State<PeopleEnterNameScreen> createState() => _PeopleEnterNameScreenState();
}

class _PeopleEnterNameScreenState extends State<PeopleEnterNameScreen> {
  final _ctrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name'), backgroundColor: AppColors.danger));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final person = Person(
        name: _ctrl.text.trim(),
        imagePath: '',
        createdAt: DateTime.now(),
      );
      await DatabaseService.instance.insertPerson(person);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.personAdded,
          (r) => r.settings.name == AppRoutes.mainAI,
          arguments: _ctrl.text.trim(),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error saving person'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18), onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Spacer(),
          const Text("What is Their Name?", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.white)),
          const SizedBox(height: 32),
          LabelledTextField(label: 'Name', hint: 'Enter name', controller: _ctrl),
          const Spacer(),
          PrimaryButton(text: _isSaving ? 'Saving...' : 'Save Name', onPressed: _isSaving ? () {} : _save),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
