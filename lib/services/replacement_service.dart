import 'dart:convert';

import 'auth_service.dart';
import 'erp_service.dart';

/// Warranty replacement flow — `Replacement Request` DocType plus the
/// `mobile_control.api.replacement` endpoints on the server (see
/// ERP_NEXT/frappe_docker/docs/warranty-replacement.md).
///
/// Sales rep: [createAndSend] raises a request and moves it to
/// "Pending Approval". Admin approves in ERPNext, which drafts a zero-rate
/// Delivery Note. Delivery person: [myDeliveries] lists what's assigned,
/// [completeDelivery] records the swap (new units given, defective units
/// collected) and the server submits the stock documents.
class ReplacementService {
  ReplacementService._();

  static const doctype = 'Replacement Request';

  static const defectReasons = [
    'Not working',
    'Physical damage',
    'Missing parts',
    'Other',
  ];

  /// The per-company "Defective - <abbr>" warehouse holds goods collected
  /// for brand claims; it must never be offered as a selling warehouse.
  static bool isDefectiveWarehouse(Map<String, dynamic> row) =>
      row['warehouse_name'] == 'Defective';

  /// Creates the request, then applies the workflow's single "Send for
  /// Approval" action via [ErpService.tryAutoProgress]. The create itself
  /// is never undone — a failed send leaves a Draft the rep can resend from
  /// the document screen, and that failure is returned as `error`.
  static Future<({Map<String, dynamic> doc, Object? error})> createAndSend(
    Map<String, dynamic> fields,
  ) async {
    final body = Map<String, dynamic>.from(fields);
    final salesPerson = await ErpService.resolveCurrentSalesPerson();
    if (salesPerson != null) body['sales_person'] = salesPerson;
    final created = await ErpService.createDoc(doctype, body);
    return ErpService.tryAutoProgress(doctype, created);
  }

  /// The current user's own requests, newest first.
  static Future<List<Map<String, dynamic>>> myRequests() async {
    final userId = await AuthService.currentUserId();
    return ErpService.getList(
      doctype,
      filters: [
        if (userId != null) ['owner', '=', userId],
      ],
      fields: const [
        'name',
        'customer',
        'customer_name',
        'request_date',
        'status',
        'total_requested_qty',
        'total_approved_qty',
      ],
      orderBy: 'creation desc',
      limit: 100,
    );
  }

  /// Approved requests assigned to the current delivery user.
  static Future<List<Map<String, dynamic>>> myDeliveries() async {
    final rows = await ErpService.callMethodList(
      '/api/method/mobile_control.api.replacement.get_my_deliveries',
    );
    return rows
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  /// [lines]: `{row, replaced_qty, defective_qty}` per request item row.
  static Future<Map<String, dynamic>> completeDelivery(
    String name,
    List<Map<String, dynamic>> lines,
  ) {
    return ErpService.callMethodPost(
      '/api/method/mobile_control.api.replacement.complete_delivery',
      params: {'name': name, 'lines': jsonEncode(lines)},
    );
  }
}
