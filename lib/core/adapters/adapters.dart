// Paid-readiness (MASTER-6 Task 46): the places where a paid service plugs in.
// Each adapter is a small interface, a fake used in tests and demos, and a
// "not configured" default that fails in a calm, typed way. The app today uses
// the free paths; docs/PAID_ADAPTERS.md says how to plug a provider in and
// which contract test it must pass (test/adapter_contract_test.dart).
export 'kyc_adapter.dart';
export 'maps_adapter.dart';
export 'payment_adapter.dart';
export 'push_adapter.dart';
export 'sms_adapter.dart';
export 'storage_adapter.dart';
