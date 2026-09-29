# BetterTab: experiment test 0

Test 0 decides the route (`docs/architecture.md` § The experiment): can swallowing the ⌘ release
hold macOS's native ⌘⇥ switcher open? The harness is the throwaway `Experiment` target
(`BetterTabExperiment.app`). The maintainer runs it by hand. Written 2026-09-29.

## What the harness does

It's a menu-bar item. It shows **T0** when idle, **T0 cycling** during ⌘⇥, **T0 holding 12 s**
during a hold, and **T0 no tap** when it couldn't create its event tap. Its menu has:
- the state, the tap, and the three permission checks;
- **Request permissions** and **Retry creating the tap**, shown only when there's no tap;
- **Tap location**: Session tap (the default) or HID tap. Choosing one recreates the tap;
- **Hold armed** (on by default). When it's off, the harness only logs and ⌘⇥ is fully native;
- **Show click-test panel during hold** (off by default), for the follow-up to 0b;
- **Quit**, which posts the ⌘ release first if a hold is running.

A **hold** starts when you release ⌘ during ⌘⇥ with Hold armed on. The harness swallows the
release, so the Dock still thinks ⌘ is down. While it holds:

| Key | What the harness does |
|---|---|
| **Return** | Posts a synthetic ⌘ release (confirm). |
| **Esc** | Posts Esc with ⌘, then the ⌘ release (cancel). |
| **Tab** | Passes it on as ⌘⇥. The hold continues. |
| **⌘, then Tab** | Swallows the ⌘ press and passes Tab on: back to cycling. Releasing ⌘ holds again. |
| **⌘ pressed and released** | Swallows both, then posts the ⌘ release, like Return. |
| **Anything else** | Swallowed and logged. The mouse is passed through and counted. |

After **30 s** it cancels by itself; time asleep counts. Every way out of a hold posts the synthetic ⌘ release. The
one exception is ⌘⇥ again, which goes back to cycling while ⌘ is physically down.

## Build and launch

```sh
xcodebuild -project BetterTab.xcodeproj -scheme Experiment -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/BetterTabExperiment.app
```

Quit the running copy before you rebuild, and **never run the harness while BetterTab is
running**: each would treat the other's synthetic ⌘ release as a real one. Don't run it under the Xcode debugger: while it's
paused at a breakpoint, its tap holds up every key and click until macOS turns the tap off.

**Permissions.** The build is signed ad hoc, so macOS forgets the grant on every rebuild, even
though the old entry still shows as on. After each rebuild:
1. Open System Settings → Privacy & Security → Accessibility.
2. Remove the old BetterTabExperiment entry (−), then add the new build (+) and switch it on.
3. From the T0 menu, choose **Retry creating the tap**, or relaunch.

The harness never prompts on its own. **Request permissions** asks for Accessibility and Input
Monitoring.

**Input Monitoring: is it needed as well?** The launch log has a `PERM at launch` line with
`AXIsProcessTrusted`, `CGPreflightListenEventAccess` (Input Monitoring) and
`CGPreflightPostEventAccess`. Each attempt to create the tap logs `PERM before tapCreate(…)` then
`TAP tapCreate(session) returned a tap` or `… returned nil`. The answer is **no** if the tap is
created with Accessibility on and Listen off, and ⌘⇥ then logs `STATE Idle → Cycling`. If the tap
only works once Input Monitoring is also granted, the answer is **yes**, and the spec gets a
second permission.

## Live log

Keep this running in a Terminal window:

```sh
log stream --predicate 'subsystem == "com.luksanss.BetterTab.Experiment"' --level info --style compact
```

Every line starts with a tag: `STATE`, `HOLD`, `SWALLOW`, `PASS`, `MOUSE`, `POST`, `AX`, `WIN`,
`FLAGS`, `PANEL`, `PERM`, `TAP`, `MENU`, `ARMED` or `SIGNAL`. The lines are logged at notice level, so
`log show --last 30m --predicate '…' --style compact` finds them afterwards too.

