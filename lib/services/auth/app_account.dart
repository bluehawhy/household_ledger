/// Display identity only; never contains authentication tokens.
class AppAccount {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  const AppAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  factory AppAccount.fromJson(Map<String, dynamic> json) => AppAccount(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String?,
    photoUrl: json['photoUrl'] as String?,
  );

  static AppAccount? fromUser(dynamic user) {
    if (user == null) return null;
    if (user is AppAccount) return user;
    return AppAccount(
      id: user.id as String,
      email: user.email as String,
      displayName: user.displayName as String?,
      photoUrl: user.photoUrl as String?,
    );
  }
}
