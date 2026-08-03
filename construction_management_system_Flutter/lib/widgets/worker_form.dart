import 'package:flutter/material.dart';
import '../constants/styles.dart';
import 'custom_button.dart';
import 'custom_input.dart';

class AddWorkerForm extends StatefulWidget {
  const AddWorkerForm({super.key});
  @override
  State<AddWorkerForm> createState() => _AddWorkerFormState();
}

class _AddWorkerFormState extends State<AddWorkerForm> {
  final _fk = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _phone = TextEditingController();
  String _project = 'Kuala Lumpur Tower Block A';

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radius12),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _fk,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add Worker', style: AppStyles.h2),
                  IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(c)),
                ],
              ),
              const SizedBox(height: 24),
              CustomInput(
                  label: 'Full Name',
                  hint: 'e.g. Ali Hassan',
                  controller: _name,
                  validator: (v) =>
                      v?.isEmpty ?? true ? 'Required' : null),
              const SizedBox(height: 16),
              CustomInput(
                  label: 'Role',
                  hint: 'e.g. Electrician',
                  controller: _role,
                  validator: (v) =>
                      v?.isEmpty ?? true ? 'Required' : null),
              const SizedBox(height: 16),
              const Text('Assigned Project', style: AppStyles.label),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _project,
                decoration: AppStyles.inputDecoration(),
                items: const [
                  'Kuala Lumpur Tower Block A',
                  'Petaling Jaya Residential Complex',
                  'Penang Bridge Maintenance',
                  'Iskandar Puteri Industrial Hub'
                ]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _project = v!),
              ),
              const SizedBox(height: 16),
              CustomInput(
                  label: 'Phone',
                  hint: '+60 12-345 6789',
                  controller: _phone,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 32),
              CustomButton(
                  text: 'Add Worker',
                  onPressed: () {
                    if (_fk.currentState?.validate() ?? false) {
                      Navigator.pop(c);
                      ScaffoldMessenger.of(c).showSnackBar(
                          const SnackBar(content: Text('✅ Worker added')));
                    }
                  }),
            ],
          ),
        ),
      ),
    );
  }
}