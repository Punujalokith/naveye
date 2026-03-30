import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';

class PeopleEnterNameScreen extends StatefulWidget {
  const PeopleEnterNameScreen({super.key});
  @override
  State<PeopleEnterNameScreen> createState() => _PeopleEnterNameScreenState();
}
class _PeopleEnterNameScreenState extends State<PeopleEnterNameScreen> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  void _save() {
    if (_ctrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a name'), backgroundColor: AppColors.danger)); return; }
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.personAdded, (r) => r.settings.name == AppRoutes.mainAI, arguments: _ctrl.text.trim());
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size:18), onPressed: () => Navigator.pop(context))),
      body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
        const Spacer(),
        const Text('What is Their Name?', style: TextStyle(fontSize:22, fontWeight: FontWeight.w700, color: AppColors.white)),
        const SizedBox(height:32),
        LabelledTextField(label: 'Name', hint: 'Enter name', controller: _ctrl),
        const Spacer(),
        PrimaryButton(text: 'Save Name', onPressed: _save),
        const SizedBox(height:20),
      ])),
    );
  }
}
