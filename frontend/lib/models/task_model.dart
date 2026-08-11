class TaskModel {
  final int id;
  final int userId;
  final String description;
  final String priority;
  final String status;
  final String source;

  TaskModel({
    required this.id,
    required this.userId,
    required this.description,
    required this.priority,
    required this.status,
    required this.source,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'],
      userId: json['user_id'],
      description: json['description'],
      priority: json['priority'],
      status: json['status'],
      source: json['source'],
    );
  }
}