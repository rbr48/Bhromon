import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/models/itinerary_models.dart';
import '../../../domain/models/tour_activity_models.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/notice_engine.dart';

const _sheet = Color(0xFF142428);
const _chip = Color(0xFF1E3326);

String noticeKindLabel(AppLocalizations l10n, NoticeKind k) =>
    l10n.translate('notice_kind_${k.name}');

Color noticeKindColor(NoticeKind k) => switch (k) {
      NoticeKind.emergency => Colors.redAccent,
      NoticeKind.schedule => const Color(0xFF38BDF8),
      NoticeKind.meetup => Colors.amber,
      NoticeKind.reminder => const Color(0xFFC084FC),
      NoticeKind.rule => const Color(0xFFFB923C),
      NoticeKind.rollcall => AppColors.mintGreen,
      NoticeKind.announcement => Colors.white70,
    };

/// Writes a new notice or edits [existing]. Returns the notice to save; its
/// id is empty for a new one. [now] fixes the clock in tests.
Future<TourNotice?> showNoticeComposer(
  BuildContext context, {
  required TourGroup? group,
  TourNotice? existing,
  DateTime? now,
}) {
  return showModalBottomSheet<TourNotice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheet,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) =>
        _Composer(group: group, existing: existing, now: now ?? DateTime.now()),
  );
}

class _Composer extends StatefulWidget {
  const _Composer({required this.group, this.existing, required this.now});

