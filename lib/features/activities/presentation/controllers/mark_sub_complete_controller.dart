import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../providers/activities_providers.dart';
import 'sub_activity_detail_controller.dart';

sealed class MarkCompleteState {
  const MarkCompleteState();
}

final class MarkCompleteIdle extends MarkCompleteState {
  const MarkCompleteIdle();
}

final class MarkCompleteSubmitting extends MarkCompleteState {
  const MarkCompleteSubmitting();
}

final class MarkCompleteFailed extends MarkCompleteState {
  const MarkCompleteFailed(this.failure);
  final Failure failure;
}

/// Drives the PREVIOUS web's "Mark Complete" form
/// (`templates/activities/sub_activity.html:157-179`; removed in CB 3.0, where
/// completion is automatic — the UI only offers this for legacy markup). This controller
/// only tracks the submit action's own transient state — whether the
/// sub-activity IS now completed is never guessed client-side; on success
/// it invalidates `SubActivityDetailController`, so the screen's "completed"
/// UI only ever appears once the server's own next GET confirms it.
class MarkSubCompleteController extends Notifier<MarkCompleteState> {
  MarkSubCompleteController(this.key);

  final SubActivityDetailKey key;

  @override
  MarkCompleteState build() => const MarkCompleteIdle();

  Future<void> submit() async {
    if (state is MarkCompleteSubmitting) return;
    // Never send a completion request for a non-positive id (the old `-1`
    // sentinel): fail locally, without touching the repository/network.
    if (key.subActivityId <= 0) {
      state = const MarkCompleteFailed(UnexpectedFailure('This sub-activity cannot be marked complete.'));
      return;
    }
    state = const MarkCompleteSubmitting();
    final result = await ref.read(activitiesRepositoryProvider).markSubComplete(key.subActivityId);
    switch (result) {
      case Success():
        state = const MarkCompleteIdle();
        ref.invalidate(subActivityDetailControllerProvider(key));
      case Failed(failure: final failure):
        state = MarkCompleteFailed(failure);
    }
  }
}

final markSubCompleteControllerProvider =
    NotifierProvider.family<MarkSubCompleteController, MarkCompleteState, SubActivityDetailKey>(
      MarkSubCompleteController.new,
    );
