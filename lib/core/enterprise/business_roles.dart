/// Roles of a company account (A4, BIZ4). The owner is the customer with the
/// company profile; the others join by phone invite. Keep the table in sync
/// with the `bizRoleIn(...)` lists in firestore.rules (DOC10).
class BizRole {
  BizRole._();
  static const owner = 'owner';
  static const manager = 'manager';
  static const dispatch = 'dispatch';
  static const accounts = 'accounts';
  static const viewer = 'viewer';

  /// Posts loads only (the first team role, kept for older members).
  static const booker = 'booker';

  /// Roles an owner can give to a member.
  static const assignable = [manager, dispatch, accounts, viewer, booker];
  static const all = [owner, ...assignable];
}

/// What a role may do (BIZ5).
class BizPerm {
  BizPerm._();
  static const postLoads = 'postLoads';
  static const viewBookings = 'viewBookings';
  static const approveLoads = 'approveLoads';
  static const manageTeam = 'manageTeam';
  static const viewStatements = 'viewStatements';
  static const manageExpenses = 'manageExpenses';
  static const managePool = 'managePool';
  static const manageContracts = 'manageContracts';
  static const businessSupport = 'businessSupport';
  static const all = [postLoads, viewBookings, approveLoads, manageTeam, viewStatements, manageExpenses, managePool, manageContracts, businessSupport];
}

const _table = <String, Set<String>>{
  BizRole.owner: {...BizPerm.all},
  BizRole.manager: {
    BizPerm.postLoads, BizPerm.viewBookings, BizPerm.approveLoads, BizPerm.viewStatements,
    BizPerm.manageExpenses, BizPerm.managePool, BizPerm.manageContracts, BizPerm.businessSupport,
  },
  BizRole.dispatch: {BizPerm.postLoads, BizPerm.viewBookings, BizPerm.managePool},
  BizRole.accounts: {BizPerm.viewBookings, BizPerm.viewStatements, BizPerm.manageExpenses, BizPerm.businessSupport},
  BizRole.viewer: {BizPerm.viewBookings, BizPerm.viewStatements},
  BizRole.booker: {BizPerm.postLoads, BizPerm.viewBookings},
};

bool bizCan(String? role, String perm) => _table[role]?.contains(perm) ?? false;

/// Roles that hold [perm], for the lists in the rules and for tests.
List<String> bizRolesWith(String perm) => [for (final r in BizRole.all) if (bizCan(r, perm)) r];

/// The company a user acts for and the role they have there.
class BizContext {
  final String ownerId;
  final String role;
  const BizContext(this.ownerId, this.role);

  bool can(String perm) => bizCan(role, perm);
  bool get isOwner => role == BizRole.owner;
}
