import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  String _vol = 'Medium', _lang = 'English', _ai = 'Medium';
  bool _vib = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() { _vol = p.getString('voice_volume') ?? 'Medium'; _lang = p.getString('language') ?? 'English'; _vib = p.getBool('vibration') ?? true; _ai = p.getString('ai_sensitivity') ?? 'Medium'; });
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('voice_volume', _vol); await p.setString('language', _lang); await p.setBool('vibration', _vib); await p.setString('ai_sensitivity', _ai);
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved!'), backgroundColor: AppColors.green)); Navigator.pop(context); }
  }
  Widget _card(Widget child) => Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)), child: child);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18), onPressed: () => Navigator.pop(context)), title: const Text('Settings')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
        _card(LevelSelector(title: 'Voice Volume', icon: Icons.volume_up, options: const ['Low','Medium','High'], selected: _vol, onSelected: (v) => setState(() => _vol = v))),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.language, color: AppColors.greyLight, size: 18), SizedBox(width: 8), Text('Language', style: TextStyle(color: AppColors.white, fontSize: 14))]),
          const SizedBox(height: 10),
          Row(children: ['English','Sinhala'].map((l) { final s = l==_lang; return Expanded(child: GestureDetector(onTap: () => setState(() => _lang = l), child: Container(margin: const EdgeInsets.only(right:6), padding: const EdgeInsets.symmetric(vertical:8), decoration: BoxDecoration(color: s ? AppColors.yellow : AppColors.inputBg, borderRadius: BorderRadius.circular(8)), child: Center(child: Text(l, style: TextStyle(color: s ? Colors.black : AppColors.greyLight, fontSize:13, fontWeight: s ? FontWeight.w700 : FontWeight.w400)))))); }).toList()),
        ])),
        _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Row(children: [Icon(Icons.vibration, color: AppColors.greyLight, size: 18), SizedBox(width: 8), Text('Vibration Feedback', style: TextStyle(color: AppColors.white, fontSize: 14))]),
          Switch(value: _vib, onChanged: (v) => setState(() => _vib = v), activeColor: AppColors.green),
        ])),
        _card(LevelSelector(title: 'AI Sensitivity', icon: Icons.tune, options: const ['Low','Medium','High'], selected: _ai, onSelected: (v) => setState(() => _ai = v))),
        _card(GestureDetector(onTap: () => Navigator.pushNamed(context, AppRoutes.guidelines), child: const Row(children: [Icon(Icons.menu_book, color: AppColors.greyLight, size: 18), SizedBox(width: 8), Text('User Guideline', style: TextStyle(color: AppColors.white, fontSize: 14)), Spacer(), Icon(Icons.chevron_right, color: AppColors.grey, size: 18)]))),
        PrimaryButton(text: 'Save Settings', onPressed: _save),
      ])),
    );
  }
}
