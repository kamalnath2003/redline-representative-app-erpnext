import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../local_db/sync_job_type.dart';
import '../services/cache_service.dart';
import '../services/erp_service.dart';
import '../services/item_catalog_service.dart';
import '../services/replacement_service.dart';
import '../services/sync_engine.dart';
import '../services/sync_status_service.dart';
import '../theme/app_theme.dart';
import '../utils/erp_error_handling.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/search_picker.dart';
import '../widgets/swipe_to_confirm_button.dart';
import 'document_detail_screen.dart';

class _RequestLine {
  _RequestLine({required this.itemCode, required this.itemName, this.qty = 1});

  final String itemCode;
  final String itemName;
  double qty;
  String reason = ReplacementService.defectReasons.first;
}

/// Sales rep raises a warranty replacement for defective goods: customer,
/// items with qty and defect reason, and a complaint note. Sending moves it
/// to "Pending Approval"; the admin approves in ERPNext and a delivery
/// person swaps the goods (see [MyDeliveriesScreen]).
class ReplacementRequestScreen extends StatefulWidget {
  const ReplacementRequestScreen({super.key});

  @override
  State<ReplacementRequestScreen> createState() =>
      _ReplacementRequestScreenState();
}

class _ReplacementRequestScreenState extends State<ReplacementRequestScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  PickedRecord? _customer;
  final List<_RequestLine> _lines = [];
  final _complaintController = TextEditingController();
  bool _lastSubmitWasQueued = false;
  String? _error;

  late Future<List<Map<String, dynamic>>> _requests =
      ReplacementService.myRequests();

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _complaintController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    List<String> territories = const [];
    try {
      territories = await ErpService.getExpandedUserTerritories();
    } catch (_) {
      // Offline or unresolved: search the cached customer list unfiltered.
    }
    if (!mounted) return;

    List<PickedRecord> toRecords(Iterable<Map<String, dynamic>> rows) => rows
        .take(300)
        .map(
          (c) => PickedRecord(
            name: c['name'] as String,
            label: (c['customer_name'] as String?) ?? c['name'] as String,
            subtitle: ErpService.customerPickerSubtitle(
              c,
              prefix: c['territory'] as String?,
            ),
            enabled: ErpService.isCustomerSelectable(c),
          ),
        )
        .toList();

    bool matches(Map<String, dynamic> row, String query) {
      final q = query.toLowerCase().trim();
      final text = '${row['name']} ${row['customer_name'] ?? ''}'.toLowerCase();
      final territory = row['territory']?.toString() ?? '';
      return (q.isEmpty || text.contains(q)) &&
          (territories.isEmpty || territories.contains(territory));
    }

    Future<List<PickedRecord>> fromCache(String query) async {
      final cached = await CacheService.readCached('Customer_master', 'master');
      return toRecords(
        (cached?.rows ?? const <Map<String, dynamic>>[]).where(
          (row) => matches(row, query),
        ),
      );
    }

    final result = await showSearchPicker(
      context: context,
      title: 'Select Customer',
      hintText: 'Search customers...',
      search: fromCache,
      backgroundSearch: (query) async {
        if (!SyncStatusService().isOnline) return fromCache(query);
        final rows = await ErpService.getList(
          'Customer',
          filters: [
            if (query.isNotEmpty) ['customer_name', 'like', '%$query%'],
            if (territories.isNotEmpty) ['territory', 'in', territories],
          ],
          fields: const [
            'name',
            'customer_name',
            'territory',
            'disabled',
            'is_frozen',
          ],
          limit: 50,
        );
        return toRecords(rows);
      },
    );
    if (result != null && mounted) setState(() => _customer = result);
  }

  Future<void> _addItems() async {
    String? brandFilter;
    final brands = await ItemCatalogService.cachedBrands();
    List<PickedRecord> toRecords(List<Map<String, dynamic>> rows) => rows
        .map(
          (item) => PickedRecord(
            name: item['name'] as String,
            label: (item['item_name'] as String?) ?? item['name'] as String,
            subtitle: item['brand'] as String?,
            imageUrl: item['image'] as String?,
          ),
        )
        .toList();
    if (!mounted) return;
    final picked = await showMultiItemPicker(
      context: context,
      title: 'Defective Items',
      brands: brands,
      selectedBrand: brandFilter,
      onBrandChanged: (value) => brandFilter = value,
      search: (query) async => toRecords(
        await ItemCatalogService.searchCached(query: query, brand: brandFilter),
      ),
      backgroundSearch: (query) async => toRecords(
        await ItemCatalogService.searchWithPriceList(
          query: query,
          brand: brandFilter,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final p in picked) {
        _lines.add(
          _RequestLine(
            itemCode: p.name,
            itemName: p.label,
            qty: p.quantity > 0 ? p.quantity.toDouble() : 1,
          ),
        );
      }
    });
  }

  Future<bool> _submit() async {
    final customer = _customer;
    if (customer == null || _lines.isEmpty) {
      setState(() => _error = 'Pick a customer and at least one item.');
      return false;
    }
    setState(() {
      _error = null;
      _lastSubmitWasQueued = false;
    });
    final fields = <String, dynamic>{
      'customer': customer.name,
      if (_complaintController.text.trim().isNotEmpty)
        'complaint': _complaintController.text.trim(),
      'items': [
        for (final l in _lines)
          {
            'item_code': l.itemCode,
            'requested_qty': l.qty,
            'defect_reason': l.reason,
          },
      ],
    };

    Future<bool> queue(String message) async {
      await SyncEngine().enqueue(
        type: SyncJobType.replacementRequestCreate,
        payload: fields,
      );
      _lastSubmitWasQueued = true;
      if (!mounted) return true;
      _resetForm();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return true;
    }

    if (!SyncStatusService().isOnline) {
      return queue('Offline. Request saved and will be sent automatically.');
    }
    try {
      final result = await ReplacementService.createAndSend(fields);
      if (!mounted) return true;
      _resetForm();
      final name = result.doc['name'] as String?;
      final sendError = result.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sendError == null
                ? 'Request $name sent for approval.'
                : 'Request $name saved as Draft but could not be sent: '
                      '${handleErpError(context, sendError) ?? ''}',
          ),
        ),
      );
      _refreshRequests();
      _tabController.animateTo(1);
      return true;
    } catch (e) {
      if (e is ErpException && e.isConnectivityFailure) {
        return queue(
          'Connection unavailable. Request saved and will be sent automatically.',
        );
      }
      if (!mounted) return false;
      final message = handleErpError(context, e);
      if (message != null) setState(() => _error = message);
      return false;
    }
  }

  void _resetForm() {
    setState(() {
      _customer = null;
      _lines.clear();
      _complaintController.clear();
    });
  }

  void _refreshRequests() {
    setState(() => _requests = ReplacementService.myRequests());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Replacement Request'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'New Request'),
            Tab(text: 'My Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildForm(), _buildRequestList()],
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.storefront_rounded),
            title: Text(_customer?.label ?? 'Select customer'),
            subtitle: _customer?.subtitle == null
                ? null
                : Text(_customer!.subtitle!),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickCustomer,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Defective items',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            TextButton.icon(
              onPressed: _addItems,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add items'),
            ),
          ],
        ),
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No items yet.',
              style: TextStyle(color: AppColors.midGray),
            ),
          ),
        for (final line in _lines) _buildLine(line),
        const SizedBox(height: 16),
        TextField(
          controller: _complaintController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Complaint (what is wrong?)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.accent)),
        ],
        const SizedBox(height: 24),
        SwipeToConfirmButton(
          label: 'Swipe to send for approval',
          confirmedLabel: 'Sent for approval',
          onConfirmed: _submit,
          wasQueued: () => _lastSubmitWasQueued,
          autoResetAfter: const Duration(seconds: 2),
        ),
      ],
    );
  }

  Widget _buildLine(_RequestLine line) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => setState(() => _lines.remove(line)),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: line.qty > 1
                      ? () => setState(() => line.qty -= 1)
                      : null,
                ),
                Text(
                  line.qty.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 16),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () => setState(() => line.qty += 1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: line.reason,
                    isExpanded: true,
                    items: [
                      for (final r in ReplacementService.defectReasons)
                        DropdownMenuItem(value: r, child: Text(r)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => line.reason = v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestList() {
    return RefreshIndicator(
      onRefresh: () async {
        _refreshRequests();
        await _requests;
      },
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _requests,
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
                        'Could not load requests.',
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
                  child: Text('No replacement requests yet.'),
                ),
              ],
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rows[i];
              final status = (r['status'] as String?) ?? 'Draft';
              return ListTile(
                title: Text(
                  (r['customer_name'] as String?) ?? r['customer'] as String,
                ),
                subtitle: Text(
                  '${r['name']} • ${r['request_date'] ?? ''} • '
                  'Qty ${(r['total_requested_qty'] as num? ?? 0).toStringAsFixed(0)}',
                ),
                trailing: ReplacementStatusChip(status: status),
                onTap: () => context.push(
                  documentDetailRoute(
                    ReplacementService.doctype,
                    r['name'] as String,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Colored chip for the `Replacement Request.status` field — that field,
/// not `workflow_state`, carries the post-approval delivery progress.
class ReplacementStatusChip extends StatelessWidget {
  const ReplacementStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Completed' => AppColors.success,
      'Rejected' || 'Cancelled' => AppColors.accent,
      'Out for Delivery' || 'Partially Completed' => Colors.orange.shade800,
      _ => AppColors.midGray,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
