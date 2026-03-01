import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../../services/tts_service.dart';

class UserProfileScreen extends StatefulWidget {
  final bool isEdit;
  const UserProfileScreen({super.key, this.isEdit = false});
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _nameCtrl      = TextEditingController();
  final _ageCtrl       = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  String  _language    = 'English';
  bool    _isSaving    = false;
  bool    _viewMode    = false; // show read-only card after loading

  final TtsService _tts = TtsService();
  static const _languages = ['English', 'Sinhala', 'Tamil'];

  @override
  void initState() {
    super.initState();
    // BUG-W1 FIX: _tts.init() is async; calling it unawaited from initState
    // is fine but wrapping in microtask ensures it runs after the first frame
    // and errors are not silently swallowed.
    Future.microtask(() async { await _tts.init(); });
    if (widget.isEdit) _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text      = p.getString('user_name')      ?? '';
      _ageCtrl.text       = p.getString('user_age')       ?? '';
      _phoneCtrl.text     = p.getString('user_phone')     ?? '';
      _emergencyCtrl.text = p.getString('user_emergency') ?? '';
      _language           = p.getString('language')       ?? 'English';
      _viewMode           = _nameCtrl.text.isNotEmpty;
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Name is required'), backgroundColor: AppColors.danger));
      return;
    }
    setState(() => _isSaving = true);
    final p = await SharedPreferences.getInstance();
    await p.setString('user_name',      _nameCtrl.text.trim());
    await p.setString('user_age',       _ageCtrl.text.trim());
    await p.setString('user_phone',     _phoneCtrl.text.trim());
    await p.setString('user_emergency', _emergencyCtrl.text.trim());
    await p.setString('language',       _language);
    setState(() => _isSaving = false);

    if (mounted) {
      if (widget.isEdit) {
        await _tts.speakNow('Profile updated.');
        if (!mounted) return;
        setState(() => _viewMode = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profile updated!'), backgroundColor: AppColors.green));
      } else {
        Navigator.pushNamed(context, AppRoutes.onboardingHowItWorks);
      }
    }
  }

  Future<void> _readAloud() async {
    final name = _nameCtrl.text.trim();
    final age  = _ageCtrl.text.trim();
    final em   = _emergencyCtrl.text.trim();
    String msg = name.isNotEmpty ? 'Your name is $name.' : 'No name saved.';
    if (age.isNotEmpty)  msg += ' Age: $age.';
    if (em.isNotEmpty)   msg += ' Emergency contact: $em.';
    msg += ' Language: $_language.';
    await _tts.speakNow(msg);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _ageCtrl.dispose();
    _phoneCtrl.dispose(); _emergencyCtrl.dispose();
    _tts.dispose();
    super.dispose();
  }

