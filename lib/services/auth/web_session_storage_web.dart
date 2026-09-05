// This adapter is selected only by a web conditional import.
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Map<String, String> sessionStorage() => html.window.sessionStorage;
String? webClientId() => html.document
    .querySelector('meta[name="google-signin-client_id"]')
    ?.getAttribute('content');