## Setup for every test

- **Apps:** Chrome with one window, and TextEdit with an empty document in front.
- **Harness settings:** Session tap, Hold armed on, click-test panel off.
- **To hold:** hold ⌘, press Tab until Chrome is highlighted, then release ⌘.

While the native switcher is up, **Q quits and H hides the highlighted app**. If swallowing ever
fails, those keys act, so don't type Q, H or W during a hold.

## Tests

Run 0a–0g with the session tap first. **If any of them fails, choose Tap location → HID tap**
(look for `TAP tapCreate(hid) returned a tap`) and repeat 0a–0g. Note which location each result
came from.

**0a. The switcher stays on screen for at least 15 s.**
- Do: hold on Chrome and touch nothing for 20 s, then press Esc.
- Pass: the switcher is still on screen 15 s after you let go of ⌘.
- Logs: `STATE Cycling → Holding: ⌘ release SWALLOWED`, then `AX switcher FOUND (Holding)`, then
  `AX heartbeat: holding 5.0 s, switcher on screen=true` at 5, 10 and 15 s. `on screen=false`, or
  a switch or close you can see, is a fail. Write down what the Dock did.

**0b. Moving the mouse doesn't close or confirm it.**
- Do: hold, move the mouse around for 5 s without clicking, then press Esc.
- Pass: the switcher stays and nothing switches.
- Logs: `MOUSE first mouseMoved during hold` (its flags show whether mouse events carry ⌘), a
  heartbeat still `on screen=true`, and `HOLD end … mouseMoves=N` with N above 0.
- **Follow-up (not part of a–g).** Turn on **Show click-test panel during hold**, hold, and click
  the yellow "Click me" panel near the top of the screen once. Write down whether the switcher
  stays, closes or confirms. Logs: `PANEL shown at level N`, `MOUSE leftMouseDown during hold`,
  `PANEL mouseDown received by the click-test panel`, then the next `AX` line. This decides
  whether the window list can take clicks (spec § Keys while the list is open, "Mouse"). Turn the
  panel off again.

**0c. Swallowed letters reach neither the Dock nor the front app.**
- Do: hold, type `asdf gjkl` and a digit or two, then press Esc.
- Pass: nothing appears in TextEdit, and the switcher doesn't react.
- Logs: one `SWALLOW keyDown` line per key, and `HOLD end … swallowedKeyDowns=N` with N at least
  the number of keys you typed (autorepeats count too). The keycodes are logged as private, so
  they show as `<private>`.

**0d. The synthetic ⌘ release finishes the switch.**
- Do: hold on Chrome, wait 3 s, then press Return.
- Pass: Chrome comes to the front and the switcher closes.
- Logs: `POST ⌘ release (reason: Return): type=12 … keycode=55 (left ⌘) flags=0x100`, then
  `HOLD end (reason: Return)`. Type 12 is flagsChanged, and the ⌘ bit (0x100000) must be clear;
  0x100 alone means no modifier is down. The release replays the ⌘ key you let go of, so it's
  `keycode=54 (right ⌘)` if you held with the right one. Then `STATE Holding → Idle (reason: Return); posted Esc=false
  ⌘release=true`.

**0e. Esc, then the ⌘ release, cancels.**
- Do: hold on Chrome, then press Esc.
- Pass: the switcher closes and TextEdit is still in front.
- Logs: `POST Esc keyDown with ⌘`, `POST Esc keyUp with ⌘`, `POST ⌘ release (reason: Esc)`, and
  `posted Esc=true ⌘release=true`.

**0f. ⌘ isn't stuck afterwards.**
- Do: after 0d, after 0e and after one 30 s timeout (hold and wait for `HOLD end (reason: 30 s
  safety timeout)`), click into the empty TextEdit document and type `abc`.
- Pass: plain letters appear each time. If ⌘ were stuck you'd see ⌘A, ⌘B and ⌘C fire instead,
  which is harmless in an empty document.
