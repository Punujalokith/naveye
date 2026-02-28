import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../../services/tts_service.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _vol      = 'Medium';
  String _ai       = 'Medium';
  bool   _vib      = true;
  String _userName = '';

  final TtsService _tts = TtsService();

  @override
  void initState() {
    super.initState();
    _load();
    _tts.init();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    // BUG-C4 FIX: widget may be disposed while awaiting SharedPreferences.
    if (!mounted) return;
    setState(() {
      _vol      = p.getString('voice_volume')   ?? 'Medium';
      _vib      = p.getBool('vibration')        ?? true;
      _ai       = p.getString('ai_sensitivity') ?? 'Medium';
      _userName = p.getString('user_name')      ?? '';
    });
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    final p = await SharedPreferences.getInstance();
    await p.setString('voice_volume',   _vol);
    await p.setBool('vibration',        _vib);
    await p.setString('ai_sensitivity', _ai);
    await _tts.init();
    await _tts.speakNow('Settings saved.');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Settings saved!'),
            backgroundColor: AppColors.green,
            duration: Duration(seconds: 2)));
      Navigator.pop(context);
    }
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
    child: child,
  );

  @override
  void dispose() { _tts.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [

          // ── Profile ──────────────────────────────────────────────────────────
          GestureDetector(
            onTap: () async {
              // BUG-32 FIX: use pushNamed consistently; route now reads the
              // bool argument to open in edit mode (see main.dart route table).
              await Navigator.pushNamed(context, AppRoutes.userProfile,
                  arguments: true);
              _load();
            },
            child: _card(Row(children: [
              Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
                child: const Icon(Icons.person, color: Colors.black, size: 26)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_userName.isEmpty ? 'Your Profile' : _userName,
                    style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const Text('Tap to update profile details',
                    style: TextStyle(color: AppColors.grey, fontSize: 12)),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.grey, size: 18),
            ])),
          ),

          // ── Voice Volume ──────────────────────────────────────────────────────
          _card(LevelSelector(
            title: 'Voice Volume', icon: Icons.volume_up,
            options: const ['Low', 'Medium', 'High'],
            selected: _vol,
            onSelected: (v) async {
              setState(() => _vol = v);
              final p = await SharedPreferences.getInstance();
              await p.setString('voice_volume', v);
              await _tts.init();
              await _tts.speakNow('Volume set to $v');
            },
          )),

          // ── Vibration ─────────────────────────────────────────────────────────
          _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Row(children: [
              Icon(Icons.vibration, color: AppColors.greyLight, size: 18),
              SizedBox(width: 8),
              Text('Vibration Feedback',
                  style: TextStyle(color: AppColors.white, fontSize: 14)),
            ]),
            Switch(
                value: _vib,
                onChanged: (v) => setState(() => _vib = v),
                activeColor: AppColors.green),
          ])),

          // ── AI Sensitivity ────────────────────────────────────────────────────
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LevelSelector(
              title: 'AI Sensitivity', icon: Icons.tune,
              options: const ['Low', 'Medium', 'High'],
              selected: _ai,
              onSelected: (v) => setState(() => _ai = v),
            ),
            const SizedBox(height: 8),
            Text(
              _ai == 'High'
                  ? 'Detects more objects — may include false alerts in busy areas'
                  : _ai == 'Low'
                      ? 'Fewer alerts — only high-confidence objects announced'
                      : 'Balanced — recommended for most environments',
              style: const TextStyle(color: AppColors.grey, fontSize: 11),
            ),
          ])),

          // ── Known People ──────────────────────────────────────────────────────
          _card(GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.peopleList),
            child: const Row(children: [
              Icon(Icons.people_outline, color: AppColors.greyLight, size: 18),
              SizedBox(width: 8),
              Text('Known People',
                  style: TextStyle(color: AppColors.white, fontSize: 14)),
              Spacer(),
              Icon(Icons.chevron_right, color: AppColors.grey, size: 18),
            ]),
          )),

          // ── Guidelines ───────────────────────────────────────────────────────
          _card(GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.guidelines),
            child: const Row(children: [
              Icon(Icons.menu_book, color: AppColors.greyLight, size: 18),
              SizedBox(width: 8),
              Text('User Guidelines',
                  style: TextStyle(color: AppColors.white, fontSize: 14)),
              Spacer(),
              Icon(Icons.chevron_right, color: AppColors.grey, size: 18),
            ]),
          )),

          PrimaryButton(text: 'Save Settings', onPressed: _save),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
