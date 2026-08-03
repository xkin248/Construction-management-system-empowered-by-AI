import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/colors.dart';
import '../constants/styles.dart';
import 'custom_button.dart';
import 'custom_input.dart';

class NewTaskForm extends StatefulWidget {
  const NewTaskForm({super.key});
  @override
  State<NewTaskForm> createState() => _NewTaskFormState();
}

class _NewTaskFormState extends State<NewTaskForm> {
  final _fk = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _hours = TextEditingController();
  final _due = TextEditingController();
  String _project = 'Kuala Lumpur Tower Block A';
  String _priority = 'High';

  @override
  void dispose() {
    _title.dispose();
    _hours.dispose();
    _due.dispose();
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
                  const Text('New Task', style: AppStyles.h2),
                  IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(c)),
                ],
              ),
              const SizedBox(height: 24),
              CustomInput(
                  label: 'Task Title',
                  hint: 'Task name',
                  controller: _title,
                  validator: (v) =>
                      v?.isEmpty ?? true ? 'Required' : null),
              const SizedBox(height: 16),
              const Text('Project', style: AppStyles.label),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _project,
                isExpanded: true,
                decoration: AppStyles.inputDecoration(),
                items: const [
                  'Kuala Lumpur Tower Block A',
                  'Petaling Jaya Residential Complex',
                  'Penang Bridge Maintenance'
                ]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _project = v!),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Priority', style: AppStyles.label),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: _priority,
                          decoration: AppStyles.inputDecoration(),
                          items: const ['High', 'Medium', 'Low']
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _priority = v!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                      child: CustomInput(
                          label: 'Due Date',
                          hint: 'mm/dd/yyyy',
                          controller: _due,
                          suffixIcon: Icons.calendar_today,
                          readOnly: true,
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2100));
                            if (d != null) {
                              _due.text = DateFormat('MM/dd/yyyy').format(d);
                            }
                          })),
                ],
              ),
              const SizedBox(height: 16),
              CustomInput(
                  label: 'Estimated Hours',
                  hint: 'e.g. 40',
                  controller: _hours,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 32),
              CustomButton(
                  text: 'Create Task',
                  onPressed: () {
                    if (_fk.currentState?.validate() ?? false) {
                      Navigator.pop(c);
                      ScaffoldMessenger.of(c).showSnackBar(
                          const SnackBar(content: Text('✅ Task created')));
                    }
                  }),
            ],
          ),
        ),
      ),
    );
  }
}