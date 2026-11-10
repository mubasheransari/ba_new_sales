import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/complaint_widgets.dart';

/// Form to raise a complaint: title, description and an optional picture.
/// Pops with the new complaint id so the inbox can open the conversation.
class NewComplaintScreen extends StatefulWidget {
  const NewComplaintScreen({super.key});

  @override
  State<NewComplaintScreen> createState() => _NewComplaintScreenState();
}

class _NewComplaintScreenState extends State<NewComplaintScreen> {
  static const _titleMax = 200;
  static const _descMax = 1000;

  final _title = TextEditingController();
  final _desc = TextEditingController();
  Uint8List? _image;
  String? _titleError;
  String? _descError;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    FocusScope.of(context).unfocus();
    final bytes = await pickComplaintPhoto(context);
    if (bytes != null && mounted) setState(() => _image = bytes);
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    final title = _title.text.trim();
    final desc = _desc.text.trim();
    setState(() {
      _titleError = title.isEmpty ? 'Please enter a title.' : null;
      _descError = desc.isEmpty ? 'Please describe the problem.' : null;
    });
    if (title.isEmpty || desc.isEmpty) return;

    setState(() => _busy = true);
    try {
      final id = await context.read<ComplaintsCubit>().create(
            title: title,
            description: desc,
            image: _image,
          );
      if (!mounted) return;
      showToast(context, 'Complaint submitted.', error: false);
      Navigator.of(context).pop(id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    final mart = martNameFor(user);

    return Scaffold(
      appBar: AppBar(title: const Text('New Complaint')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: GradientButton(
            text: 'SUBMIT COMPLAINT',
            icon: Icons.send_rounded,
            loading: _busy,
            onPressed: _submit,
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.redTint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mart == null
                          ? 'Tell us about the problem. Our team will reply '
                              'in this app.'
                          : 'This complaint will be sent for $mart. Our team '
                              'will reply in this app.',
                      style: const TextStyle(
                          color: AppColors.text, fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _Label('Title'),
            TextField(
              controller: _title,
              enabled: !_busy,
              maxLength: _titleMax,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
              decoration: InputDecoration(
                hintText: 'e.g. Stock not delivered',
                prefixIcon: const Icon(Icons.title_rounded),
                errorText: _titleError,
              ),
            ),
            const SizedBox(height: 8),
            const _Label('Description'),
            TextField(
              controller: _desc,
              enabled: !_busy,
              maxLength: _descMax,
              minLines: 5,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              onChanged: (_) {
                if (_descError != null) setState(() => _descError = null);
              },
              decoration: InputDecoration(
                hintText: 'Explain what happened...',
                alignLabelWithHint: true,
                errorText: _descError,
              ),
            ),
            const SizedBox(height: 8),
            const _Label('Picture (optional)'),
            if (_image == null)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _busy ? null : _pickImage,
                child: Container(
                  height: 118,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.redLight, width: 1.6),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_rounded,
                          color: AppColors.red, size: 32),
                      SizedBox(height: 8),
                      Text('Add a picture',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.text)),
                      SizedBox(height: 2),
                      Text('Camera or gallery',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 12.5)),
                    ],
                  ),
                ),
              )
            else
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      _image!,
                      width: double.infinity,
                      height: 210,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Row(
                      children: [
                        _RoundAction(
                          icon: Icons.edit_rounded,
                          onTap: _busy ? null : _pickImage,
                        ),
                        const SizedBox(width: 8),
                        _RoundAction(
                          icon: Icons.delete_outline_rounded,
                          onTap: _busy ? null : () => setState(() => _image = null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppColors.text)),
      );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      );
}
