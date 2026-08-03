import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/styles.dart';
import 'custom_button.dart';
import 'custom_input.dart';

class NewProjectForm extends StatefulWidget {
  const NewProjectForm({super.key});

  @override
  State<NewProjectForm> createState() => _NewProjectFormState();
}

class _NewProjectFormState extends State<NewProjectForm> {
  final _fk = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _loc = TextEditingController();
  final _start = TextEditingController();
  final _due = TextEditingController();
  final _budget = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _loc.dispose();
    _start.dispose();
    _due.dispose();
    _budget.dispose();
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
                  const Text('New Project', style: AppStyles.h2),
                  IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(c)),
                ],
              ),
              const SizedBox(height: 24),
              CustomInput(
                  label: 'Project Name',
                  hint: 'e.g. Penang Tower C',
                  controller: _name,
                  validator: (v) =>
                      v?.isEmpty ?? true ? 'Required' : null),
              const SizedBox(height: 16),
              CustomInput(label: 'Location', hint: 'Address', controller: _loc),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: CustomInput(
                          label: 'Start Date',
                          hint: 'mm/dd/yyyy',
                          controller: _start,
                          suffixIcon: Icons.calendar_today,
                          readOnly: true,
                          onTap: () => _pick(_start))),
                  const SizedBox(width: 16),
                  Expanded(
                      child: CustomInput(
                          label: 'Due Date',
                          hint: 'mm/dd/yyyy',
                          controller: _due,
                          suffixIcon: Icons.calendar_today,
                          readOnly: true,
                          onTap: () => _pick(_due))),
                ],
              ),
              const SizedBox(height: 16),
              CustomInput(
                  label: 'Budget (RM)',
                  hint: 'e.g. 4200000',
                  controller: _budget,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 32),
              CustomButton(
                  text: 'Create Project',
                  onPressed: () {
                    if (_fk.currentState?.validate() ?? false) {
                      Navigator.pop(c, {
                        'name': _name.text,
                        'location': _loc.text,
                        'budget': double.tryParse(_budget.text) ?? 0,
                      });
                      ScaffoldMessenger.of(c).showSnackBar(
                          const SnackBar(content: Text('✅ Project created')));
                    }
                  }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(TextEditingController ctrl) async {
    final d = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (d != null) ctrl.text = DateFormat('MM/dd/yyyy').format(d);
  }
}