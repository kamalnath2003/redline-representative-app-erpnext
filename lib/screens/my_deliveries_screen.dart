import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../local_db/sync_job_type.dart';
import '../services/erp_service.dart';
import '../services/replacement_service.dart';
import '../services/sync_engine.dart';
import '../services/sync_status_service.dart';
import '../theme/app_theme.dart';
import '../utils/erp_error_handling.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/swipe_to_confirm_button.dart';
import 'replacement_request_screen.dart';

/// Delivery person's queue of approved warranty replacements. Each one is a
/// swap at the customer: hand over the new units (from the approved
/// warehouse) and take back the defective ones.
class MyDeliveriesScreen extends StatefulWidget {
  const MyDeliveriesScreen({super.key});

  @override
  State<MyDeliveriesScreen> createState() => _MyDeliveriesScreenState();
}

class _MyDeliveriesScreenState extends State<MyDeliveriesScreen> {
  late Future<List<Map<String, dynamic>>> _deliveries =
      ReplacementService.myDeliveries();

  void _refresh() {
    setState(() => _deliveries = ReplacementService.myDeliveries());
  }

  Future<void> _open(Map<String, dynamic> delivery) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _DeliveryConfirmScreen(delivery: delivery),
      ),
    );
    if (done == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Deliveries')),
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh();
          await _deliveries;
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _deliveries,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingIndicator();
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      handleErpError(context, snapshot.error!) ??
                          'Could not load deliveries.',
                    ),
                  ),
                ],
              );
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No replacements waiting for delivery.'),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = rows[i];
                final items = (d['items'] as List?) ?? const [];
                final units = items.fold<num>(
                  0,
                  (sum, it) => sum + ((it as Map)['approved_qty'] as num? ?? 0),
                );
                return ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: Text(
                    (d['customer_name'] as String?) ?? d['customer'] as String,
                  ),
                  subtitle: Text(
                    '${d['name']} • ${items.length} item(s), '
                    '${units.toStringAsFixed(0)} unit(s)'
                    '${d['customer_mobile'] != null ? ' • ${d['customer_mobile']}' : ''}'
                    '${d['customer_address'] != null ? '\n${(d['customer_address'] as String).replaceAll('\n', ', ')}' : ''}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: d['customer_address'] != null,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _open(d),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SwapLine {
  _SwapLine(Map<String, dynamic> row)
    : rowName = row['name'] as String,
      itemName = (row['item_name'] as String?) ?? row['item_code'] as String,
      brand = row['brand'] as String?,
      reason = row['defect_reason'] as String?,
      approved = (row['approved_qty'] as num? ?? 0).toDouble(),
      replaced = (row['approved_qty'] as num? ?? 0).toDouble(),
      defective = (row['approved_qty'] as num? ?? 0).toDouble();

  final String rowName;
  final String itemName;
  final String? brand;
  final String? reason;
  final double approved;
  double replaced;
  double defective;
}

class _DeliveryConfirmScreen extends StatefulWidget {
  const _DeliveryConfirmScreen({required this.delivery});

  final Map<String, dynamic> delivery;

  @override
  State<_DeliveryConfirmScreen> createState() => _DeliveryConfirmScreenState();
}

class _DeliveryConfirmScreenState extends State<_DeliveryConfirmScreen> {
  late final List<_SwapLine> _lines = [
    for (final row in (widget.delivery['items'] as List? ?? const []))
      if (((row as Map)['approved_qty'] as num? ?? 0) > 0)
        _SwapLine(Map<String, dynamic>.from(row)),
  ];
  bool _lastSubmitWasQueued = false;
  String? _error;

  String get _name => widget.delivery['name'] as String;

  Future<bool> _confirm() async {
    final lines = [
      for (final l in _lines)
        {
          'row': l.rowName,
          'replaced_qty': l.replaced,
          'defective_qty': l.defective,
        },
    ];
    setState(() {
      _error = null;
      _lastSubmitWasQueued = false;
    });

    Future<bool> queue(String message) async {
      await SyncEngine().enqueue(
        type: SyncJobType.replacementDeliveryComplete,
        payload: {'name': _name, 'lines': lines},
      );
      _lastSubmitWasQueued = true;
      if (!mounted) return true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
      return true;
    }

    if (!SyncStatusService().isOnline) {
      return queue('Offline. Delivery saved and will be sent automatically.');
    }
    try {
      final result = await ReplacementService.completeDelivery(_name, lines);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_name: ${result['status'] ?? 'Delivered'}'),
        ),
      );
      Navigator.of(context).pop(true);
      return true;
    } catch (e) {
      if (e is ErpException && e.isConnectivityFailure) {
        return queue(
          'Connection unavailable. Delivery saved and will be sent automatically.',
        );
      }
      if (!mounted) return false;
      final message = handleErpError(context, e);
      if (message != null) setState(() => _error = message);
      return false;
    }
  }

  Widget _counter({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_rounded),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${value.toStringAsFixed(0)} / ${max.toStringAsFixed(0)}',
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  /// Delivery address card. No in-app map: the rep copies it into their
  /// maps app (the app has no URL-launching dependency).
  Widget _buildAddress(String? address) {
    if (address == null || address.trim().isEmpty) {
      return const Text(
        'No address on file for this customer.',
        style: TextStyle(color: AppColors.midGray),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.location_on_outlined, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(address)),
            IconButton(
              tooltip: 'Copy address',
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: address.replaceAll('\n', ', ')),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Address copied')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            (d['customer_name'] as String?) ?? d['customer'] as String,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (d['customer_mobile'] != null) Text('${d['customer_mobile']}'),
          const SizedBox(height: 8),
          _buildAddress(d['customer_address'] as String?),
          const SizedBox(height: 8),
          ReplacementStatusChip(status: (d['status'] as String?) ?? ''),
          if ((d['complaint'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text('Complaint: ${d['complaint']}'),
          ],
          if (d['source_warehouse'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Take new stock from: ${d['source_warehouse']}',
              style: const TextStyle(color: AppColors.midGray),
            ),
          ],
          const SizedBox(height: 16),
          for (final l in _lines)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.itemName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        if (l.brand != null) l.brand!,
                        if (l.reason != null) l.reason!,
                      ].join(' • '),
                      style: const TextStyle(color: AppColors.midGray),
                    ),
                    _counter(
                      label: 'New given',
                      value: l.replaced,
                      max: l.approved,
                      onChanged: (v) => setState(() => l.replaced = v),
                    ),
                    _counter(
                      label: 'Defective collected',
                      value: l.defective,
                      max: l.approved,
                      onChanged: (v) => setState(() => l.defective = v),
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.accent)),
          ],
          const SizedBox(height: 24),
          SwipeToConfirmButton(
            label: 'Swipe to confirm swap',
            confirmedLabel: 'Delivery recorded',
            onConfirmed: _confirm,
            wasQueued: () => _lastSubmitWasQueued,
          ),
        ],
      ),
    );
  }
}
