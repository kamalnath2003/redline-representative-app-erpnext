import '../local_db/sync_job_type.dart';
import 'erp_service.dart';
import 'sync_engine.dart';
import 'sync_status_service.dart';

class CustomerVisitSaveResult {
  const CustomerVisitSaveResult({required this.queued, this.name});

  final bool queued;
  final String? name;
}

/// Shared online/offline save path for the Log Visit screen and visit prompts.
class CustomerVisitService {
  const CustomerVisitService._();

  static Future<CustomerVisitSaveResult> save(
    Map<String, dynamic> visitBody, {
    int? dependsOnJobId,
  }) async {
    final body = Map<String, dynamic>.from(visitBody);
    if (dependsOnJobId != null || !SyncStatusService().isOnline) {
      await _enqueue(body, dependsOnJobId);
      return const CustomerVisitSaveResult(queued: true);
    }

    final salesPerson = await ErpService.resolveCurrentSalesPerson();
    if (salesPerson != null) body['sales_person'] = salesPerson;
    try {
      final created = await ErpService.createDoc('Customer Visit', body);
      return CustomerVisitSaveResult(
        queued: false,
        name: created['name'] as String?,
      );
    } on ErpException catch (e) {
      if (!e.isConnectivityFailure) rethrow;
      await _enqueue(body, dependsOnJobId);
      return const CustomerVisitSaveResult(queued: true);
    }
  }

  static Future<void> _enqueue(
    Map<String, dynamic> body,
    int? dependsOnJobId,
  ) async {
    await SyncEngine().enqueue(
      type: SyncJobType.customerVisitCreate,
      payload: body,
      dependsOnJobId: dependsOnJobId,
    );
  }
}
