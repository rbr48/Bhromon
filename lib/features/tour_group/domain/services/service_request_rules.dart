import '../models/service_request_models.dart';

/// Whether [email] may change a request's title, details or category. Only its author
/// may, and only while it is still open: once the committee has moved it on, the words
/// are fixed.
bool canEditServiceRequestText(ServiceRequest request, String email) =>
    request.createdByEmail == email && request.isOpen;

/// Whether [email] may remove a request: its author, or an owner or admin.
bool canDeleteServiceRequest(
  ServiceRequest request,
  String email, {
  required bool isAdmin,
}) =>
    isAdmin || request.createdByEmail == email;

/// Whether a title is long enough and short enough to be a request.
bool isValidServiceRequestTitle(String raw) {
  final length = raw.trim().length;
  return length >= kServiceRequestTitleMin && length <= kServiceRequestTitleMax;
}

/// How many requests stand at each status.
class ServiceRequestCounts {
  const ServiceRequestCounts({
    required this.open,
    required this.inProgress,
    required this.resolved,
  });

  final int open;
  final int inProgress;
  final int resolved;

  int get total => open + inProgress + resolved;
}

/// Counts the requests at each status.
ServiceRequestCounts countServiceRequests(Iterable<ServiceRequest> requests) {
  var open = 0;
  var inProgress = 0;
  var resolved = 0;
  for (final r in requests) {
    switch (r.status) {
      case ServiceRequestStatus.open:
        open++;
      case ServiceRequestStatus.inProgress:
        inProgress++;
      case ServiceRequestStatus.resolved:
        resolved++;
    }
  }
  return ServiceRequestCounts(
    open: open,
    inProgress: inProgress,
    resolved: resolved,
  );
}

/// The requests at [status], or all of them when it is null. The newest comes first;
/// a request with no time yet sorts last.
List<ServiceRequest> filterServiceRequests(
  Iterable<ServiceRequest> requests, {
  ServiceRequestStatus? status,
}) {
  final list = [
    for (final r in requests)
      if (status == null || r.status == status) r,
  ];
  list.sort((a, b) {
    final at = a.createdAt;
    final bt = b.createdAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return list;
}
