import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'info_icon.dart';

class ParamEditor extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final bool readOnly;
  final bool isInt;
  final String? info;
  final ValueChanged<double>? onChanged;

  const ParamEditor({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions = 100,
    this.unit = '',
    this.readOnly = false,
    this.isInt = true,
    this.info,
    this.onChanged,
  });

  @override
  State<ParamEditor> createState() => _ParamEditorState();
}

class _ParamEditorState extends State<ParamEditor> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode()..addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(ParamEditor old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      widget.isInt ? v.round().toString() : v.toStringAsFixed(1);

  void _commit() {
    final parsed = double.tryParse(_ctrl.text.trim());
    if (parsed == null) {
      _ctrl.text = _fmt(widget.value);
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max);
    _ctrl.text = _fmt(clamped);
    widget.onChanged?.call(widget.isInt ? clamped.roundToDouble() : clamped);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.readOnly) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(widget.label, style: theme.textTheme.bodyMedium),
            if (widget.info != null)
              InfoIcon(title: widget.label, message: widget.info!),
            const Spacer(),
            Text(
              '${_fmt(widget.value)}${widget.unit.isEmpty ? '' : ' ${widget.unit}'}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label),
            if (widget.info != null)
              InfoIcon(title: widget.label, message: widget.info!),
            const Spacer(),
            SizedBox(
              width: 88,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textAlign: TextAlign.end,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: const OutlineInputBorder(),
                  suffixText: widget.unit.isEmpty ? null : widget.unit,
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
          ],
        ),
        Slider(
          value: widget.value.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: _fmt(widget.value),
          onChanged: (v) {
            final out = widget.isInt ? v.roundToDouble() : v;
            _ctrl.text = _fmt(out);
            widget.onChanged?.call(out);
          },
        ),
      ],
    );
  }
}