  final TourGroup? group;
  final TourNotice? existing;
  final DateTime now;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final TourNotice? e = widget.existing;
  late final _title = TextEditingController(text: e?.title ?? '');
  late final _body = TextEditingController(text: e?.content ?? '');
  late final _place = TextEditingController(
      text:
          e?.place ?? (e == null ? widget.group?.meetingPointTitle ?? '' : ''));
  late final _map = TextEditingController(
      text: e?.mapUrl ??
          (e == null ? widget.group?.meetingPointMapUrl ?? '' : ''));
  late NoticeKind _kind = e?.kind ?? NoticeKind.announcement;
  late DateTime? _eventAt = e?.eventAt;
  late bool _autoExpire = e == null ||
      e!.eventAt == null ||
      e!.expiresAt == NoticeEngine.defaultExpiry(e!.kind, e!.eventAt);
  late DateTime? _until = e?.eventAt == null ? e?.expiresAt : null;
  late bool _pinned = e?.pinned ?? false;
  late bool _urgent = e?.urgent ?? false;
  late bool _ack = e?.requireAck ?? false;
  late String? _stopId = e?.stopId ?? widget.group?.stopOn(widget.now)?.id;
  String? _templateId;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _place.dispose();
    _map.dispose();
    super.dispose();
  }

  void _applyTemplate(NoticeTemplate t) {
    final l10n = context.l10n;
    setState(() {
      _templateId = t.id;
      _kind = t.kind;
      _title.text = l10n.translate('notice_tpl_${t.id}_title');
      _body.text = l10n.translate('notice_tpl_${t.id}_body');
      _ack = t.requireAck || t.kind == NoticeKind.rollcall;
      _urgent = t.urgent;
      if (t.leadMinutes != null) {
        _eventAt = _roundUp(widget.now.add(Duration(minutes: t.leadMinutes!)));
      }
    });
  }

  /// To the next quarter hour, as tour leaders announce times.
  static DateTime _roundUp(DateTime d) {
    final extra = (15 - d.minute % 15) % 15;
    return DateTime(d.year, d.month, d.day, d.hour, d.minute + extra);
  }

  Future<void> _pickEventTime() async {
    final base = _eventAt ?? _roundUp(widget.now.add(const Duration(hours: 1)));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2022),
      lastDate: DateTime(2035),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null) return;
    setState(() => _eventAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickUntil() async {
    final base = _until ?? widget.now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2022),
      lastDate: DateTime(2035),
    );
    if (date != null) {
      setState(
          () => _until = DateTime(date.year, date.month, date.day, 23, 59));
    }
  }

  void _save() {
    final l10n = context.l10n;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = l10n.translate('notice_err_title'));
      return;
    }
    if (_kind.isTimed && _eventAt == null) {
      setState(() => _error = l10n.translate('notice_err_time'));
      return;
    }
    final map = _map.text.trim();
    if (map.isNotEmpty && !map.startsWith('https://')) {
      setState(() => _error = l10n.translate('tour_map_link_needs_https'));
      return;
    }
    final expires = _eventAt != null
        ? (_autoExpire ? NoticeEngine.defaultExpiry(_kind, _eventAt) : null)
        : _until;
    final place = _place.text.trim();
    Navigator.pop(
      context,
      TourNotice(
        id: e?.id ?? '',
        title: title,
        content: _body.text.trim(),
        author: e?.author ?? '',
        authorEmail: e?.authorEmail ?? '',
        createdAt: e?.createdAt ?? widget.now,
        urgent: _urgent || _kind == NoticeKind.emergency,
        kind: _kind,
        pinned: _pinned,
        eventAt: _eventAt,
        expiresAt: expires,
        place: place.isEmpty ? null : place,
        mapUrl: map.isEmpty ? null : map,
        stopId: _stopId,
        requireAck: _ack || _kind == NoticeKind.rollcall,
        ackBy: e?.ackBy ?? const [],
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged,
          {String? help}) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label, style: const TextStyle(color: Colors.white)),
        subtitle: help == null
            ? null
            : Text(help,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
        value: value,
        activeThumbColor: AppColors.mintGreen,
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stops = widget.group?.effectiveStops ?? const <TourStop>[];
    final fmt = DateFormat('EEE d MMM, h:mm a');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      builder: (context, scroll) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text(
                l10n.translate(e == null
                    ? 'tour_notice_new_title'
                    : 'tour_notice_edit_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            if (e == null) ...[
              const SizedBox(height: 10),
              Text(l10n.translate('notice_templates'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in kNoticeTemplates)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          backgroundColor:
                              _templateId == t.id ? AppColors.mintGreen : _chip,
                          label: Text(
                              '${t.kind.emoji} ${l10n.translate('notice_tpl_${t.id}_title')}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _templateId == t.id
                                      ? AppColors.darkGreen
                                      : Colors.white)),
                          onPressed: () => _applyTemplate(t),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in NoticeKind.values)
                  ChoiceChip(
                    label: Text('${k.emoji} ${noticeKindLabel(l10n, k)}',
                        style: const TextStyle(fontSize: 12)),
                    selected: _kind == k,
                    selectedColor: noticeKindColor(k),
                    backgroundColor: _chip,
                    labelStyle: TextStyle(
                        color: _kind == k ? Colors.black : Colors.white),
                    onSelected: (_) => setState(() {
                      _kind = k;
                      if (k.asksEveryone) _ack = true;
                    }),
                  ),
              ],
            ),
            TextField(
              controller: _title,
              maxLength: 100,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  labelText: l10n.translate('tour_notice_heading')),
            ),
            TextField(
              controller: _body,
              maxLines: 4,
              minLines: 2,
              maxLength: 1000,
              style: const TextStyle(color: Colors.white),
              decoration:
                  InputDecoration(labelText: l10n.translate('tour_details')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.schedule_rounded,
                  color: _kind.isTimed ? AppColors.gold : Colors.white38),
              title: Text(
                  _eventAt == null
                      ? l10n.translate(_kind.isTimed
                          ? 'notice_set_time'
                          : 'notice_set_time_optional')
                      : fmt.format(_eventAt!),
                  style: const TextStyle(color: Colors.white)),
              trailing: _eventAt == null
                  ? null
                  : IconButton(
                      tooltip: l10n.translate('notice_clear_time'),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54),
                      onPressed: () => setState(() => _eventAt = null),
                    ),
              onTap: _pickEventTime,
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final m in const [15, 30, 60, 120])
                  ActionChip(
                    backgroundColor: _chip,
                    label: Text(
                        l10n.translate('notice_in_minutes',
                            args: {'n': l10n.number(m)}),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                    onPressed: () => setState(() => _eventAt =
                        _roundUp(widget.now.add(Duration(minutes: m)))),
                  ),
                ActionChip(
                  backgroundColor: _chip,
                  label: Text(l10n.translate('notice_tomorrow_morning'),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                  onPressed: () => setState(() => _eventAt = DateTime(
                      widget.now.year,
                      widget.now.month,
                      widget.now.day + 1,
                      7)),
                ),
              ],
            ),
            if (_eventAt != null)
              _switch(l10n.translate('notice_auto_archive'), _autoExpire,
                  (v) => setState(() => _autoExpire = v),
                  help: l10n.translate('notice_auto_archive_help'))
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading:
                    const Icon(Icons.event_busy_rounded, color: Colors.white54),
                title: Text(
                    _until == null
                        ? l10n.translate('notice_until_none')
                        : l10n.translate('notice_until', args: {
                            'date': DateFormat('d MMM').format(_until!)
                          }),
                    style: const TextStyle(color: Colors.white)),
                trailing: _until == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white54),
                        onPressed: () => setState(() => _until = null),
                      ),
                onTap: _pickUntil,
              ),
            TextField(
              controller: _place,
              maxLength: 120,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.place_rounded,
                      color: Colors.amber, size: 20),
                  labelText: l10n.translate('notice_place')),
            ),
            TextField(
              controller: _map,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.map_rounded,
                      color: Colors.white54, size: 20),
                  labelText: l10n.translate('tour_map_link_label'),
                  helperText: l10n.translate('notice_map_help'),
                  helperStyle: const TextStyle(color: Colors.white38)),
            ),
            if (stops.length > 1)
              DropdownButtonFormField<String?>(
                initialValue:
                    stops.any((s) => s.id == _stopId) ? _stopId : null,
                dropdownColor: const Color(0xFF1B4332),
                decoration:
                    InputDecoration(labelText: l10n.translate('notice_stop')),
                items: [
                  DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.translate('notice_stop_all'))),
                  for (final s in stops)
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _stopId = v),
              ),
            const SizedBox(height: 6),
            _switch(
                l10n.translate(_kind == NoticeKind.rollcall
                    ? 'notice_ack_rollcall'
                    : 'notice_ack'),
                _ack || _kind == NoticeKind.rollcall,
                _kind == NoticeKind.rollcall
                    ? (_) {}
                    : (v) => setState(() => _ack = v),
                help: l10n.translate('notice_ack_help')),
            _switch(l10n.translate('notice_pin'), _pinned,
                (v) => setState(() => _pinned = v),
                help: l10n.translate('notice_pin_help')),
            _switch(
                l10n.translate('tour_notice_urgent'),
                _urgent || _kind == NoticeKind.emergency,
                _kind == NoticeKind.emergency
                    ? (_) {}
                    : (v) => setState(() => _urgent = v)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 6),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: AppColors.darkGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _save,
              child: Text(l10n.translate('tour_post'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
