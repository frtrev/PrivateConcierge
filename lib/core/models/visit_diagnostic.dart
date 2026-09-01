class VisitDiagnostic {
  const VisitDiagnostic({
    required this.at,
    required this.event,
    required this.detail,
  });

  final DateTime at;
  final String event;
  final String detail;
}