- Logs: `POST check 200 ms after the ⌘ release: session ⌘ down=false …, HID ⌘ down=false`.

**0g. If the harness is killed during a hold, one ⌘ press closes the switcher.**
- This is the only test that uses `kill -9`. The keyboard is swallowed during a hold, so the
  kill has to be scheduled before it starts.
- Do: in Terminal, run `sleep 10; pkill -9 -x BetterTabExperiment`. Within 10 s, bring TextEdit to
  the front and hold on Chrome. Once the harness is gone (T0 disappears from the menu bar), look
  at the switcher, then press and release ⌘ once.
- Pass: the switcher closes on that one ⌘ press. Write down whether it switched to Chrome or
  cancelled. Afterwards ⌘⇥ works normally, and typing in TextEdit gives plain letters.
- Logs: `HOLD start` and no `HOLD end`. The process is gone, so nothing more is logged.
- Relaunch the harness afterwards.

**0h. ⌘⇥ during the hold moves the native highlight on.**
- Do: hold on Chrome. First press Tab on its own, twice. Then hold ⌘, press Tab, and release ⌘.
  Finish with Esc.
- Pass: the highlight moves on each Tab. After the ⌘⇥, releasing ⌘ holds again on the new app.
- Logs: for Tab alone, `PASS Tab keyDown with ⌘ added during hold`, then `AX after Tab during
  hold: … selected=<the next app>`. For ⌘⇥, `SWALLOW ⌘ pressed again during hold`, `HOLD end
  (reason: ⌘⇥ again)`, `STATE Holding → Cycling`, and after the release `STATE Cycling →
  Holding` with `AX switcher FOUND (Holding) … selected=…`. Note whether one variant works
  and the other doesn't.

**0i. A quick ⌘⇥ tap, released before the switcher draws, can also be held.**
- Do: with TextEdit in front and Chrome the previous app, tap ⌘⇥ as fast as you can. Wait 3 s,
  then press Esc.
- Pass: the switcher appears and stays held.
- Logs: `AX Cycling ended N ms in, before the switcher was found` marks a real quick tap. Then
  `AX switcher FOUND (Holding) N ms after entering, check #k` shows how long the Dock took to
  draw it. `AX switcher NOT FOUND (Holding) within 1 s` is a fail. If 0i fails, a quick tap stays
  native (spec § Edge cases); it doesn't change the route.

**Also record the switcher's window layer.** At every hold start, the `WIN` lines list the Dock's
on-screen windows. `WIN switcher window is probably #… at layer N` is the level that BetterTab's
dots and list have to sit above.

## Recovery

If anything goes wrong during a hold:
1. **Press and release ⌘ once.** If the harness is alive, that ends the hold and it posts the
   release. If it's dead, the Dock gets a real release.
2. **If that fails, quit the harness from its menu with the mouse.** Quit posts the release
   first.
3. **Or, once the keyboard works again, run `pkill -TERM -x BetterTabExperiment`.** SIGTERM (and
   SIGINT) post the release before the harness exits.
4. **If ⌘ still acts stuck afterwards** (typing fires shortcuts), stop typing, then press and
   release the left ⌘ and then the right ⌘. Each gives the system a real release.

The harness also cancels any hold by itself after 30 s, counting time asleep. **Never `kill -9` it except for 0g**:
like a crash, it's an exit that can't post the release. If the menu says Holding but no
switcher is on screen (after clicking an icon in the switcher, for example), press Esc.

## Record the result

Write the result under **`docs/handoff.md` § Decisions already settled**, using `/handoff-update`.
For each of 0a–0i give pass or fail, the tap location, and the log lines that show it. Add the
Input Monitoring answer, the 0b click follow-up, and the switcher's window layer.

- **If 0a–0g all pass** with one tap location, it's **route A+**. Record which location.
- **If any of 0a–0g fails** with both locations, it's **route B**. Record what failed.
- 0h and 0i don't decide the route. They decide how "⌘⇥ again" and a quick tap behave.
