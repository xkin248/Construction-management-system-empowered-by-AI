import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateHelper {
  static String format(DateTime d, [String pattern = 'dd/MM/yyyy']) =>
      DateFormat(pattern).format(d);
  static String formatApi(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String formatMd(DateTime d) => DateFormat('MM/dd/yyyy').format(d);
  static String formatTime(DateTime d) => DateFormat('HH:mm').format(d);
  static String formatDateTime(DateTime d) =>
      DateFormat('dd/MM/yyyy HH:mm').format(d);
  static String? tryFormat(DateTime? d, [String pattern = 'dd/MM/yyyy']) =>
      d == null ? null : format(d, pattern);
  static double? hoursBetween(DateTime? a, DateTime? b) {
    if (a == null || b == null || !b.isAfter(a)) return null;
    return b.difference(a).inMinutes / 60;
  }
  static bool isLate(DateTime checkIn, TimeOfDay threshold) {
    final t = checkIn.hour * 60 + checkIn.minute;
    final th = threshold.hour * 60 + threshold.minute;
    return t > th;
  }
  static String todayApi() => formatApi(DateTime.now());
}