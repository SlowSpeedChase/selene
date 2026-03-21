import SeleneShared

/// Disambiguate SeleneShared.Thread from Foundation.Thread
/// This typealias ensures that unqualified `Thread` in SeleneChat resolves
/// to the Selene model type, not Foundation's threading class.
typealias Thread = SeleneShared.Thread
