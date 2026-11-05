// lib/features/tour_group/presentation/widgets/fund/mfs_settlement_sheet.dart
//
// Flutter UI bottom sheet for recording MFS (bKash/Nagad/Rocket/Upay) settlements,
// pasting confirmation SMS messages to auto-fill TrxID & fees, and manager one-tap verification.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/expense_models.dart';
import '../../../domain/services/mfs_sms_parser.dart';
import '../../../domain/services/trip_ledger_engine.dart';

class MfsSettlementSheet extends StatefulWidget {
  final String tourId;
  final List<LedgerMember> members;
  final String currentUserEmail;
  final bool isGroupManager;
  final List<ExpenseItem> existingExpenses;
  final List<SettlementRecord> existingSettlements;
  final ValueChanged<SettlementRecord> onSaveSettlement;
  final String? initialFromMemberId;
  final String? initialToMemberId;
  final int? initialAmountPaisa;

  const MfsSettlementSheet({
    super.key,
    required this.tourId,
    required this.members,
    required this.currentUserEmail,
    this.isGroupManager = false,
    required this.existingExpenses,
    required this.existingSettlements,
    required this.onSaveSettlement,
    this.initialFromMemberId,
    this.initialToMemberId,
    this.initialAmountPaisa,
  });

  @override
  State<MfsSettlementSheet> createState() => _MfsSettlementSheetState();
}

