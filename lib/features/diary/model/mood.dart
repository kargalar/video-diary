class Mood {
  final String id;
  final String emoji;
  final String label;

  const Mood({required this.id, required this.emoji, required this.label});

  static const List<Mood> defaults = [
    Mood(id: 'happy', emoji: '😊', label: 'Happy'),
    Mood(id: 'sad', emoji: '😢', label: 'Sad'),
    Mood(id: 'angry', emoji: '😡', label: 'Angry'),
    Mood(id: 'calm', emoji: '😌', label: 'Calm'),
    Mood(id: 'tired', emoji: '😴', label: 'Tired'),
    Mood(id: 'excited', emoji: '😍', label: 'Excited'),
    Mood(id: 'disappointed', emoji: '😔', label: 'Disappointed'),
  ];

  static final Map<String, Mood> _defaultsById = {for (final mood in defaults) mood.id: mood};

  String get displayText => '$emoji $label';

  Mood copyWith({String? id, String? emoji, String? label}) {
    return Mood(id: id ?? this.id, emoji: emoji ?? this.emoji, label: label ?? this.label);
  }

  Map<String, dynamic> toJson() => {'id': id, 'emoji': emoji, 'label': label};

  factory Mood.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] as String?)?.trim();
    final id = (json['id'] as String?)?.trim();
    return Mood(id: (id != null && id.isNotEmpty) ? id : createId(label ?? 'Mood'), emoji: ((json['emoji'] as String?)?.trim().isNotEmpty ?? false) ? (json['emoji'] as String).trim() : '🙂', label: (label != null && label.isNotEmpty) ? label : 'Mood');
  }

  static Mood? fromDynamic(dynamic value) {
    if (value is String) return fromString(value);
    if (value is Map) return Mood.fromJson(Map<String, dynamic>.from(value));
    return null;
  }

  static Mood? fromString(String value) => _defaultsById[value];

  static String createId(String label) {
    final base = label.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'-{2,}'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return base.isEmpty ? 'mood' : base;
  }

  static String createUniqueId(String label, Iterable<Mood> existing) {
    final taken = existing.map((m) => m.id).toSet();
    final base = createId(label);
    if (!taken.contains(base)) return base;

    var counter = 2;
    while (taken.contains('$base-$counter')) {
      counter += 1;
    }
    return '$base-$counter';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || (other is Mood && other.id == id && other.emoji == emoji && other.label == label);
  }

  @override
  int get hashCode => Object.hash(id, emoji, label);
}
