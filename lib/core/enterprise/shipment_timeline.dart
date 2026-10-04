import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/load.dart';

/// How far one truck leg has got.
enum LegStage { posted, assigned, inTransit, delivered, cancelled }

LegStage legStage(Load? load, Booking? booking) {
  if (load == null) return LegStage.posted;
  if (load.cancelled) return LegStage.cancelled;
  if (booking != null && booking.status == BookingStatus.delivered) return LegStage.delivered;
  if (booking != null && booking.status != BookingStatus.cancelled) {
    final i = BookingStatus.flow.indexOf(booking.status);
    return i >= BookingStatus.flow.indexOf(BookingStatus.pickedUp) ? LegStage.inTransit : LegStage.assigned;
  }
  if (load.status == LoadStatus.matched) return LegStage.assigned;
  if (load.status == LoadStatus.closed) return LegStage.delivered;
  return LegStage.posted;
}

enum TimelineState { done, current, pending, cancelled }

/// One line of the shipment timeline: leg (1/2) and stage it represents.
class TimelineStep {
  final int leg;
  final LegStage stage;
  final TimelineState state;
  const TimelineStep(this.leg, this.stage, this.state);
}

/// Eight steps (posted, driver assigned, in transit, delivered for each
/// leg). Leg 2 cannot be ahead of leg 1: its steps stay pending until leg 1
/// has been delivered to the hub.
List<TimelineStep> shipmentTimeline(LegStage leg1, LegStage leg2) {
  const order = [LegStage.posted, LegStage.assigned, LegStage.inTransit, LegStage.delivered];
  final steps = <TimelineStep>[];
  var currentPlaced = false;
  for (final (leg, stage) in [(1, leg1), (2, leg1 == LegStage.delivered ? leg2 : LegStage.posted)]) {
    for (final s in order) {
      TimelineState state;
      if (stage == LegStage.cancelled) {
        state = s == LegStage.posted ? TimelineState.done : TimelineState.cancelled;
      } else if (order.indexOf(s) <= order.indexOf(stage) && !(leg == 2 && leg1 != LegStage.delivered)) {
        state = TimelineState.done;
      } else if (!currentPlaced) {
        state = TimelineState.current;
        currentPlaced = true;
      } else {
        state = TimelineState.pending;
      }
      steps.add(TimelineStep(leg, s, state));
    }
  }
  return steps;
}

bool shipmentComplete(LegStage leg1, LegStage leg2) => leg1 == LegStage.delivered && leg2 == LegStage.delivered;
