import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/ui/app_toast.dart';
import 'package:gym_tracker/features/workout/domain/usecases/edit_plan.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Says why the editor refused to add an exercise (a short toast). Errors
/// that can't happen from the library's screens say nothing.
void showPlanEditError(BuildContext context, PlanEditError error) {
  final l10n = context.l10n;
  final message = switch (error) {
    PlanEditError.duplicate => l10n.libraryAlreadyInDay,
    PlanEditError.tooMany => l10n.libraryDayFull,
    PlanEditError.lockedDay => l10n.planLocked,
    PlanEditError.notAllowed => l10n.libraryNotAllowed,
    PlanEditError.lastDay ||
    PlanEditError.notFound ||
    PlanEditError.invalidName => null,
  };
  if (message == null) return;
  AppToast.show(message, direction: Directionality.of(context));
}
