import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class UserGuidelinesScreen extends StatefulWidget {
  const UserGuidelinesScreen({super.key});
  @override
  State<UserGuidelinesScreen> createState() => _UserGuidelinesScreenState();
}
class _UserGuidelinesScreenState extends State<UserGuidelinesScreen> {
  int _step = 0;
  final _steps = const [
    {'title':'Play User Instructions','desc':'Tap the speaker icon to hear audio instructions.','voice':'Say: Repeat, Next, or Back','icon':Icons.volume_up},
    {'title':'Start Detection','desc':'Tap the camera area to begin obstacle detection.','voice':'Say: Start to begin','icon':Icons.camera_alt},
    {'title':'Listen for Alerts','desc':'NavEye speaks obstacle name, direction and distance.','voice':'Say: Repeat to hear again','icon':Icons.hearing},
    {'title':'Add Known People','desc':'Capture faces so NavEye can recognise and announce them.','voice':'Say: Who is this','icon':Icons.people},
    {'title':'Adjust Settings','desc':'Change volume, language and AI sensitivity in Settings.','voice':'Say: Open settings','icon':Icons.settings},
  ];
  @override
  Widget build(BuildContext context) {
    final s = _steps[_step];
    final total = _steps.length;
    final current = _step + 1;
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18), onPressed: () => Navigator.pop(context)), title: const Text('User Guidelines')),
      body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
        Text('Step ' + current.toString() + ' of ' + total.toString(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(total, (i) => Container(margin: const EdgeInsets.symmetric(horizontal:4), width: i==_step?24:8, height:8, decoration: BoxDecoration(color: i==_step?AppColors.yellow:AppColors.greyDark, borderRadius: BorderRadius.circular(4))))),
        const SizedBox(height: 36),
        Container(width:100, height:100, decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle), child: Icon(s['icon'] as IconData, color: Colors.black, size:48)),
        const SizedBox(height: 24),
        Text(s['title'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize:20, fontWeight: FontWeight.w700, color: AppColors.white)),
        const SizedBox(height: 12),
        Text(s['desc'] as String, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.greyLight, fontSize:14, height:1.5)),
        const Spacer(),
        Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.mic, color: AppColors.grey, size:18), const SizedBox(width:10), Text(s['voice'] as String, style: const TextStyle(color: AppColors.greyLight, fontSize:13))])),
        const SizedBox(height: 24),
        Row(children: [
          if (_step > 0) ...[Expanded(child: OutlinedButton(onPressed: () => setState(() => _step--), style: OutlinedButton.styleFrom(foregroundColor: AppColors.white, side: const BorderSide(color: AppColors.greyDark), padding: const EdgeInsets.symmetric(vertical:14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Back'))), const SizedBox(width:12)],
          Expanded(flex:2, child: ElevatedButton(onPressed: () { if (_step < total-1) setState(() => _step++); else Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical:14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(_step < total-1 ? 'Next' : 'Done', style: const TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ])),
    );
  }
}
