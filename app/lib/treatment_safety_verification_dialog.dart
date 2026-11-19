import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TreatmentSafetyVerificationDialog extends StatefulWidget {
  const TreatmentSafetyVerificationDialog({
    required this.organizationId,
    required this.operationId,
    required this.productName,
    required this.registrationCountry,
    required this.registrationNumber,
    required this.registrationStatus,
    required this.registrationValidUntil,
    required this.cropName,
    required this.greenhouseName,
    required this.zoneName,
    super.key,
  });

  final String organizationId;
  final String operationId;
  final String productName;
  final String? registrationCountry;
  final String? registrationNumber;
  final String? registrationStatus;
  final String? registrationValidUntil;
  final String cropName;
  final String greenhouseName;
  final String zoneName;

  @override
  State<TreatmentSafetyVerificationDialog> createState() =>
      _TreatmentSafetyVerificationDialogState();
}

class _TreatmentSafetyVerificationDialogState
    extends State<TreatmentSafetyVerificationDialog> {
  final _scope = TextEditingController();
  final _labelVersion = TextEditingController();
  final _sourceUrl = TextEditingController();
  final _harvestMinutes = TextEditingController();
  final _reentryMinutes = TextEditingController();
  final _notes = TextEditingController();

  DateTime _sourceCheckedAt = DateTime.now();
  bool _labelAttested = false;
  bool _scopeAttested = false;
  bool _intervalsAttested = false;
  bool _busy = false;
  String? _error;

  DateTime? get _registrationExpiry =>
      DateTime.tryParse(widget.registrationValidUntil ?? '');

  bool get _registrationReady {
    final expiry = _registrationExpiry;
    final number = widget.registrationNumber?.trim() ?? '';
    // The farm's business timezone is Europe/Moscow (UTC+03:00).
    final moscowNow = DateTime.now().toUtc().add(const Duration(hours: 3));
    final localToday = DateTime(moscowNow.year, moscowNow.month, moscowNow.day);
    return widget.registrationCountry?.trim().toUpperCase() == 'RU' &&
        widget.registrationStatus == 'active' &&
        number.isNotEmpty &&
        expiry != null &&
        !DateTime(expiry.year, expiry.month, expiry.day).isBefore(localToday);
  }

  String _dateText(DateTime? value) {
    if (value == null) return 'не указана';
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  @override
  void initState() {
    super.initState();
    final scopeParts = <String>[
      if (widget.cropName.isNotEmpty) 'Культура: ${widget.cropName}',
      'Место применения: защищённый грунт',
      if (widget.greenhouseName.isNotEmpty)
        'Теплица: ${widget.greenhouseName}',
      if (widget.zoneName.isNotEmpty) 'Зона: ${widget.zoneName}',
    ];
    _scope.text = scopeParts.join('; ');
  }

  @override
  void dispose() {
    _scope.dispose();
    _labelVersion.dispose();
    _sourceUrl.dispose();
    _harvestMinutes.dispose();
    _reentryMinutes.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _chooseSourceDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _sourceCheckedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Когда проверен источник',
    );
    if (selected != null && mounted) {
      setState(() {
        _sourceCheckedAt = DateTime(
          selected.year,
          selected.month,
          selected.day,
          12,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_registrationReady) {
      setState(() => _error =
          'Сначала заполни и проверь карточку препарата: страна РФ, действующий статус, номер и срок регистрации.');
      return;
    }

    final scope = _scope.text.trim();
    final labelVersion = _labelVersion.text.trim();
    final source = Uri.tryParse(_sourceUrl.text.trim());
    final harvest = int.tryParse(_harvestMinutes.text.trim());
    final reentry = int.tryParse(_reentryMinutes.text.trim());

    if (scope.isEmpty || labelVersion.isEmpty) {
      setState(() => _error =
          'Укажи область применения (культуру и защищённый грунт) и версию этикетки.');
      return;
    }
    if (source == null ||
        source.scheme.toLowerCase() != 'https' ||
        source.host.isEmpty) {
      setState(() => _error = 'Укажи корректную HTTPS-ссылку на источник.');
      return;
    }
    if (harvest == null || harvest < 0 || reentry == null || reentry < 0) {
      setState(() => _error =
          'Введи оба интервала целым числом минут. Неизвестный интервал нельзя подтверждать.');
      return;
    }
    if (!_labelAttested || !_scopeAttested || !_intervalsAttested) {
      setState(() => _error =
          'Для подтверждения отметь все три пункта проверки.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.rpc('verify_treatment_safety', params: {
        'p_organization_id': widget.organizationId,
        'p_operation_id': widget.operationId,
        'p_registration_reference': widget.registrationNumber!.trim(),
        'p_crop_and_site_scope': scope,
        'p_label_version': labelVersion,
        'p_source_url': _sourceUrl.text.trim(),
        'p_source_checked_at': _sourceCheckedAt.toUtc().toIso8601String(),
        'p_harvest_wait_minutes': harvest,
        'p_reentry_wait_minutes': reentry,
        'p_label_review_attested': _labelAttested,
        'p_scope_review_attested': _scopeAttested,
        'p_intervals_review_attested': _intervalsAttested,
        'p_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Не удалось сохранить подтверждение. Проверь соединение и повтори попытку.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiry = _registrationExpiry;
    return AlertDialog(
      title: const Text('Проверка безопасности обработки'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.productName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Страна регистрации: ${widget.registrationCountry ?? 'не указана'}'),
                      Text('Номер регистрации: ${widget.registrationNumber?.isNotEmpty == true ? widget.registrationNumber : 'не указан'}'),
                      Text('Статус: ${widget.registrationStatus ?? 'не указан'}'),
                      Text('Действует до: ${_dateText(expiry)}'),
                      if (!_registrationReady) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Карточка препарата не подтверждает действующую регистрацию РФ. Сначала исправь регистрационные сведения; эта форма не может заменить их.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _scope,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Культура и область применения',
                  helperText: 'Проверь культуру, объект воздействия и применение именно в защищённом грунте.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _labelVersion,
                decoration: const InputDecoration(
                  labelText: 'Версия / дата этикетки',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sourceUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'HTTPS-ссылка на официальный реестр или этикетку',
                  helperText: 'Сайт и документ проверяет ответственный специалист; приложение не удостоверяет подлинность ссылки.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseSourceDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Дата проверки источника: ${_dateText(_sourceCheckedAt)}'),
              ),
              const SizedBox(height: 12),
              Text(
                'Интервалы из проверенной инструкции',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _harvestMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'До сбора, минут',
                        helperText: 'Только значение из этикетки',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _reentryMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'До входа, минут',
                        helperText: 'Только значение из этикетки',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: _labelAttested,
                onChanged: _busy ? null : (value) => setState(() => _labelAttested = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Сверил действующую регистрацию РФ и этикетку, применимую на дату обработки.'),
              ),
              CheckboxListTile(
                value: _scopeAttested,
                onChanged: _busy ? null : (value) => setState(() => _scopeAttested = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Убедился, что культура, объект воздействия и защищённый грунт входят в область применения.'),
              ),
              CheckboxListTile(
                value: _intervalsAttested,
                onChanged: _busy ? null : (value) => setState(() => _intervalsAttested = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Оба интервала дословно сверены с инструкцией; приложение их не рассчитывало.'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Примечание (необязательно)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Если инструкция задаёт условие, которое нельзя выразить фиксированным числом минут (например, «до полного высыхания»), не подтверждай обработку в этой форме: оставь статус «требует проверки». Нормы и дозировки приложение не предлагает.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy || !_registrationReady ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Подтвердить проверку'),
        ),
      ],
    );
  }
}
