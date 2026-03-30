import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const PrimaryButton({super.key, required this.text, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  const SecondaryButton({super.key, required this.text, required this.onPressed, this.icon});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class NavEyeLogo extends StatelessWidget {
  const NavEyeLogo({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 70, height: 70,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.greyDark)),
        child: const Icon(Icons.remove_red_eye_outlined, color: AppColors.yellow, size: 36),
      ),
      const SizedBox(height: 12),
      const Text('NavEye', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.white)),
      const Text('Your Assistant', style: TextStyle(fontSize: 13, color: AppColors.grey)),
    ]);
  }
}

class LabelledTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  const LabelledTextField({super.key, required this.label, required this.hint, this.controller, this.keyboardType = TextInputType.text});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.greyLight, fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      TextField(controller: controller, keyboardType: keyboardType, style: const TextStyle(color: AppColors.white, fontSize: 14), decoration: InputDecoration(hintText: hint)),
    ]);
  }
}

class LevelSelector extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  const LevelSelector({super.key, required this.title, required this.icon, required this.options, required this.selected, required this.onSelected});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: AppColors.greyLight, size: 18), const SizedBox(width: 8), Text(title, style: const TextStyle(color: AppColors.white, fontSize: 14))]),
      const SizedBox(height: 10),
      Row(children: options.map((opt) {
        final sel = opt == selected;
        return Expanded(child: GestureDetector(
          onTap: () => onSelected(opt),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: sel ? AppColors.yellow : AppColors.inputBg, borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(opt, style: TextStyle(color: sel ? Colors.black : AppColors.greyLight, fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400))),
          ),
        ));
      }).toList()),
    ]);
  }
}
