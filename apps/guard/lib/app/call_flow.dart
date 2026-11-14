/// The Phone call flow (Guard-Call), as plain state with the records it makes, so every outcome
/// is tested without widgets. The screen shows [CallFlow.step] and calls the methods here.
///
/// Only a callback to a registered number, or the home PIN, verifies a caller. The inbound
/// caller ID is a hint: it offers the home first and goes on the records masked
/// (`caller_masked`); after a confirmed callback it can be offered as the resident's new number.
library;

import '../core/estate_time.dart';
import '../data/models.dart';
import '../sync/capture.dart' show VoiceClip;
import 'admission.dart';
import 'caller.dart';
import 'controller.dart';

/// What the resident said on the callback.
enum CallOutcome {
  confirmed('confirmed'),
  saidNo('declined'),
  noAnswer('no_answer');

  const CallOutcome(this.api);

  /// The `outcome` the sync endpoint expects.
  final String api;
}

enum CallStep {
  /// Call back a registered number of the home (or: they gave the home PIN; call the supervisor).
  callback,

  /// Back from the dialler: "House called back", say the visitor's name, "Did they say yes?".
  answer,

  /// A guest with a code whose home wants a call first, and the home said yes: "Let them in?".
  letIn,

  /// "Are they here now?" (with the name to say first, if it was not said yet).
  hereNow,

  /// How long are they staying (a visit for later).
  stay,

  /// The home PIN keypad (4 digits, 3 tries per call).
  pin,

  /// Three wrong PINs: call back, or the supervisor.
  pinLocked,

  /// Which CSO decides (skipped when the CSO is the one signed in).
  pickCso,

  /// Why the CSO would let them in, as tiles.
  csoReason,

  /// "Other": the reason, said.
  csoOther,

  /// "Let them in?" on the CSO's word.
  csoLetIn,

  /// "Add this number for Mrs Adeyemi?"
  offerNumber,

  /// Recorded. [CallFlow.result] says what.
  done,
}

/// How the guest was verified, for the entry's method.
enum CallProof { callback, pin, cso }

enum CallResult { letIn, expected, turnedAway }

class CallFlow {
  CallFlow(this.c, this.home, {this.visit, this.caller});

  final GateController c;
  final Home home;

  /// A guest with a code whose home wants a call before anyone comes in.
  final Visit? visit;

  /// The last incoming call (within 10 minutes), if the phone saw one.
  final IncomingCall? caller;

  CallStep step = CallStep.callback;
  CallProof? proof;

  // --- the callback ---
  (Resident, PhoneNumber)? dialled;
  DateTime? calledBackAt;
  int noAnswers = 0;
  Resident? confirmedBy;
  ConfirmedCall? _confirmedCall;

  // --- the home PIN ---
  static const pinTries = 3;
  int pinWrong = 0;

  // --- the name, said ---
  VoiceClip? nameClip;

  // --- the CSO ---
  String? stopWhy;
  Guard? decider;
  CsoReason? reason;
  VoiceClip? reasonClip;

  // --- what was recorded ---
  CallResult? result;
  String? recordId;
  bool numberOffered = false;

  String? get callerMasked => caller?.masked;

  /// The CSO is the one signed in: they decide, alone.
  bool get decidingAlone => c.isCso;

  /// The home's numbers to call back, the caller's own first when they rang from one.
  List<(Resident, PhoneNumber)> get numbers {
    final all = [
      for (final r in home.residents)
        for (final n in r.numbers) (r, n),
    ];
    final from = caller == null ? null : toE164(caller!.number);
    all.sort((a, b) => (toE164(b.$2.e164) == from ? 1 : 0) - (toE164(a.$2.e164) == from ? 1 : 0));
    return all;
  }

  bool get homeHasPin => home.houseCodeHash != null;

  /// The resident confirmed on the callback, but the call to the gate came from a number not
  /// on file for this home: offer to add it.
  bool get canOfferNumber => caller != null && confirmedBy != null && proof == CallProof.callback && !isRegisteredTo(caller!.number, home);

  // --- the callback --------------------------------------------------------------------------

  /// The guard tapped Call back: the dialler opens. Back on the screen, the answer step.
  void dialling(Resident r, PhoneNumber n) {
    dialled = (r, n);
  }

  void calledBack(DateTime at) {
    calledBackAt = at;
    step = CallStep.answer;
  }

  /// "Did they say yes?" Yes, No, or No answer. A confirmed call is recorded at once, so it is
  /// on file whatever the guard does next.
  Future<CallStep> answer(CallOutcome outcome) async {
    final d = dialled;
    if (d == null) throw StateError('No call was made.');
    final (r, n) = d;
    switch (outcome) {
      case CallOutcome.confirmed:
        _confirmedCall = await c.recordConfirmedCall(homeId: home.id, numberId: n.id, visitId: visit?.id);
        confirmedBy = r;
        proof = CallProof.callback;
        step = visit != null ? CallStep.letIn : CallStep.hereNow;
      case CallOutcome.saidNo:
        await c.recordCallback(homeId: home.id, numberId: n.id, outcome: outcome.api, visitId: visit?.id);
        stopWhy = '${r.name} said no on the callback';
        step = _toCso();
      case CallOutcome.noAnswer:
        await c.recordCallback(homeId: home.id, numberId: n.id, outcome: outcome.api, visitId: visit?.id);
        noAnswers++;
        if (noAnswers >= 2) {
          stopWhy = 'No answer on two calls to ${home.displayAddress}';
          step = _toCso();
        } else {
          step = CallStep.callback;
        }
    }
    return step;
  }

