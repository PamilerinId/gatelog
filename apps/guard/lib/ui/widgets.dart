import 'package:url_launcher/url_launcher.dart';

/// Opens the native dialler. The full number appears only here, in the `tel:` URI.
/// Replaced in widget tests, where there is no dialler.
Future<bool> Function(String number) dial = (number) async {
  try {
    return await launchUrl(Uri(scheme: 'tel', path: number.replaceAll(' ', '')));
  } catch (_) {
    return false;
  }
};