  String get _initials {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.isEdit
            ? (_viewMode ? 'My Profile' : 'Edit Profile')
            : 'Create Profile'),
        actions: [
          if (widget.isEdit) ...[
            if (_viewMode)
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: AppColors.yellow, size: 20),
                onPressed: () => setState(() => _viewMode = false),
              ),
            IconButton(
              icon: const Icon(Icons.record_voice_over_outlined,
                  color: AppColors.grey, size: 20),
              onPressed: _readAloud,
              tooltip: 'Read profile aloud',
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: _viewMode ? _viewBody() : _editBody(),
        ),
      ),
    );
  }

  // ── View mode ─────────────────────────────────────────────────────────────
  Widget _viewBody() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Avatar + name
      Center(child: Column(children: [
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            color: AppColors.yellow,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
                color: AppColors.yellow.withValues(alpha: 0.35),
                blurRadius: 24, spreadRadius: 2)],
          ),
          child: Center(child: Text(_initials,
              style: const TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w800, color: Colors.black))),
        ),
        const SizedBox(height: 14),
        Text(_nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'No name set',
            style: const TextStyle(
                color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('NavEye User',
            style: TextStyle(color: AppColors.grey, fontSize: 13)),
      ])),
      const SizedBox(height: 24),

      // Read aloud button
      GestureDetector(
        onTap: _readAloud,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.greyDark),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.record_voice_over, color: AppColors.yellow, size: 18),
            SizedBox(width: 8),
            Text('Read Profile Aloud',
                style: TextStyle(color: AppColors.yellow,
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      const SizedBox(height: 20),

      // Info cards
      _infoCard(Icons.person_outline, 'Full Name',
          _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '—'),
      _infoCard(Icons.cake_outlined, 'Age',
          _ageCtrl.text.isNotEmpty ? _ageCtrl.text : '—'),
      _infoCard(Icons.phone_outlined, 'Phone',
          _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : '—'),
      _infoCard(Icons.emergency_outlined, 'Emergency Contact',
          _emergencyCtrl.text.isNotEmpty ? _emergencyCtrl.text : '—',
          accent: AppColors.danger),
      _infoCard(Icons.language_outlined, 'Language', _language),

      const SizedBox(height: 24),
      PrimaryButton(
        text: 'Edit Profile',
        onPressed: () => setState(() => _viewMode = false),
      ),
    ]);
  }

  Widget _infoCard(IconData icon, String label, String value, {Color? accent}) {
    final c = accent ?? AppColors.yellow;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: accent != null
            ? Border.all(color: accent.withValues(alpha: 0.4), width: 1.5)
            : null,
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: c, size: 20),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: AppColors.grey, fontSize: 11)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(
              color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  // ── Edit mode ─────────────────────────────────────────────────────────────
  Widget _editBody() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!widget.isEdit) ...[
        const Center(child: Text('Create Your Profile',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                color: AppColors.white))),
        const SizedBox(height: 6),
        const Center(child: Text('A few details help NavEye assist you better',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.grey, fontSize: 13))),
        const SizedBox(height: 28),
      ],

      // Avatar initials preview
      Center(child: Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: AppColors.yellow.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.yellow, width: 2),
        ),
        child: Center(child: Text(_initials,
            style: const TextStyle(fontSize: 28,
                fontWeight: FontWeight.w800, color: AppColors.yellow))),
      )),
      const SizedBox(height: 24),

      VoiceTextField(label: 'Full Name *', hint: 'Enter your name or tap mic',
          controller: _nameCtrl),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: VoiceTextField(
          label: 'Age', hint: 'e.g. 25',
          controller: _ageCtrl, keyboardType: TextInputType.number,
        )),
        const SizedBox(width: 12),
        Expanded(child: VoiceTextField(
          label: 'Phone', hint: 'Your number',
          controller: _phoneCtrl, keyboardType: TextInputType.phone,
        )),
      ]),
      const SizedBox(height: 14),

      // Emergency contact — highlighted
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.emergency_outlined, color: AppColors.danger, size: 15),
            SizedBox(width: 6),
            Text('Emergency Contact',
                style: TextStyle(color: AppColors.danger,
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          VoiceTextField(
            label: '', hint: 'Caretaker name or number',
            controller: _emergencyCtrl, keyboardType: TextInputType.phone,
          ),
        ]),
      ),
      const SizedBox(height: 18),

      const Text('Preferred Language',
          style: TextStyle(color: AppColors.greyLight,
              fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.inputBg, borderRadius: BorderRadius.circular(10)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _language,
            isExpanded: true,
            dropdownColor: AppColors.inputBg,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            items: _languages.map((l) =>
                DropdownMenuItem(value: l, child: Text(l))).toList(),
            onChanged: (v) => setState(() => _language = v!),
          ),
        ),
      ),
      const SizedBox(height: 36),

      PrimaryButton(
        text: _isSaving ? 'Saving...'
            : widget.isEdit ? 'Save Changes' : 'Continue',
        onPressed: _isSaving ? () {} : _save,
      ),

      if (!widget.isEdit) ...[
        const SizedBox(height: 12),
        Center(child: TextButton(
          onPressed: () =>
              Navigator.pushNamed(context, AppRoutes.onboardingHowItWorks),
          child: const Text('Skip for now',
              style: TextStyle(color: AppColors.grey, fontSize: 13)),
        )),
      ],
      const SizedBox(height: 16),
    ]);
  }
}
