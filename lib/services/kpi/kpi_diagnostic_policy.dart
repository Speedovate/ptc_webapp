/// Missing historical truck assignments are not synchronization failures.
bool isKpiAssignmentNotice(String issue) => RegExp(
  r'^Booking [^:\n]+: (?:No PM assigned;|Truck not recorded\.)',
).hasMatch(issue.trim());

/// KPI read/validation diagnostics do not represent failed queued actions.
bool isObsoleteKpiDiagnosticLog(Map<String, dynamic> row) =>
    row['kind'] == 'kpi_diagnostic';