  /// "Call supervisor", from any step before a decision.
  CallStep supervisor() {
    stopWhy ??= 'The guard called the supervisor';
    return step = _toCso();
  }

  CallStep _toCso() {
    proof = CallProof.cso;
    if (decidingAlone) {
      decider = c.guard;
      return CallStep.csoReason;
    }
    return CallStep.pickCso;
  }

  // --- the home PIN ---------------------------------------------------------------------------

  void wantPin() => step = CallStep.pin;

  /// One try. Every try is a `pin_checks` record. Right: on to the name and "here now?".
  /// The third wrong try stops the PIN for this call.
  Future<bool> tryPin(String pin) async {
    final ok = await c.checkGatePin(home.id, pin, callerMasked: callerMasked) ?? false;
    if (ok) {
      proof = CallProof.pin;
      step = CallStep.hereNow;
      return true;
    }
    pinWrong++;
    if (pinWrong >= pinTries) step = CallStep.pinLocked;
    return false;
  }

  int get pinTriesLeft => pinTries - pinWrong;

  /// After three wrong PINs: call the home back instead.
  void backToCallback() => step = CallStep.callback;

  // --- here now, or later ----------------------------------------------------------------------

  /// "Are they here now?" No: how long they will stay.
  void notHereNow() => step = CallStep.stay;

  /// In now, with what the cameras took. Returns the entry's id.
  Future<String> letIn(GatePhotos photos) async {
    final v = visit;
    final String id;
    switch (proof) {
      case CallProof.callback when v != null:
        id = await c.admitWithCode(v, photos: photos);
      case CallProof.callback:
        id = await c.admitOnCallback(home.id, null, photos: photos, clip: nameClip, callerMasked: callerMasked);
      case CallProof.pin:
        id = await c.admitOnPin(home.id, photos: photos, clip: nameClip, callerMasked: callerMasked);
      case CallProof.cso:
        id = await c.admitWalkIn(
          homeId: home.id,
          guestName: v?.guestName,
          visitId: v?.id,
          decidedBy: decider!.id,
          reason: reason!.api,
          photos: photos,
          clip: nameClip,
          reasonClip: reasonClip,
          callerMasked: callerMasked,
        );
      case null:
        throw StateError('Nobody verified this guest.');
    }
    recordId = id;
    result = CallResult.letIn;
    step = canOfferNumber ? CallStep.offerNumber : CallStep.done;
    return id;
  }

  /// Coming later: a visit for the stay picked. After a callback it is linked from the call;
  /// after the home PIN it is PIN-verified.
  Future<String> expect(Stay stay, {DateTime? until}) async {
    final id = await c.expectLater(
      home: home,
      residentId: confirmedBy?.id,
      call: _confirmedCall,
      stay: stay,
      until: until,
      clip: nameClip,
      trust: proof == CallProof.pin ? 'pin_verified' : 'verified',
    );
    recordId = id;
    result = CallResult.expected;
    step = canOfferNumber ? CallStep.offerNumber : CallStep.done;
    return id;
  }

  /// No to "Let them in?": turned away, with the reason tapped (or why the call stopped).
  Future<String> turnAway({String? why}) async {
    final v = visit;
    final id = await c.turnAway(
      homeId: home.id,
      guestName: v?.guestName,
      visitId: v?.id,
      reason: why ?? stopWhy ?? (proof == CallProof.cso ? 'The CSO said no' : null),
      clip: nameClip,
      callerMasked: callerMasked,
      decidedBy: proof == CallProof.cso ? decider?.id : null,
    );
    recordId = id;
    result = CallResult.turnedAway;
    step = CallStep.done;
    return id;
  }

  // --- the CSO --------------------------------------------------------------------------------

  void pickCso(Guard g) {
    decider = g;
    step = CallStep.csoReason;
  }

  void pickReason(CsoReason r) {
    reason = r;
    step = r == CsoReason.other ? CallStep.csoOther : CallStep.csoLetIn;
  }

  void otherReasonSaid(VoiceClip clip) {
    reasonClip = clip;
    step = CallStep.csoLetIn;
  }

  // --- a resident's new number -----------------------------------------------------------------

  /// "Add this number for Mrs Adeyemi?" Yes: a `number_offers` record with the full number.
  Future<void> offer(bool yes) async {
    final who = confirmedBy, call = caller;
    if (yes && who != null && call != null) {
      await c.offerNumber(residentId: who.id, number: call.number);
      numberOffered = true;
    }
    step = CallStep.done;
  }
}
