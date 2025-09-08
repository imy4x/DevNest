class Hub {
  final String id;
  final String name;
  final String secretCode;
  final String leaderUserId;

  Hub({
    required this.id,
    required this.name,
    required this.secretCode,
    required this.leaderUserId,
  });

  factory Hub.fromJson(Map<String, dynamic> json) {
    return Hub(
      id: json['id'],
      name: json['name'],
      secretCode: json['secret_code'],
      leaderUserId: json['leader_user_id'],
    );
  }
}
