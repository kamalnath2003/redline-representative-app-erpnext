import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/customer_visit_service.dart';
import '../services/erp_service.dart';
import '../theme/app_theme.dart';

/// بعد إرسال طلبية/فاتورة بنجاح — يسأل المندوب هل يسجل زيارة لنفس العميل،
/// ولو "نعم" ياخد ملاحظة اختيارية، يلتقط GPS best-effort (زي
/// [CustomerVisitsScreen])، وينشئ `Customer Visit` وقد يربطها بالمستند
/// المُنشأ (`reference_doctype`/`reference_name`). فشل تسجيل الزيارة نفسها
/// (لو حصل) ميرجعش المستند الأساسي أو يوقف تدفق الشاشة — هو إضافة، مش شرط.
Future<void> promptLogVisit(
  BuildContext context, {
  required String customer,
  String? territory,
  required String referenceDoctype,
  String? referenceName,
  int? referenceJobId,
  bool includeReference = true,
  String visitType = 'Visit',
  String? receiptNumber,
}) async {
  final wantsToLog = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      title: const Text('Log visit'),
      content: const Text('Would you like to log a visit for this customer?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  if (wantsToLog != true || !context.mounted) return;

  final notesController = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      title: const Text('Visit notes'),
      content: TextFormField(
        controller: notesController,
        maxLines: 3,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Notes (optional)...'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final notes = notesController.text.trim();
  notesController.dispose();
  if (confirmed != true) return;

  try {
    final location = await _captureVisitLocation();
    if (location == null) {
      if (context.mounted) await _showLocationRequired(context);
      return;
    }
    final visitBody = <String, dynamic>{
      'customer': customer,
      'visit_type': visitType,
      if (territory != null && territory.isNotEmpty) 'territory': territory,
      if (notes.isNotEmpty) 'notes': notes,
      if (receiptNumber != null && receiptNumber.trim().isNotEmpty)
        'receipt_number': receiptNumber.trim(),
      'location': location,
      if (includeReference &&
          referenceName != null &&
          referenceName.isNotEmpty) ...{
        'reference_doctype': referenceDoctype,
        'reference_name': referenceName,
      } else if (includeReference && referenceJobId != null) ...{
        'reference_doctype': referenceDoctype,
      },
    };
    final result = await CustomerVisitService.save(
      visitBody,
      dependsOnJobId: referenceJobId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.queued
                ? 'Visit saved and will be sent when you are back online'
                : 'Visit logged successfully',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ErpException
                ? 'The $referenceDoctype was saved, but the visit was not recorded: ${e.toString()}'
                : 'The $referenceDoctype was saved, but the visit could not be saved locally. Please try again.',
          ),
        ),
      );
    }
  }
}

Future<void> _showLocationRequired(BuildContext context) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  final permission = await Geolocator.checkPermission();
  if (!context.mounted) return;
  final openSettings = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Location required'),
      content: const Text(
        'A location is required to log a visit. Turn on GPS and grant RCD Sales location permission, then try again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
  if (openSettings != true) return;
  if (!serviceEnabled) {
    await Geolocator.openLocationSettings();
  } else if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
  }
}

Future<String?> _captureVisitLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {},
          'geometry': {
            'type': 'Point',
            'coordinates': [position.longitude, position.latitude],
          },
        },
      ],
    });
  } catch (_) {
    return null;
  }
}
