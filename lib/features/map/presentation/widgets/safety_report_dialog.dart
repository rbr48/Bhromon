import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';

class SafetyReportDialog extends StatefulWidget {
  final LocationPin pin;
  const SafetyReportDialog({super.key, required this.pin});

  static Future<void> show(BuildContext context, LocationPin pin) {
    return showDialog<void>(
      context: context,
      builder: (_) => SafetyReportDialog(pin: pin),
    );
  }

  @override
  State<SafetyReportDialog> createState() => _SafetyReportDialogState();
}

class _SafetyReportDialogState extends State<SafetyReportDialog> {
  String _selectedReason = 'Road blocked';
  final TextEditingController _detailCtrl = TextEditingController();
  bool _submitting = false;

  static const List<String> _reasons = [
    'Road blocked',
    'Flooding',
    'Criminal activity reported',
    'Landslide risk',
    'Place no longer exists',
    'Wrong location on map',
    'Other safety concern',
  ];

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.report_problem_outlined,
              color: Colors.redAccent, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Report Safety Issue',
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📍 ${widget.pin.name}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 14),
          Text('Reason:',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedReason,
            dropdownColor: cs.surfaceContainerHigh,
            style: TextStyle(color: cs.onSurface, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _reasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) =>
                setState(() => _selectedReason = v ?? _selectedReason),
          ),
          const SizedBox(height: 12),
          Text('Additional details (optional):',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _detailCtrl,
            maxLines: 3,
            maxLength: 300,
            style: TextStyle(color: cs.onSurface, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Describe the safety issue...',
              hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 12),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              counterStyle:
                  TextStyle(color: cs.onSurfaceVariant, fontSize: 9),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Submit Report',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final auth = context.read<AuthCubit>().state;
      final uid = auth is Authenticated ? auth.profile.uid : 'anonymous';
      await FirebaseFirestore.instance.collection('safety_reports').add({
        'pinId': widget.pin.pinId,
        'pinName': widget.pin.name,
        'reason': _selectedReason,
        'detail': _detailCtrl.text.trim(),
        'reportedBy': uid,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      // Increment report count on pin
      await FirebaseFirestore.instance
          .collection('location_pins')
          .doc(widget.pin.pinId)
          .update({'reportCount': FieldValue.increment(1)});
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  '🛡️ Safety report submitted. Thank you for keeping explorers safe!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
