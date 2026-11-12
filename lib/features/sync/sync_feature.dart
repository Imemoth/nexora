/// The synchronization feature flag (decision D-F). OFF by default: with the flag
/// off the engine never touches the network and no sync control is shown.
/// A build turns it on with `--dart-define=NEXORA_SYNC=true`.
const bool syncFeatureEnabled = bool.fromEnvironment('NEXORA_SYNC');
