import 'package:googleapis_auth/auth_io.dart';

abstract class GoogleAuthService {
  final List<String> scopes;
  GoogleAuthService(this.scopes);

  dynamic get currentUser;
  Future<AuthClient> getAuthenticatedClient();
}

GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    throw UnsupportedError('Cannot create a GoogleAuthService');