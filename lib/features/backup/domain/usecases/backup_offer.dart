/// When to offer backup (docs/designs/never_lose_history.md §7): on the
/// summary of the 3rd finished workout; "Not now" → once more after the 10th;
/// then only in Settings. Never at first launch, never to someone who already
/// has it on. Pure, so every case is a unit test.
bool shouldOfferBackup({
  required int finishedWorkouts,
  required int dismissals,
  required bool enabled,
  required bool flagOn,
}) {
  if (!flagOn || enabled) return false;
  return switch (dismissals) {
    0 => finishedWorkouts >= 3,
    1 => finishedWorkouts >= 10,
    _ => false,
  };
}
