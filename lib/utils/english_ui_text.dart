/// Converts known Arabic workflow labels to English for display while leaving
/// the original server values untouched for filtering and workflow requests.
String englishUiText(String value, {required String fallback}) {
  const translations = <String, String>{
    'إرسال للاعتماد': 'Submit for Approval',
    'إعادة إرسال للاعتماد': 'Resubmit for Approval',
    'طلب تعديل': 'Request Changes',
    'رفض': 'Reject',
    'تعديل': 'Edit',
    'في انتظار مدير المنطقة': 'Awaiting Area Manager',
    'في انتظار الحسابات': 'Awaiting Accounts',
    'مطلوب تعديل': 'Changes Requested',
    'مرفوض': 'Rejected',
    'مقبول': 'Approved',
    'معتمد': 'Approved',
    'ملغي': 'Cancelled',
    'مسودة': 'Draft',
  };

  final normalized = value.trim();
  final translated = translations[normalized];
  if (translated != null) return translated;
  if (RegExp(r'[\u0600-\u06FF]').hasMatch(normalized)) return fallback;
  return normalized;
}
