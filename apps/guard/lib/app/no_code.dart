import '../data/models.dart';

/// What the resident said on the callback. Only a callback to a registered number counts;
/// an inbound caller ID never does.
enum CallOutcome {
  confirmed('confirmed', 'Confirmed'),
  saidNo('declined', 'Said no'),
  noAnswer('no_answer', 'No answer');

  const CallOutcome(this.api, this.label);

  /// The `outcome` the sync endpoint expects.
  final String api;
  final String label;
}

enum NoCodeStep {
  /// Pick a resident and call them.
  call,

  /// One call went unanswered: call again or try someone else.
  tryAgain,

  /// The resident confirmed: ask the guest's name, then in now or expected later.
  confirmed,

  /// Said no, or no answer twice: do not admit on phone authority. Show the walk-in policy;
  /// turn the guest away, or record the CSO's decision to admit.
  stop,
}

/// The No code flow for one home: a guest at the gate with no code, or a resident calling the
/// gate about a guest. Pure state, so the outcomes are tested without widgets.
class NoCodeFlow {
  NoCodeFlow(this.home);
  final Home home;

  int noAnswers = 0;

  /// Who said no, if anyone did.
  Resident? saidNoBy;

  /// The call the guard just made, waiting for its outcome.
  (Resident, PhoneNumber)? calling;

  /// Who confirmed, and on which number (the callback record and the visit need both).
  (Resident, PhoneNumber)? confirmedBy;

  NoCodeStep get step {
    if (confirmedBy != null) return NoCodeStep.confirmed;
    if (saidNoBy != null || noAnswers >= 2) return NoCodeStep.stop;
    if (noAnswers == 1) return NoCodeStep.tryAgain;
    return NoCodeStep.call;
  }

  void call(Resident r, PhoneNumber n) => calling = (r, n);

  /// Records the outcome of the call in progress and returns the next step.
  NoCodeStep record(CallOutcome outcome) {
    final c = calling;
    if (c == null) throw StateError('No call in progress');
    calling = null;
    switch (outcome) {
      case CallOutcome.confirmed:
        confirmedBy = c;
      case CallOutcome.saidNo:
        saidNoBy = c.$1;
      case CallOutcome.noAnswer:
        noAnswers++;
    }
    return step;
  }

  /// Why the gate stopped, for the refusal record when the guard gives no other reason.
  String get stopReason => saidNoBy != null ? '${saidNoBy!.name} said no on the callback' : 'No answer on two calls to ${home.displayAddress}';
}