class _MfsSettlementSheetState extends State<MfsSettlementSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _feeController = TextEditingController(text: '0');
  final _trxIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  late String _fromMemberId;
  late String _toMemberId;
  MfsProvider _selectedProvider = MfsProvider.bkash;
  bool _feeAbsorbedByGroup = false;
  bool _markVerifiedImmediately = false;
  DateTime _selectedDate = DateTime.now();
  String? _duplicateError;

  @override
  void initState() {
    super.initState();
    _fromMemberId = widget.initialFromMemberId ??
        (widget.members.isNotEmpty ? widget.members.first.id : '');
    _toMemberId = widget.initialToMemberId ??
        (widget.members.length > 1 ? widget.members[1].id : _fromMemberId);
    if (widget.initialAmountPaisa != null && widget.initialAmountPaisa! > 0) {
      _amountController.text =
          (widget.initialAmountPaisa! / 100).toStringAsFixed(2);
    }
    _markVerifiedImmediately = widget.isGroupManager;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _feeController.dispose();
    _trxIdController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pasteAndParseSms() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clip?.text?.trim() ?? '';
    if (raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ক্লিপবোর্ডে কোনো SMS টেক্সট পাওয়া যায়নি।')),
      );
      return;
    }

    final parsed = MfsSmsParser.parse(raw);
    if (parsed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS থেকে bKash/Nagad/Rocket TrxID শনাক্ত করা যায়নি।'),
        ),
      );
      return;
    }

    setState(() {
      _selectedProvider = parsed.provider;
      _trxIdController.text = parsed.trxId;
      _amountController.text = (parsed.amountPaisa / 100).toStringAsFixed(2);
      _feeController.text = (parsed.feePaisa / 100).toStringAsFixed(2);
      if (parsed.counterpartyMaskedPhone != null) {
        _phoneController.text = parsed.counterpartyMaskedPhone!;
      }
      if (parsed.transactionTime != null) {
        _selectedDate = parsed.transactionTime!;
      }
      _duplicateError = null;
    });
  }

  void _estimateCashOutFee() {
    final amountTaka = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amountTaka <= 0) return;
    final bps = _selectedProvider.defaultCashOutFeeBps;
    final estimatedFee = (amountTaka * bps) / 10000.0;
    setState(() {
      _feeController.text = estimatedFee.toStringAsFixed(2);
    });
  }

  void _submit() {
    setState(() => _duplicateError = null);
    if (!_formKey.currentState!.validate()) return;

    final trxId = _trxIdController.text.trim().toUpperCase();
    if (_selectedProvider.requiresTrxId) {
      final isDup = MfsTrxIdValidator.isDuplicateTrxId(
        tourId: widget.tourId,
        trxId: trxId,
        expenses: widget.existingExpenses,
        settlements: widget.existingSettlements,
      );
      if (isDup) {
        setState(() {
          _duplicateError =
              'এই TrxID ($trxId) ইতিপূর্বে এই গ্রুপে ব্যবহৃত হয়েছে!';
        });
        return;
      }
    }

    final amountPaisa =
        ((double.tryParse(_amountController.text.trim()) ?? 0) * 100).round();
    final feePaisa =
        ((double.tryParse(_feeController.text.trim()) ?? 0) * 100).round();

    final fromMember = widget.members.firstWhere((m) => m.id == _fromMemberId);
    final toMember = widget.members.firstWhere((m) => m.id == _toMemberId);

    final status = (!_selectedProvider.requiresTrxId ||
            (widget.isGroupManager && _markVerifiedImmediately))
        ? MfsVerificationStatus.verified
        : MfsVerificationStatus.unverified;

    final mfsInfo = MfsPaymentInfo(
      provider: _selectedProvider,
      trxId: _selectedProvider.requiresTrxId ? trxId : null,
      senderMaskedPhone: _phoneController.text.trim().isEmpty
          ? null
          : MfsSmsParser.maskBdPhone(_phoneController.text.trim()),
      feePaisa: feePaisa,
      feeAbsorbedByGroup: _feeAbsorbedByGroup,
      status: status,
      verifiedByUserId: status == MfsVerificationStatus.verified
          ? widget.currentUserEmail
          : null,
      verifiedAt:
          status == MfsVerificationStatus.verified ? DateTime.now() : null,
    );

    final record = SettlementRecord(
      id: 'set_${DateTime.now().millisecondsSinceEpoch}',
      tourId: widget.tourId,
      fromMemberId: fromMember.id,
      fromMemberName: fromMember.name,
      toMemberId: toMember.id,
      toMemberName: toMember.name,
      amountPaisa: amountPaisa,
      date: _selectedDate,
      mfsInfo: mfsInfo,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      addedByEmail: widget.currentUserEmail,
    );

    widget.onSaveSettlement(record);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'বকেয়া পরিশোধ / MFS জমা (Settle-Up)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  TextButton.icon(
                    onPressed: _pasteAndParseSms,
                    icon: const Icon(Icons.content_paste_go, size: 18),
                    label: const Text('SMS পেস্ট করুন'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: MfsProvider.values.map((provider) {
                  return ChoiceChip(
                    label: Text(provider.banglaLabel),
                    selected: _selectedProvider == provider,
                    onSelected: (_) {
                      setState(() {
                        _selectedProvider = provider;
                        _duplicateError = null;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _fromMemberId,
                      decoration: const InputDecoration(
                        labelText: 'প্রদানকারী (Sender)',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.members
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _fromMemberId = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _toMemberId,
                      decoration: const InputDecoration(
                        labelText: 'গ্রহণকারী (Receiver)',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.members
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _toMemberId = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'পরিমাণ (৳ BDT)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final val = double.tryParse(v?.trim() ?? '');
                        if (val == null || val <= 0) {
                          return 'সঠিক টাকার পরিমাণ লিখুন';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _feeController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'MFS চার্জ (৳)',
                        border: const OutlineInputBorder(),
                        suffixIcon: _selectedProvider.defaultCashOutFeeBps > 0
                            ? IconButton(
                                tooltip: 'অটো ক্যাশ-আউট ফি হিসাব করুন',
                                icon: const Icon(Icons.calculate_outlined),
                                onPressed: _estimateCashOutFee,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedProvider.requiresTrxId) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _trxIdController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: '${_selectedProvider.shortLabel} TrxID',
                    hintText: 'যেমন: BKL890XYZ1',
                    border: const OutlineInputBorder(),
                    errorText: _duplicateError,
                  ),
                  validator: (val) => MfsTrxIdValidator.validateFormat(
                    provider: _selectedProvider,
                    trxId: val,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText:
                        'প্রেরকের মোবাইল নম্বর (ঐচ্ছিক - শেষ ৪ ডিজিট সংরক্ষিত হবে)',
                    hintText: '017XXXXXXXX',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    const Text('ক্যাশ-আউট চার্জ প্রেরকের জমা হিসেবে যুক্ত হবে'),
                value: _feeAbsorbedByGroup,
                onChanged: (val) => setState(() => _feeAbsorbedByGroup = val),
              ),
              if (widget.isGroupManager && _selectedProvider.requiresTrxId)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                      'অ্যাডমিন হিসেবে এখনই TrxID যাচাইকৃত (Verified) হিসেবে চিহ্নিত করুন'),
                  value: _markVerifiedImmediately,
                  onChanged: (val) =>
                      setState(() => _markVerifiedImmediately = val ?? false),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('জমা সংরক্ষণ করুন'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
