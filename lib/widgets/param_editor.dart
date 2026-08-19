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
  final double? step;

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
    this.step,
  });

  @override
  State<ParamEditor> createState() => _ParamEditorState();
}

class _ParamEditorState extends State<ParamEditor> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  double get _step => widget.step ?? (widget.isInt ? 1.0 : 0.1);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode()
      ..addListener(() {
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

  void _nudge(double delta) {
    final next = (widget.value + delta).clamp(widget.min, widget.max);
    final out = widget.isInt ? next.roundToDouble() : next;
    _ctrl.text = _fmt(out);
    widget.onChanged?.call(out);
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

    final unit = widget.unit.trim();

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
              width: 120,
              height: 42,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      textAlign: TextAlign.left,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.fromLTRB(
                          10,
                          10,
                          unit.isEmpty ? 10 : 8,
                          unit.isEmpty ? 10 : 16,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _commit(),
                    ),
                  ),
                  if (unit.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 4,
                      child: IgnorePointer(
                        child: Text(
                          unit,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 10,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '-$_step',
              onPressed: () => _nudge(-_step),
              icon: const Icon(Icons.remove_circle_outline, size: 22),
            ),
            Expanded(
              child: Slider(
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
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '+$_step',
              onPressed: () => _nudge(_step),
              icon: const Icon(Icons.add_circle_outline, size: 22),
            ),
          ],
        ),
      ],
    );
  }
}
