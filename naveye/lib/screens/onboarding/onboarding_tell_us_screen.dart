import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';

class OnboardingTellUsScreen extends StatefulWidget {
  const OnboardingTellUsScreen({super.key});
  @override
  State<OnboardingTellUsScreen> createState() => _OnboardingTellUsScreenState();
}

class _OnboardingTellUsScreenState extends State<OnboardingTellUsScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _selectedLanguage = 'English';
  final List<String> _languages = ['English', 'Sinhala', 'Tamil'];
  @override
  void dispose() { _nameController.dispose(); _emailController.dispose(); super.dispose(); }

  Future<void> _continue() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your name'), backgroundColor: AppColors.danger));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text.trim());
    if (mounted) Navigator.pushNamed(context, AppRoutes.onboardingHowItWorks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: Text('Tell Us About You', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.white))),
            const SizedBox(height: 32),
            LabelledTextField(label: 'Name', hint: 'Enter your name', controller: _nameController),
            const SizedBox(height: 20),
            const Text('Language', style: TextStyle(color: AppColors.greyLight, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: AppColors.inputBg, borderRadius: BorderRadius.circular(10)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _selectedLanguage, isExpanded: true, dropdownColor: AppColors.inputBg,
                style: const TextStyle(color: AppColors.white, fontSize: 14),
                items: _languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (val) => setState(() => _selectedLanguage = val!),
              )),
            ),
            const SizedBox(height: 20),
            LabelledTextField(label: 'Email', hint: 'Your email (optional)', controller: _emailController, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 40),
            PrimaryButton(text: 'Continue', onPressed: _continue),
            const SizedBox(height: 16),
            Center(child: TextButton(onPressed: () => Navigator.pushNamed(context, AppRoutes.onboardingHowItWorks), child: const Text('Skip for now', style: TextStyle(color: AppColors.grey, fontSize: 13)))),
          ]),
        ),
      ),
    );
  }
}
