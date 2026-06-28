import 'package:stacked/stacked.dart';
import 'package:webapp/models/client_member.dart';
import 'package:webapp/requests/client_member.request.dart';
import 'package:webapp/repositories/interfaces/client_member_repository.dart';

class ClientMembersViewModel extends BaseViewModel {
  ClientMembersViewModel({ClientMemberRepository? repository})
    : _repository = repository ?? ClientMemberRequest.instance;

  final ClientMemberRepository _repository;

  static final Map<String, List<ClientMember>> _cachedMembersByClientId = {};

  static void clearCachedState() {
    _cachedMembersByClientId.clear();
  }

  final List<ClientMember> _members = [];
  String _searchQuery = '';
  String _activeFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  String? _clientId;

  List<ClientMember> get members => List.unmodifiable(_members);
  String get searchQuery => _searchQuery;
  String get activeFilter => _activeFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;

  Future<void> load(String clientId) async {
    if (isBusy) {
      return;
    }
    _clientId = clientId;
    final cachedMembers = _cachedMembersByClientId[clientId];
    if (cachedMembers != null && cachedMembers.isNotEmpty) {
      _members
        ..clear()
        ..addAll(cachedMembers);
      notifyListeners();
    }

    setBusy(true);
    try {
      await _repository.initialize();
      final loadedMembers = await _repository.getMembersForClient(clientId);
      _members
        ..clear()
        ..addAll(loadedMembers);
      _cachedMembersByClientId[clientId] = List<ClientMember>.from(_members);
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  void setSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }
    _searchQuery = value;
    notifyListeners();
  }

  bool matches(ClientMember member) {
    final query = _searchQuery.trim().toLowerCase();
    final haystack = [
      member.name,
      member.email,
      member.phone,
      member.position,
    ].whereType<String>().join(' ').toLowerCase();
    final matchesQuery = query.isEmpty || haystack.contains(query);
    final isActive = member.isActive ?? true;
    final matchesActive = switch (_activeFilter) {
      'Active' => isActive,
      'Inactive' => !isActive,
      _ => true,
    };
    final createdAt = member.createdAt;
    final matchesStart =
        _startDate == null ||
        (createdAt != null && !_startsBeforeDay(createdAt, _startDate!));
    final matchesEnd =
        _endDate == null ||
        (createdAt != null && !_startsAfterDay(createdAt, _endDate!));
    return matchesQuery && matchesActive && matchesStart && matchesEnd;
  }

  void updateActiveFilter(String value) {
    if (_activeFilter == value) {
      return;
    }
    _activeFilter = value;
    notifyListeners();
  }

  void updateStartDate(DateTime? value) {
    _startDate = value;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      _endDate = _startDate;
    }
    notifyListeners();
  }

  void updateEndDate(DateTime? value) {
    _endDate = value;
    if (_startDate != null &&
        _endDate != null &&
        _startDate!.isAfter(_endDate!)) {
      _startDate = _endDate;
    }
    notifyListeners();
  }

  void clearFilters() {
    var changed = false;
    if (_activeFilter != 'All') {
      _activeFilter = 'All';
      changed = true;
    }
    if (_startDate != null) {
      _startDate = null;
      changed = true;
    }
    if (_endDate != null) {
      _endDate = null;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<ClientMember> save(ClientMember member) async {
    setBusy(true);
    try {
      final saved = await _repository.saveMember(member);
      final existingIndex = _members.indexWhere((item) => item.id == saved.id);
      if (existingIndex >= 0) {
        _members[existingIndex] = saved;
      } else {
        _members.add(saved);
      }
      _sortMembers();
      if (_clientId != null) {
        _cachedMembersByClientId[_clientId!] = List<ClientMember>.from(_members);
      }
      notifyListeners();
      return saved;
    } finally {
      setBusy(false);
    }
  }

  Future<void> delete(ClientMember member) async {
    setBusy(true);
    try {
      await _repository.deleteMember(
        member.id ?? '',
        clientId: member.clientId ?? _clientId,
      );
      _members.removeWhere((item) => item.id == member.id);
      _sortMembers();
      if (_clientId != null) {
        _cachedMembersByClientId[_clientId!] = List<ClientMember>.from(_members);
      }
      notifyListeners();
    } finally {
      setBusy(false);
    }
  }

  void _sortMembers() {
    _members.sort((a, b) {
      if ((a.isActive ?? true) != (b.isActive ?? true)) {
        return (b.isActive ?? true) ? 1 : -1;
      }
      final aDate = a.updatedAt ?? a.createdAt;
      final bDate = b.updatedAt ?? b.createdAt;
      if (aDate == null && bDate == null) {
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      }
      if (aDate == null) {
        return 1;
      }
      if (bDate == null) {
        return -1;
      }
      return bDate.compareTo(aDate);
    });
  }

  String formatDate(DateTime? value) {
    if (value == null) {
      return 'All';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day/${value.year.toString().padLeft(2, '0')}';
  }

  bool _startsBeforeDay(DateTime value, DateTime boundary) {
    final normalizedValue = DateTime(value.year, value.month, value.day);
    final normalizedBoundary = DateTime(
      boundary.year,
      boundary.month,
      boundary.day,
    );
    return normalizedValue.isBefore(normalizedBoundary);
  }

  bool _startsAfterDay(DateTime value, DateTime boundary) {
    final normalizedValue = DateTime(value.year, value.month, value.day);
    final normalizedBoundary = DateTime(
      boundary.year,
      boundary.month,
      boundary.day,
    );
    return normalizedValue.isAfter(normalizedBoundary);
  }
}
