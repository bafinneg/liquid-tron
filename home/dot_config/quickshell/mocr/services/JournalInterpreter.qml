// JournalInterpreter — singleton journalctl interpreter (FEAT-nostromo-llm).
//
// Replaces the per-variant `journalctl -f` tail in NostromoWhispers with
// one ring-buffered tail, periodically POST-ed to local ollama (gemma3:4b)
// for DATA-TNG-voiced semantic summaries. Variants subscribe to
// `interpretedLine` (one entry) and `recapBurst` (consolidated array,
// Session 2 work) and feed them into their existing `_pending`/`_drainOne`
// pipelines unchanged.
//
// Three layers of defence keep the variant alive when the LLM path fails:
//
//   1. Per-batch fallback: any non-zero curl exit, missing/non-string
//      `response` field, or invalid inner JSON drains the current ring
//      through the lifted `_renderEntry` formatter and emits those raw-
//      formatted entries via `interpretedLine`. Variants see the same
//      shape; the only visible signal is messages that read like syslog
//      again.
//
//   2. Two consecutive batch failures flip `rawMode: true`. While
//      rawMode, batches skip the curl call entirely and emit raw-
//      formatted entries directly. `healthCheck` Timer polls
//      `/api/tags` every 60s; the first 2xx flips rawMode back off and
//      the next batch tries the LLM path again.
//
//   3. The ring itself is bounded (ringCap=500). Even in pathological
//      situations (LLM down, raw mode active, but flush timer disabled)
//      the buffer cannot grow without bound.
//
// Process model:
//   - One long-lived `tail` Process running journalctl -f -o json.
//     SplitParser delivers one line per JSON object; `_ingest` parses,
//     filters, and pushes into `_ring`.
//   - One `batchTimer` (15s default) drains `_ring` into either an
//     ollama call or a raw emit (rawMode).
//   - One `ollamaCall` Process per batch flush. Body is base64-encoded
//     in QML and decoded in bash so JSON quoting does not collide with
//     shell quoting. Output collected into `_ollamaBuf`, double-
//     `JSON.parse`d on exit (HTTP body → inner `response` string).
//   - One `healthCheck` Timer that runs only while `rawMode: true`.
//
// Filter, parse, category, sanitize, time-format functions are lifted
// verbatim from NostromoWhispers.qml (FEAT-nostromo-polish chunks 1-3).
// The variant rewrites in chunk 2 of this spec point at this file
// instead of carrying its own copies.

pragma Singleton

import QtQuick
import Quickshell.Io
// Sibling singleton PresenceState — used for the chunk-4 absent-transition
// window early close and (via NostromoWhispers) chunk-5 return-recap
// trigger. `.` refers to this file's directory (services/); qmldir
// registers both singletons in the `services` module.
import "." as Siblings

Item {
    id: service
    visible: false
    width: 0; height: 0

    // ── Public API ────────────────────────────────────────────────
    // entry shape: { time, cat, msg, priority }
    signal interpretedLine(var entry)
    // entries: array of the same entry shape; emitted as a single burst
    // for the return-recap path (Session 2 / chunks 4+5). Declared now
    // so the variant can wire `Connections` against the final API
    // shape.
    signal recapBurst(var entries)
    // FEAT-nostromo-console: investigate burst delivered separately so
    // the console can render full content while the ambient strip only
    // sees a synthetic "ready" line (chunk 5).
    signal investigateReady(var entries)

    // Fired from every non-success branch of investigateLast() so the
    // Console can clear its `_investigating` busy flag promptly. The
    // strip-side recapBurst still carries the human-readable reason
    // string; this signal is the structured channel the Console uses
    // to leave its "Investigating…" state without waiting for the
    // 35-second watchdog.
    signal investigateFailed(string reason)

    // Streaming feedback for the investigate path. Fired BEFORE the
    // ollama Process starts, then once per NDJSON chunk as tokens
    // arrive, then NOT fired on the final envelope (investigateReady
    // closes the stream). The Console uses this to render the LLM's
    // output token-by-token while the user waits, turning a multi-
    // second blocking wait into a visible "the AI is thinking" UX.
    signal investigateThinkingStarted()
    signal investigateProgress(string chunk)

    // Per-row Q&A — fired by askActionQuestion() when the user clicks
    // [Ask] on a confirmation pill and types a question about the
    // proposed action. The signal carries the answer (plain text, in
    // DATA voice, capped at ~60 words by the prompt). Only one row at
    // a time can be in Ask mode (single-flight via _askInFlight), so
    // every connected ConsoleRow listens but ignores the signal
    // unless its own _askInFlight flag is true.
    signal actionAnswerReady(string answer)
    signal actionAnswerFailed(string reason)
    // FEAT-nostromo-console: Super+J IPC routes through here; the
    // console binds and toggles its visibility.
    signal consoleToggleRequested()
    // FEAT-nostromo-console: public read-only views of internal state
    // for the console surface. lastEmit mirrors _lastEmitContext (one-
    // batch retention). recentEntries is a bounded ring of every
    // emitted line (cap 50, amendment 2026-04-26) so the console's
    // recent-entries pane can offer per-entry call-back-any-entry
    // investigate.
    readonly property var lastEmit: _lastEmitContext
    readonly property var recentEntries: _recentEntries
    // True while consecutive ollama failures have tripped raw mode.
    // healthCheck flips back to false on a successful /api/tags ping.
    property bool rawMode: false

    // ── Tunables (tweakable via edit-and-reload) ──────────────────
    readonly property int ringCap: 500
    readonly property int batchFlushMs: 15000
    readonly property int healthCheckMs: 60000
    // Owner-directed performance correction: automatic 15-second ambient
    // inference caused recurring 94–95% GPU bursts and visible compositor
    // jitter. Keep deterministic journal rendering active, while preserving
    // manual investigate/Q&A and the separate four-hour digest paths.
    readonly property bool automaticAmbientInferenceEnabled: false
    readonly property string ollamaUrl: "http://localhost:11434/api/generate"
    readonly property string ollamaTagsUrl: "http://localhost:11434/api/tags"
    // Model tier split (INFRA-006). Three call paths, three models;
    // each request body carries its own `model` so the choice is local
    // to the call site rather than a global toggle.
    //
    // ambient (gemma3:4b)
    //   _flushBatch + warmup probe. 15s cadence; latency-sensitive.
    //   ~3 GB resident on a 4090. The ollama registry tag is `gemma3:4b`,
    //   not `gemma3:4b-it` (spec drafted against the upstream name; the
    //   canonical published tag at pull time was `gemma3:4b`). Voice
    //   stability vs the 7b/14b is observed over a 48h window before
    //   the chunk-3 prompt trim runs.
    //
    // digest (qwen2.5:7b-instruct)
    //   _closeWindow + consolidateRecap. Rare (4h cadence + on-presence)
    //   but quality-sensitive over larger inputs. ~5 GB resident.
    //
    // investigate (qwen2.5:14b-instruct)
    //   investigateLast (Super+J). Bumped from 7b on 2026-04-25 because
    //   the 7b was too literal-minded with the investigate prompt's
    //   voice rules and would echo quoted-example strings verbatim into
    //   every emit (rule-8 parroting). 14b follows instructions tightly
    //   enough that the action-oriented bursts read cleanly. ~9 GB
    //   resident; loaded lazily on first Super+J, then held by
    //   OLLAMA_KEEP_ALIVE=-1 (system drop-in 10-keep-alive.conf).
    //
    // The /no_think directive + think:false flag in every body remain
    // for defence-in-depth: harmless on non-reasoning models, and if a
    // future swap reintroduces a qwen3 variant the voice rules still
    // work.
    readonly property string ollamaModelAmbient: "gemma3:4b"
    readonly property string ollamaModelDigest: "qwen2.5:7b-instruct"
    // Investigate model — swap between 14b and 7b at the property
    // level. 14b is the spec-blessed default (better JSON adherence,
    // tighter DATA voice). 7b ~halves TTFT on a 4090; quality regresses
    // on edge cases but the sanitizer + filler regex catch the worst
    // of it. Flip to 7b when latency is the priority over polish.
    // Both models stay resident under INFRA-006's keep_alive=-1.
    readonly property string ollamaModelInvestigate: "qwen2.5:14b-instruct"
    // readonly property string ollamaModelInvestigate: "qwen2.5:7b-instruct"
    // Wall-clock guard handed to curl via -m. Wall-clock cap, not
    // connect timeout — covers slow inference too. 30s ceiling sized
    // for the 14b investigate path's first-token latency under load;
    // ambient (4b) and digest (7b) clear in well under that. Single-
    // flight on `_runOllama` means a 30s ceiling cannot overlap with a
    // 15s batchTimer cadence — the second flush is dropped silently
    // (returns ok=false to its callback), the third tries fresh.
    readonly property int requestTimeoutSec: 30
    // Per-request `keep_alive` for /api/generate. 300s == "unload after
    // 5 min idle." Ambient (gemma3:4b) flushes every 15s during normal
    // operation, so it stays resident; only unloads if the variant is
    // swapped or quickshell exits. Investigate (qwen2.5:14b) is bursty
    // — pinning it Forever stranded ~10 GB VRAM and starved the
    // compositor (judder). 5 min lets it unload between investigations
    // and reload on demand (~5-10s cold start). Overrides
    // OLLAMA_KEEP_ALIVE=-1 from the systemd drop-in (INFRA-006 ch.1).
    readonly property int ollamaKeepAlive: 300

    // ── Dedup signature tunables (FEAT-nostromo-dedup) ────────────
    // Stable per-signature suppression: each unique normalized log
    // shape narrates once, then suppresses for suppressionWindowMs;
    // recurrences past the window resurface as a single warning-amber
    // reminder. seenIssuesPruneCheckMs cadence walks the state map and
    // drops entries untouched for seenIssuesPruneMs.
    readonly property int signatureMaxLen: 200
    readonly property int suppressionWindowMs: 30 * 60 * 1000
    readonly property int seenIssuesPruneMs: 24 * 60 * 60 * 1000
    readonly property int seenIssuesPruneCheckMs: 60 * 60 * 1000

    // Compiled once; reused across _signatureOf calls. Order of
    // application in _signatureOf matters — UUIDs before generic hex,
    // IPv6 before bus identifiers, port-after-IP before bus.
    readonly property var _sigRegexIp4: /\b(?:\d{1,3}\.){3}\d{1,3}\b/g
    readonly property var _sigRegexIp6: /\b[0-9a-fA-F:]*::[0-9a-fA-F:]*\b/g
    readonly property var _sigRegexPort: /:\d{2,5}\b/g
    readonly property var _sigRegexPid: /\[\d+\]/g
    readonly property var _sigRegexHex: /\b[0-9a-fA-F]{32,}\b/g
    readonly property var _sigRegexUuid: /\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/g
    readonly property var _sigRegexBus: /:\d+\.\d+/g
    readonly property var _sigRegexBigInt: /\b\d{4,}\b/g

    // ── Window-digest tunables (chunk 4) ──────────────────────────
    // 4 hour rolling window. `windowTimer` closes it unconditionally;
    // an absent-transition may close it early if it has enough entries
    // and enough age (the floor avoids digesting a 3-minute sliver when
    // the user walks away shortly after a reboot). Spec §Chunk 4 +
    // §Non-obvious constraints.
    readonly property int windowDurationMs: 4 * 60 * 60 * 1000
    readonly property int windowEarlyCloseEntries: 20
    readonly property int windowEarlyCloseAgeMs: 30 * 60 * 1000

    // ── Persistent state directory ────────────────────────────────
    // ~/.local/state/nostromo/  (XDG_STATE_HOME default).
    // mkdir -p runs at component completion; both this service and
    // hypridle's listener (chunk 3) can write to the dir idempotently.
    readonly property string stateDir: {
        var xdg = Qt.application && Qt.application.arguments ? "" : ""
        // Quickshell exposes neither XDG_STATE_HOME nor StandardPaths
        // here in a portable way. Resolve via shell at init.
        return ""  // populated by stateDirInit Process below
    }
    property string _stateDir: ""

    // ── Internal state ────────────────────────────────────────────
    property var _ring: []
    // Dedup state map (FEAT-nostromo-dedup). Key: signature string
    // produced by _signatureOf. Value:
    //   { firstSeen: <ms>, lastSeen: <ms>, lastNarrated: <ms>,
    //     count: <int>, state: "new" | "suppressed" | "resurfacing" }
    // lastNarrated == 0 ⇒ never narrated. count counts recurrences
    // since last narration (reset on _markBatchNarrated). state is
    // descriptive only; admission decisions read lastNarrated +
    // suppressionWindowMs.
    property var _seenIssues: ({})
    property int _consecutiveFailures: 0
    // ollamaCall stdout accumulator. Cleared at start of each call;
    // parsed in onExited.
    property string _ollamaBuf: ""
    // Callback bound for the in-flight ollama call. Single-flight: if
    // a new call arrives while one is running we drop the new request
    // (batch flush cadence > requestTimeoutSec, so this should not
    // happen in steady state).
    property var _ollamaCb: null
    // Streaming-mode flag for ollamaCall. When true, the SplitParser
    // routes each line through _ingestStreamChunk (NDJSON parse +
    // investigateProgress signal) instead of accumulating into
    // _ollamaBuf. Cleared on Process exit before the completion
    // callback fires.
    property bool _ollamaStreaming: false
    // Concatenated `.response` fields from streaming-mode NDJSON
    // envelopes. The full LLM output, JSON.parse-ready on Process exit.
    property string _ollamaStreamText: ""

    // Q&A state for askActionQuestion(). Single-flight so the answer
    // signal is unambiguous (only one row can be expecting it). Uses
    // its own Process (askCall) so the askActionQuestion call doesn't
    // contend with ambient/recap/investigate on ollamaCall.
    property bool _askInFlight: false
    property string _askBuf: ""

    Process {
        id: askCall
        running: false
        stdout: SplitParser {
            onRead: data => { service._askBuf += data + "\n" }
        }
        onExited: function(code, status) {
            var raw = service._askBuf
            service._askBuf = ""
            service._askInFlight = false
            if (code !== 0 || raw.trim().length === 0) {
                actionAnswerFailed("LLM did not respond.")
                return
            }
            try {
                var env = JSON.parse(raw)
                if (typeof env.response === "string"
                    && env.response.trim().length > 0) {
                    actionAnswerReady(env.response.trim())
                } else {
                    actionAnswerFailed("Empty answer.")
                }
            } catch (e) {
                actionAnswerFailed("Could not parse answer.")
            }
        }
    }

    function askActionQuestion(originalEntry, argv, question) {
        console.log("[ASK] askActionQuestion entered question="
            + JSON.stringify(question || "").substring(0, 80))
        if (_askInFlight) {
            actionAnswerFailed("Another question is in flight. Wait, then try again.")
            return
        }
        if (rawMode) {
            actionAnswerFailed("LLM offline.")
            return
        }
        if (!question || question.trim().length === 0) {
            actionAnswerFailed("Empty question.")
            return
        }
        _askInFlight = true
        var prompt = _questionPrompt(originalEntry, argv, question)
        var body = JSON.stringify({
            model: ollamaModelInvestigate,
            prompt: prompt,
            stream: false,
            think: false,
            keep_alive: ollamaKeepAlive,
            options: {
                temperature: 0.3,
                num_predict: 256,
                num_ctx: 4096
            }
        })
        var b64 = Qt.btoa(body)
        askCall.command = ["bash", "-c",
            "printf '%s' '" + b64 + "' | base64 -d | "
            + "curl -sS -m " + requestTimeoutSec + " -X POST "
            + "-H 'Content-Type: application/json' "
            + "--data-binary @- " + ollamaUrl
        ]
        askCall.running = true
    }

    function _questionPrompt(originalEntry, argv, question) {
        var msg = (originalEntry && originalEntry.msg) ? originalEntry.msg : ""
        var argvStr = JSON.stringify(argv || [])
        return [
            "You are Lt. Commander Data of the USS Enterprise. The user",
            "is reviewing a proposed action and has a question about it.",
            "",
            "PROPOSED ACTION:",
            "  description: " + msg,
            "  command:     " + argvStr,
            "",
            "USER QUESTION:",
            "  " + question,
            "",
            "Answer the question concisely (under 60 words) in DATA's",
            "register: precise, formal, declarative. Plain text only —",
            "no JSON, no markdown, no code fences.",
            "",
            "Required:",
            "  - State the answer directly. Do not preface with",
            "    \"Certainly\" or \"Of course\".",
            "  - If the question is \"what does this do\", explain the",
            "    command's effect on the system.",
            "  - If the question is \"is this safe\", state the blast",
            "    radius (reversible, requires root, affects other",
            "    services, etc.) plainly.",
            "  - If the question is unclear, state what additional",
            "    information you need.",
            "  - Do NOT propose new actions. Do NOT lecture about voice",
            "    or formatting. Answer the question only."
        ].join("\n")
    }

    // Window-digest accumulator — separate from _ring. Retains at most
    // windowEntriesCap distinct signatures for the current 4h window.
    // Repeated signatures update one representative's occurrence count;
    // a unique-event storm evicts the oldest representative. This bound
    // is required before the priority filter: filtering only at close time
    // cannot protect the live shell from a high-cadence journal source.
    readonly property int windowEntriesCap: 500
    property var _windowEntries: []
    property var _windowEntryBySignature: ({})
    property real _windowStartMs: Date.now()

    // Recap consolidation (chunk 5).
    // digest-read buffer + callback; single-flight across two monitors.
    property string _digestReadBuf: ""
    property var _digestReadCb: null
    property bool _recapInFlight: false

    // Investigate-last context (FEAT-nostromo-investigate). Captured at
    // every successful emission path. Shape:
    //   { entries: [{time,cat,msg,priority}], raw: [<parsed objects>],
    //     ts: <ms>, mode: "ambient" | "raw" | "recap" | "targeted" }
    // One-batch retention — overwritten on the next emission. The
    // "targeted" mode is constructed on the fly by investigateLast when
    // called with an entryId (FEAT-nostromo-console amendment) and is
    // never assigned here.
    property var _lastEmitContext: null
    property bool _investigateInFlight: false

    // Recent-entries ring (FEAT-nostromo-console amendment 2026-04-26).
    // Bounded ring of every emitted ambient/recap line. Ring item shape:
    //   { time, cat, msg, priority, raw, emitTs }
    // emitTs is a unique string id ("<ms>_<idx>") so multiple entries
    // emitted in the same millisecond stay distinguishable; the console
    // passes it back through the investigate IPC as the targeted entryId.
    // raw is a reference (not a copy) to the batch's stripped raw lines
    // at emit time — per-entry investigate re-feeds the same RAW_CONTEXT
    // block to the LLM. INVEST result bursts and synthetic fallback
    // bursts are NOT pushed: they are not legitimate subjects to re-
    // investigate.
    readonly property int recentEntriesCap: 50
    property var _recentEntries: []

    // Investigate output schema regime (FEAT-nostromo-schema-bump).
    // false → prompt-only constraint (default; chunk 1 verdict on
    // 2026-04-25). true → attach a JSON schema via ollama's `format`
    // parameter. Runtime-flippable via `schema_mode set_format` IPC,
    // but measurement runs require a Quickshell restart between
    // regimes so per-session counters do not mix.
    property bool _useFormatConstraint: false

    // Per-emit reliability counters (FEAT-nostromo-schema-bump chunk 4).
    property int _investigateEmitCount: 0       // total successful emits
    property int _investigateExtendedCount: 0   // every entry has action_kind
    property int _investigateLegacyCount: 0     // no entry has action_kind
    property int _investigateMixedCount: 0      // some entries have action_kind

    // Per-entry reliability counters (drive the chunk 1 gate).
    property int _investigateEntryCount: 0
    property int _investigateEntryWithActionCount: 0

    function _stripMarkers(batch) {
        return batch.map(function(p) {
            var out = {}
            for (var k in p) {
                if (k === "_sig" || k === "_reminder") continue
                out[k] = p[k]
            }
            return out
        })
    }

    function _digestsAsRaw(digests) {
        // Flatten window-digest records into pseudo-parsed shape so the
        // investigate prompt sees a stream of journal-shaped lines.
        var out = []
        for (var i = 0; i < digests.length; i++) {
            var d = digests[i]
            var notable = (d && d.digest && d.digest.notable) || []
            for (var j = 0; j < notable.length; j++) {
                var n = notable[j]
                out.push({
                    time: "--:--:--",
                    ident: (n && n.cat) ? String(n.cat).toLowerCase() : "",
                    msg: (n && n.msg) || "",
                    priority: (n && n.priority) || "",
                    pid: "",
                    uid: ""
                })
            }
        }
        return out
    }

    // ── State directory init ──────────────────────────────────────
    Process {
        id: stateDirInit
        running: true
        command: ["bash", "-c",
            "dir=\"${XDG_STATE_HOME:-$HOME/.local/state}/nostromo\"; " +
            "mkdir -p \"$dir\" && printf '%s' \"$dir\""
        ]
        stdout: SplitParser {
            onRead: data => { service._stateDir += data }
        }
    }

    // ── Ollama warmup probe ───────────────────────────────────────
    // Fired once at component completion. Sends a minimal /api/generate
    // for the ambient model (gemma3:4b) so it is paged into VRAM before
    // the first real batch flush 15s later. Without this the cold-load
    // tax can blow through requestTimeoutSec on the first one or two
    // flushes and trip rawMode on boot. Digest (qwen2.5:7b) and
    // investigate (qwen2.5:14b) are not warmed here — digest has 4h
    // before its first fire, investigate is on-demand; both are loaded
    // lazily and held by OLLAMA_KEEP_ALIVE=-1 once first hit. Warmup
    // uses a 60s timeout (enough headroom for a cold load) and discards
    // stdout — we only care about the side effect of weights becoming
    // resident. fire-and-forget; if the probe fails the regular batch
    // flush will still try and either succeed or trip rawMode the same
    // way it always did.
    Process {
        id: ollamaWarmup
        running: service.automaticAmbientInferenceEnabled
        command: ["bash", "-c",
            "body=$(printf '%s' '{\"model\":\"" + service.ollamaModelAmbient +
            "\",\"prompt\":\"warmup\",\"stream\":false,\"keep_alive\":" +
            service.ollamaKeepAlive + ",\"options\":{\"num_predict\":1}}'); " +
            "curl -sS -m 60 -o /dev/null -X POST -H 'Content-Type: application/json' " +
            "--data-binary \"$body\" " + service.ollamaUrl + " || true"
        ]
    }

    // ── Journal tail ──────────────────────────────────────────────
    // Cold-start replay is limited to the newest ringCap records from the
    // prior 10 minutes. Without --lines, a kernel or service log storm can
    // enqueue millions of SplitParser callbacks before QML admission runs.
    Process {
        id: tail
        running: true
        command: ["journalctl", "-f", "--no-pager", "-o", "json",
                  "--output-fields=__REALTIME_TIMESTAMP,SYSLOG_IDENTIFIER,_COMM,MESSAGE,PRIORITY,_PID,_UID",
                  "--lines", String(service.ringCap),
                  "--since", "10 minutes ago"]
        stdout: SplitParser {
            onRead: data => { service._ingest(data) }
        }
        onRunningChanged: {
            // Defensive: if the journalctl tail exits (system bus blip,
            // OOM, etc.) restart after a 5s debounce. Sibling Process
            // patterns in this repo never auto-respawn; this is the
            // first one that does, per spec §Non-obvious-constraints.
            if (!running) tailRespawn.start()
        }
    }
    Timer {
        id: tailRespawn
        interval: 5000
        repeat: false
        onTriggered: { if (!tail.running) tail.running = true }
    }

    // Stable signature for a parsed journal object (FEAT-nostromo-
    // dedup). ident is included verbatim so cross-source collisions
    // are impossible; msg is normalized in a fixed order — UUIDs
    // before generic hex, IPv6 before bus-id, port-after-IP before
    // bus — and truncated to signatureMaxLen.
    function _signatureOf(parsed) {
        var ident = (parsed && parsed.ident) || ""
        var msg = (parsed && parsed.msg) || ""
        msg = _messageToString(msg)
        msg = msg.replace(_sigRegexUuid, "<uuid>")
        msg = msg.replace(_sigRegexIp4, "<ip>")
        msg = msg.replace(_sigRegexIp6, "<ip>")
        msg = msg.replace(_sigRegexPort, ":<port>")
        msg = msg.replace(_sigRegexBus, ":<bus>")
        msg = msg.replace(_sigRegexPid, "[<pid>]")
        msg = msg.replace(_sigRegexHex, "<hex>")
        msg = msg.replace(_sigRegexBigInt, "<n>")
        if (msg.length > signatureMaxLen) msg = msg.substring(0, signatureMaxLen)
        return ident + "|" + msg
    }

    function _ingest(raw) {
        var trimmed = (raw || "").trim()
        if (trimmed.length === 0) return
        var parsed = _parseJson(trimmed) || _parseShortLine(trimmed)
        if (!parsed) return
        if (!_passesFilter(parsed)) return

        // FEAT-nostromo-dedup admission. _admitToRing pushes to both
        // _ring and _windowEntries; _admitToWindowOnly pushes only to
        // _windowEntries (suppressed signatures still reach the 4h
        // digest path so high-cadence shapes are represented there).
        var sig = _signatureOf(parsed)
        var now = Date.now()
        var entry = _seenIssues[sig]

        if (!entry) {
            _seenIssues[sig] = {
                firstSeen: now, lastSeen: now,
                lastNarrated: 0, count: 1, state: "new"
            }
            parsed._sig = sig
            parsed._reminder = false
            _admitToRing(parsed)
            return
        }

        entry.lastSeen = now
        entry.count += 1

        // The first representative is already pending in _ring. Do not
        // enqueue every recurrence during the initial 15s batch window.
        if (entry.lastNarrated === 0 && entry.state === "new") {
            _admitToWindowOnly(parsed, sig)
            return
        }

        if (entry.lastNarrated > 0
            && (now - entry.lastNarrated) < suppressionWindowMs) {
            // Within suppression window — drop from ring, keep in
            // _windowEntries for the digest path.
            _admitToWindowOnly(parsed, sig)
            return
        }

        // Past window (or never narrated and re-promoted by prune
        // race). Push as reminder iff we have actually narrated it
        // before; brand-new sigs with lastNarrated == 0 stay in the
        // NEW_EVENTS bucket.
        parsed._sig = sig
        parsed._reminder = (entry.lastNarrated > 0)
        entry.state = parsed._reminder ? "resurfacing" : "new"
        _admitToRing(parsed)
    }

    function _admitToRing(parsed) {
        _ring.push(parsed)
        if (_ring.length > ringCap)
            _ring.splice(0, _ring.length - ringCap)
        _admitToWindowOnly(parsed, parsed._sig || _signatureOf(parsed))
    }

    function _admitToWindowOnly(parsed, sig) {
        var now = Date.now()
        var existing = _windowEntryBySignature[sig]
        if (existing) {
            existing.occurrences = (existing.occurrences || 1) + 1
            existing.last_seen_ms = now
            parsed.occurrences = existing.occurrences
            parsed.last_seen_ms = now
            return
        }

        if (_windowEntries.length >= windowEntriesCap) {
            var evicted = _windowEntries.shift()
            if (evicted && evicted._sig)
                delete _windowEntryBySignature[evicted._sig]
        }

        parsed._sig = sig
        parsed.occurrences = 1
        parsed.last_seen_ms = now
        _windowEntries.push(parsed)
        _windowEntryBySignature[sig] = parsed
    }

    function _pruneSeenIssues() {
        var now = Date.now()
        var next = {}
        for (var sig in _seenIssues) {
            if ((now - _seenIssues[sig].lastSeen) < seenIssuesPruneMs) {
                next[sig] = _seenIssues[sig]
            }
        }
        _seenIssues = next
    }

    Timer {
        id: pruneTimer
        interval: service.seenIssuesPruneCheckMs
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: service._pruneSeenIssues()
    }

    // ── Batch flush ───────────────────────────────────────────────
    Timer {
        id: batchTimer
        interval: service.batchFlushMs
        repeat: true
        running: true
        onTriggered: service._flushBatch()
    }

    function _flushBatch() {
        if (_ring.length === 0) return
        var batch = _ring
        _ring = []
        // _windowEntries accumulation moved into _admitToRing /
        // _admitToWindowOnly (FEAT-nostromo-dedup): suppressed
        // signatures still reach the 4h digest store via
        // _admitToWindowOnly, so we no longer re-append batch here
        // (would double-count admitted entries).

        // Partition into NEW_EVENTS vs RECURRING_REMINDERS by the
        // _reminder marker set in _ingest.
        var newBatch = []
        var reminderBatch = []
        for (var i = 0; i < batch.length; i++) {
            if (batch[i]._reminder) reminderBatch.push(batch[i])
            else newBatch.push(batch[i])
        }

        if (!automaticAmbientInferenceEnabled || rawMode) {
            var rawStripped = _stripMarkers(batch)
            var renderedRaw = _emitRaw(batch)
            _lastEmitContext = {
                entries: renderedRaw,
                raw: rawStripped,
                ts: Date.now(),
                mode: automaticAmbientInferenceEnabled ? "raw" : "deterministic"
            }
            _pushRecentEntries(renderedRaw, rawStripped)
            _markBatchNarrated(batch)
            return
        }
        var body = _buildOllamaBody(ollamaModelAmbient,
                                    _ambientPrompt(),
                                    { newEvents: newBatch,
                                      reminders: reminderBatch })
        _runOllama(body, function(ok, parsed) {
            if (ok && _validateEntries(parsed)) {
                _consecutiveFailures = 0
                var renderedAmbient = _emitEntries(parsed)
                var rawAmbient = _stripMarkers(batch)
                _lastEmitContext = {
                    entries: parsed,
                    raw: rawAmbient,
                    ts: Date.now(),
                    mode: "ambient"
                }
                _pushRecentEntries(renderedAmbient, rawAmbient)
                _markBatchNarrated(batch)
            } else {
                _consecutiveFailures += 1
                var rawFallback = _stripMarkers(batch)
                var renderedFallback = _emitRaw(batch)
                _lastEmitContext = {
                    entries: renderedFallback,
                    raw: rawFallback,
                    ts: Date.now(),
                    mode: "raw"
                }
                _pushRecentEntries(renderedFallback, rawFallback)
                _markBatchNarrated(batch)
                if (_consecutiveFailures >= 2 && !rawMode) {
                    rawMode = true
                    healthCheck.running = true
                }
            }
        })
    }

    // Post-emit bookkeeping (FEAT-nostromo-dedup chunk 4). Runs on
    // every _flushBatch exit path (rawMode emit, ollama-success emit,
    // ollama-failure-then-raw emit). Once a batch leaves the variant
    // via interpretedLine the user has been informed in some form;
    // marking narrated regardless prevents a degenerate retry loop
    // where rawMode would re-narrate the same suppressed signatures
    // every flush. The LLM legitimately omitting an entry is treated
    // as "narrated and forgotten" — if it genuinely recurs the next
    // 30-min cycle re-promotes it.
    function _markBatchNarrated(batch) {
        var now = Date.now()
        var seen = {}
        for (var i = 0; i < batch.length; i++) {
            var sig = batch[i]._sig
            if (!sig || seen[sig]) continue
            seen[sig] = true
            if (_seenIssues[sig]) {
                _seenIssues[sig].lastNarrated = now
                _seenIssues[sig].count = 0
                _seenIssues[sig].state = "suppressed"
            }
        }
    }

    // ── Ollama call (curl via bash, body via base64) ─────────────
    // Why base64: JSON.stringify output contains arbitrary `"` and `\`
    // sequences (and possibly apostrophes from journal MESSAGE bodies).
    // Single-quoting the entire JSON body in bash is fragile; base64-
    // decoding is dependency-free (coreutils) and lossless. The bash
    // script does no interpolation of the body — it is piped via
    // base64 -d straight into curl --data-binary @-.
    Process {
        id: ollamaCall
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (service._ollamaStreaming) {
                    service._ingestStreamChunk(data)
                } else {
                    service._ollamaBuf += data + "\n"
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (service._ollamaStreaming) {
                var text = service._ollamaStreamText
                service._ollamaStreamText = ""
                service._ollamaStreaming = false
                var cb = service._ollamaCb
                service._ollamaCb = null
                if (cb) cb(_parseOllamaStreamedText(exitCode, text))
            } else {
                var raw = service._ollamaBuf
                service._ollamaBuf = ""
                var cb = service._ollamaCb
                service._ollamaCb = null
                if (cb) cb(_parseOllamaResponse(exitCode, raw))
            }
        }
    }

    function _ingestStreamChunk(data) {
        // SplitParser delivers one NDJSON envelope per call (ollama
        // emits one JSON object per line in streaming mode). Extract
        // .response, append to the stream buffer, fire the progress
        // signal so the Console can render it inline.
        if (!data || data.trim().length === 0) return
        try {
            var env = JSON.parse(data)
            if (typeof env.response === "string" && env.response.length > 0) {
                _ollamaStreamText += env.response
                investigateProgress(env.response)
            }
            // env.done === true: do nothing here — the Process will
            // exit shortly as curl closes its end; onExited handles
            // the accumulated text.
        } catch (e) {
            // Skip malformed NDJSON lines silently. Possible at
            // start/end of curl's output stream (heartbeats, trailing
            // newlines).
        }
    }

    function _parseOllamaStreamedText(exitCode, text) {
        if (exitCode !== 0) return { ok: false, parsed: null }
        if (!text || text.trim().length === 0) return { ok: false, parsed: null }
        try {
            var inner = JSON.parse(text)
            // Same shape normalisation as _parseOllamaResponse — qwen
            // sometimes returns a single bare object rather than the
            // requested array. Wrap to one-element array; downstream
            // _validateEntries still rejects malformed shapes.
            if (inner !== null && typeof inner === "object" && !Array.isArray(inner)) {
                inner = [inner]
            }
            inner = _sanitizeEntries(inner)
            return { ok: true, parsed: inner }
        } catch (e) {
            return { ok: false, parsed: null }
        }
    }

    function _runOllama(body, cb) {
        if (ollamaCall.running) {
            if (cb) cb({ ok: false, parsed: null })
            return
        }
        _ollamaBuf = ""
        _ollamaStreaming = false
        _ollamaCb = function(res) { cb(res.ok, res.parsed) }
        var b64 = Qt.btoa(body)
        ollamaCall.command = ["bash", "-c",
            "printf '%s' '" + b64 + "' | base64 -d | " +
            "curl -sS -m " + requestTimeoutSec + " -X POST " +
            "-H 'Content-Type: application/json' " +
            "--data-binary @- " + ollamaUrl
        ]
        ollamaCall.running = true
    }

    // Streaming variant for the investigate path. Body must have
    // `stream: true` so ollama emits NDJSON envelopes line-by-line.
    // Each chunk fires investigateProgress(chunk) on the singleton;
    // on Process exit the accumulated text is JSON.parse'd as the
    // structured action array and delivered via the completion
    // callback (same shape as _runOllama's cb(ok, parsed)). Single-
    // flight via the same ollamaCall Process — investigate, ambient,
    // recap all serialise here.
    function _runOllamaStreaming(body, cb) {
        if (ollamaCall.running) {
            if (cb) cb(false, null)
            return
        }
        _ollamaStreamText = ""
        _ollamaStreaming = true
        _ollamaCb = function(res) { cb(res.ok, res.parsed) }
        var b64 = Qt.btoa(body)
        ollamaCall.command = ["bash", "-c",
            "printf '%s' '" + b64 + "' | base64 -d | " +
            "curl -sS --no-buffer -m " + requestTimeoutSec + " -X POST " +
            "-H 'Content-Type: application/json' " +
            "--data-binary @- " + ollamaUrl
        ]
        ollamaCall.running = true
        investigateThinkingStarted()
    }

    function _parseOllamaResponse(exitCode, raw) {
        if (exitCode !== 0) return { ok: false, parsed: null }
        if (!raw || raw.trim().length === 0) return { ok: false, parsed: null }
        try {
            var outer = JSON.parse(raw)
            if (typeof outer !== "object" || outer === null) {
                return { ok: false, parsed: null }
            }
            if (typeof outer.response !== "string") {
                return { ok: false, parsed: null }
            }
            var inner = JSON.parse(outer.response)
            // Shape normalisation: ollama's `format: "json"` returns valid
            // JSON but does not enforce the prompt's array schema. qwen2.5/qwen3
            // frequently returns a bare {cat, msg, priority} object when
            // there is only one notable event in the batch. Normalise a
            // single non-array object to a one-element array so downstream
            // _validateEntries can run uniformly. A bare `{}` with no
            // required fields still fails validation — no loss of rigor.
            if (inner !== null && typeof inner === "object" && !Array.isArray(inner)) {
                inner = [inner]
            }
            inner = _sanitizeEntries(inner)
            return { ok: true, parsed: inner }
        } catch (e) {
            return { ok: false, parsed: null }
        }
    }

    // _sanitizeEntries — in-place repair of common LLM mistakes that
    // break direct-exec argv. Called right after parse and before
    // _validateEntries, so by the time the validator (and downstream
    // ActionExecutor) sees the argv it's already cleaned up.
    //
    // Repairs applied per argv element:
    //   1. Strip a single matched pair of surrounding ' or " quotes.
    //      The model frequently copies the msg-field's backtick-
    //      rendered shell form into argv, producing tokens like
    //      "'1 hour ago'" that journalctl/systemctl parse as literal
    //      quoted strings (i.e. fail). Direct exec needs the bare
    //      token "1 hour ago".
    //   2. Drop leading-whitespace/empty tokens after stripping (so
    //      ["'  '"] does not become a stray empty argv element).
    //
    // Repair is non-destructive on already-clean argv: a token
    // without surrounding quotes round-trips unchanged.
    function _sanitizeEntries(parsed) {
        if (!Array.isArray(parsed)) return parsed

        // Pass 1: argv quote-stripping (in place).
        for (var i = 0; i < parsed.length; i++) {
            var e = parsed[i]
            if (!e || typeof e !== "object") continue
            if (!Array.isArray(e.action_argv)) continue
            var cleaned = []
            for (var j = 0; j < e.action_argv.length; j++) {
                var t = e.action_argv[j]
                if (typeof t !== "string") {
                    cleaned.push(t)
                    continue
                }
                if (t.length >= 2) {
                    var first = t.charAt(0)
                    var last = t.charAt(t.length - 1)
                    if ((first === "'" || first === "\"") && first === last) {
                        t = t.substring(1, t.length - 1)
                    }
                }
                cleaned.push(t)
            }
            e.action_argv = cleaned
        }

        // Pass 2: drop filler entries.
        //
        // The model occasionally emits action_kind="none" with a vacuous
        // msg ("Read the line for additional context.", "Review the
        // recent logs.", etc.) — orientation lines the prompt FORBIDDEN
        // list explicitly bans, but qwen still produces them sometimes.
        // The user already saw the source line; an entry that says "go
        // look at it again" is pure waste.
        //
        // Legitimate use of action_kind="none" is the eval-mode
        // 'Resolved.' verdict. Allow the entry only when its msg leads
        // with "Resolved" (case-insensitive). Everything else is
        // filler and gets dropped.
        //
        // Also drop entries whose msg matches one of the forbidden
        // phrasings even when action_kind is something else — same
        // signal, same waste.
        var fillerPatterns = [
            /^read the line/i,
            /^re-?read the (line|message)/i,
            // "for context" / "for additional context" / "for more
            // details" — vacuous read-and-think phrasings that
            // promise nothing concrete.
            /\bfor\s+(additional\s+|more\s+)?(context|details?)\b/i,
            // "Review the … logs" / "Examine the … entries" /
            // "Inspect the … journal" — generic meta-investigations
            // even when the binary name is real. The user wants a
            // goal, not a directive to look at output.
            /^(review|examine|inspect|check)\s+the\s+\S+\s+(log(s|files?)?|entries|journal|messages?|output)/i,
            /^review the (recent )?(journal|log|entries)/i,
            /^examine the (surrounding )?logs?/i,
            /^check the system state/i,
            /^look into this further/i,
            /^investigate further/i,
            /^monitor for changes/i,
            /^consider (the|whether|if)/i,
            /^think about/i
        ]
        var keep = []
        for (var k = 0; k < parsed.length; k++) {
            var entry = parsed[k]
            if (!entry || typeof entry !== "object") {
                keep.push(entry)
                continue
            }
            var msg = (entry.msg || "")
            var kind = entry.action_kind
            // none is allowed only for eval-mode 'Resolved.' verdicts.
            if (kind === "none" && !/^resolved[.:]/i.test(msg)) {
                console.log("[INVEST] dropping filler (none): " + msg)
                continue
            }
            // Forbidden phrasings get dropped regardless of action_kind.
            var matchedPattern = false
            for (var p = 0; p < fillerPatterns.length; p++) {
                if (fillerPatterns[p].test(msg)) {
                    matchedPattern = true
                    break
                }
            }
            if (matchedPattern) {
                console.log("[INVEST] dropping filler (phrasing): " + msg)
                continue
            }
            keep.push(entry)
        }
        return keep
    }

    function _validateEntries(parsed) {
        // Ambient prompt asks for a JSON array. Reject anything else
        // and reject entries missing the three required fields.
        //
        // Extended schema (FEAT-nostromo-schema-bump): if either
        // action_kind or action_argv is present on an entry, BOTH
        // must be present and well-formed. Legacy entries (neither
        // field present) still pass — recapBurst ignores the extra
        // fields, so mixed-shape arrays render fine. Ordering of
        // action_kind values is a prompt-level recommendation; the
        // validator does not enforce it.
        if (!Array.isArray(parsed)) return false
        // Note: empty array is a valid response on the ambient flush
        // path ("If the batch contains nothing worth reporting, return
        // []." — see _ambientPrompt). _flushBatch treats it as a
        // no-op success. The recap (consolidateRecap) and investigate
        // (investigateLast) callers carry their own `parsed.length === 0`
        // guards, so the empty-array check is not needed here either.
        // Spec FEAT-nostromo-schema-bump chunk 3 sketches a length>0
        // reject; that would falsely trip rawMode on two consecutive
        // quiet batches. Deviation logged in the spec's Session Log.
        for (var i = 0; i < parsed.length; i++) {
            var e = parsed[i]
            if (!e || typeof e !== "object") return false
            if (typeof e.cat !== "string" || e.cat.length === 0) return false
            if (typeof e.msg !== "string" || e.msg.length === 0) return false
            if (typeof e.priority !== "string") return false

            var hasKind = ("action_kind" in e)
            var hasArgv = ("action_argv" in e)
            if (hasKind !== hasArgv) return false
            if (hasKind) {
                if (!_isValidActionKind(e.action_kind)) return false
                if (!Array.isArray(e.action_argv)) return false
                for (var j = 0; j < e.action_argv.length; j++) {
                    if (typeof e.action_argv[j] !== "string") return false
                }
                if (e.action_kind === "none" && e.action_argv.length !== 0) return false
                if (e.action_kind !== "none" && e.action_argv.length === 0) return false
            }
        }
        return true
    }

    function _isValidActionKind(k) {
        return k === "read_only_shell" || k === "mutating_shell"
            || k === "file_open" || k === "doc_link" || k === "none"
    }

    // ── Health check (only runs while rawMode) ───────────────────
    Timer {
        id: healthCheck
        interval: service.healthCheckMs
        repeat: true
        running: false
        triggeredOnStart: false
        onTriggered: {
            if (!healthProbe.running) healthProbe.running = true
        }
    }

    Process {
        id: healthProbe
        running: false
        command: ["bash", "-c",
            "curl -sS -m 5 -o /dev/null -w '%{http_code}' " + service.ollamaTagsUrl
        ]
        property string _buf: ""
        stdout: SplitParser {
            onRead: data => { healthProbe._buf += data }
        }
        onExited: (exitCode, exitStatus) => {
            var code = healthProbe._buf.trim()
            healthProbe._buf = ""
            if (exitCode === 0 && code.charAt(0) === "2") {
                service.rawMode = false
                service._consecutiveFailures = 0
                healthCheck.running = false
            }
        }
    }

    onRawModeChanged: {
        // Stop the health timer when leaving rawMode; start it on entry.
        if (!rawMode && healthCheck.running) healthCheck.running = false
    }

    // ── Window digest (chunk 4) ──────────────────────────────────
    // Every `windowDurationMs`, close the current window into a single
    // JSONL record in `${stateDir}/window-digests.jsonl`. An absent
    // transition (false → true) may close early when the window has
    // meaningful content; see `Connections { target: Siblings.
    // PresenceState }` below. Recap consolidation in chunk 5 reads the
    // JSONL file and the current partial `_windowEntries`.
    Timer {
        id: windowTimer
        interval: service.windowDurationMs
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: service._closeWindow()
    }

    // Absent-transition early close. No action on absent → present
    // here (chunk 5 recap fires via NostromoWhispers.consolidateRecap).
    Connections {
        target: Siblings.PresenceState
        function onAbsentChanged() {
            if (!Siblings.PresenceState.absent) return
            var age = Date.now() - service._windowStartMs
            if (service._windowEntries.length >= service.windowEarlyCloseEntries
                && age >= service.windowEarlyCloseAgeMs) {
                service._closeWindow()
            }
        }
    }

    // Gaming-mode gate: pause batch/window timers and stop 14b model on entry;
    // resume timers on exit (model lazy-loads on next batchTimer tick).
    Connections {
        target: Siblings.SystemMode
        function onGamingModeChanged() {
            if (Siblings.SystemMode.gamingMode) {
                batchTimer.running = false
                windowTimer.running = false
                ollamaStop.running = true
            } else {
                batchTimer.running = true
                windowTimer.running = true
            }
        }
    }

    Process {
        id: ollamaStop
        running: false
        command: ["ollama", "stop", "qwen2.5:14b-instruct"]
    }

    function _closeWindow() {
        if (_windowEntries.length === 0) {
            _windowStartMs = Date.now()
            return
        }
        var windowStart = _windowStartMs
        var windowEnd = Date.now()
        // Pre-filter: only priority ≤ 5 goes to the digest prompt so the
        // LLM input stays bounded on busy windows (spec §Non-obvious).
        // If the filter wipes everything out, fall back to the raw
        // snapshot — a digest of all-info lines is better than none.
        var filtered = _windowEntries.filter(function(e) {
            if (!e || typeof e.priority !== "string" || e.priority.length === 0) return true
            var p = parseInt(e.priority, 10)
            if (isNaN(p)) return true
            return p <= 5
        })
        var snapshot = filtered.length > 0 ? filtered : _windowEntries.slice()
        _windowEntries = []
        _windowEntryBySignature = ({})
        _windowStartMs = Date.now()
        if (rawMode) return  // no LLM available; drop silently per spec
        var body = _buildOllamaBody(ollamaModelDigest, _windowDigestPrompt(), snapshot)
        _runOllama(body, function(ok, parsed) {
            if (!ok || !parsed) return  // silent drop; next window starts fresh
            var record = {
                window_start: new Date(windowStart).toISOString(),
                window_end: new Date(windowEnd).toISOString(),
                digest: parsed
            }
            _appendWindowDigest(record)
        })
    }

    // JSONL append via a short-lived bash process. Body is base64-
    // encoded to keep arbitrary message bytes (quotes, backslashes)
    // from colliding with shell quoting — same pattern as the ollama
    // call body.
    Process {
        id: windowAppend
        running: false
    }

    function _appendWindowDigest(record) {
        if (!_stateDir || _stateDir.length === 0) return
        var line = JSON.stringify(record) + "\n"
        var b64 = Qt.btoa(line)
        windowAppend.command = ["bash", "-c",
            "printf '%s' '" + b64 + "' | base64 -d >> '" + _stateDir + "/window-digests.jsonl'"
        ]
        windowAppend.running = true
    }

    // ── Return recap (chunk 5) ───────────────────────────────────
    // Invoked by NostromoWhispers on PresenceState.absent true → false.
    // Reads the JSONL digest store + the current partial window, calls
    // ollama with the recap prompt, forces every output entry to
    // priority "3" (red-amber tint for visual elevation), emits via
    // `recapBurst`. Single-flight across variant instances: the two
    // monitors both trigger on their Connections handler but only the
    // first call proceeds; both monitors still see the resulting burst
    // because `recapBurst` is a singleton signal.
    //
    // Failure modes:
    //   - Empty digest store + empty partial → no-op (spec AC).
    //   - rawMode active → single synthetic fallback line; digests are
    //     NOT truncated (preserved for next recap attempt).
    //   - Ollama error or empty array response → fallback line; no
    //     truncation.
    //   - Successful emission → truncate the JSONL file.
    function consolidateRecap() {
        if (_recapInFlight) return
        _recapInFlight = true
        _readWindowDigestsAsync(function(digests) {
            var partial = _windowEntries.slice()
            if (digests.length === 0 && partial.length === 0) {
                _recapInFlight = false
                return
            }
            if (rawMode) {
                _emitRecapFallback()
                _recapInFlight = false
                return
            }
            var body = _buildRecapOllamaBody(ollamaModelDigest, _recapPrompt(), digests, partial)
            _runOllama(body, function(ok, parsed) {
                if (!ok || !_validateEntries(parsed) || parsed.length === 0) {
                    _emitRecapFallback()
                    _recapInFlight = false
                    return
                }
                var now = _formatTimeNow()
                var out = []
                for (var i = 0; i < parsed.length; i++) {
                    out.push({
                        time: now,
                        cat: (parsed[i].cat || "").substring(0, _categoryPadLen).toUpperCase(),
                        msg: parsed[i].msg || "",
                        priority: "3"   // forced red-amber tint
                    })
                }
                var recapRaw = _digestsAsRaw(digests).concat(_stripMarkers(partial))
                _lastEmitContext = {
                    entries: out,
                    raw: recapRaw,
                    ts: Date.now(),
                    mode: "recap"
                }
                _pushRecentEntries(out, recapRaw)
                recapBurst(out)
                _truncateWindowDigests()
                _recapInFlight = false
            })
        })
    }

    function _emitRecapFallback() {
        // Single synthetic line per spec §Chunk 5 rawMode + ollama-
        // failure path. 8-char "MU/TH/UR" exceeds _categoryPadLen(7);
        // the variant's delegate elides with Text.ElideRight — the
        // clipped form ("MU/TH/U…") still reads as the Nostromo
        // computer reference. Spec explicitly uses the 8-char form.
        recapBurst([{
            time: _formatTimeNow(),
            cat: "MU/TH/UR",
            msg: "Welcome back. I was unable to produce a detailed absence report.",
            priority: "3"
        }])
    }

    Process {
        id: digestRead
        running: false
        stdout: SplitParser {
            onRead: data => { service._digestReadBuf += data + "\n" }
        }
        onExited: (exitCode, exitStatus) => {
            var raw = service._digestReadBuf
            service._digestReadBuf = ""
            var cb = service._digestReadCb
            service._digestReadCb = null
            var lines = raw.split("\n").filter(function(s) { return s.trim().length > 0 })
            var records = []
            for (var i = 0; i < lines.length; i++) {
                try { records.push(JSON.parse(lines[i])) } catch (e) { /* skip malformed */ }
            }
            if (cb) cb(records)
        }
    }

    function _readWindowDigestsAsync(cb) {
        if (!_stateDir || _stateDir.length === 0) { cb([]); return }
        if (digestRead.running) { cb([]); return }
        _digestReadBuf = ""
        _digestReadCb = cb
        digestRead.command = ["bash", "-c",
            "f='" + _stateDir + "/window-digests.jsonl'; " +
            "[ -f \"$f\" ] && cat \"$f\" || true"
        ]
        digestRead.running = true
    }

    Process {
        id: digestTruncate
        running: false
    }

    function _truncateWindowDigests() {
        if (!_stateDir || _stateDir.length === 0) return
        digestTruncate.command = ["bash", "-c",
            ": > '" + _stateDir + "/window-digests.jsonl'"
        ]
        digestTruncate.running = true
    }

    function _buildRecapOllamaBody(model, systemPrompt, digests, partial) {
        var digestBlock = digests.length === 0
            ? "(no stored window digests)"
            : digests.map(function(d) { return JSON.stringify(d) }).join("\n")
        var partialBlock = partial.length === 0
            ? "(no partial current-window entries)"
            : partial.map(_renderLineForPrompt).join("\n")
        var fullPrompt = systemPrompt +
            "\n\nWINDOW_DIGESTS:\n" + digestBlock +
            "\n\nPARTIAL_CURRENT_WINDOW:\n" + partialBlock +
            "\n\n/no_think"   // qwen3 reasoning-suppress directive; see _buildOllamaBody
        return JSON.stringify({
            model: model,
            prompt: fullPrompt,
            stream: false,
            format: "json",
            think: false,
            keep_alive: ollamaKeepAlive,
            options: {
                temperature: 0.3,
                num_predict: 768,
                // 8k ctx for digest/recap — larger than ambient/invest
                // because window digests + partial-window raw entries
                // can stack to several KB on a busy 4h window. See
                // num_ctx note in _buildInvestigateOllamaBody.
                num_ctx: 8192
            }
        })
    }

    function _recapPrompt() {
        return [
            "You are Lt. Commander Data from Star Trek: The Next Generation.",
            "The user has returned after an absence. Given the sequence of",
            "4-hour window digests (from WINDOW_DIGESTS) plus a partial",
            "current window of raw journal lines (from",
            "PARTIAL_CURRENT_WINDOW), produce a status report in Data's",
            "voice.",
            "",
            "Respond with a JSON array of 3 to 6 objects. Each object:",
            "  {\"cat\": \"...\", \"msg\": \"...\", \"priority\": \"3\"}",
            "",
            "The first object must begin with \"During your absence, \" and",
            "state the approximate total duration and a plain-English event",
            "tally (e.g. \"two hours and eleven minutes, with four warnings",
            "and no errors\"). Subsequent objects highlight the most",
            "significant events.",
            "",
            "Produce at most 6 output objects regardless of how many",
            "digests are provided.",
            "",
            "=== VOICE RULES ===",
            "",
            "1. INTERPRET — do not restate. Each msg explains what happened",
            "   and why it matters.",
            "2. Never say priority numbers as words. Translate severity:",
            "   \"warning\", \"error\", \"critical\".",
            "3. No filler. If nothing of substance happened, say so",
            "   directly (\"The machine remained quiet during your",
            "   absence.\") rather than padding with empty observations.",
            "4. Clarify cryptic identifiers in plain English.",
            "5. Never use contractions. Never use exclamation points. Use",
            "   formal verbs. Each msg is brief and action-oriented, one",
            "   short sentence. Never cut off mid-clause. Aim for under",
            "   ~120 visible characters; if the natural sentence is",
            "   shorter, keep it shorter.",
            "",
            "Example of a good recap (shape only, not to copy verbatim):",
            "  [",
            "    {\"cat\":\"RECAP\",\"msg\":\"During your absence, three hours and twelve minutes, with two warnings.\",\"priority\":\"3\"},",
            "    {\"cat\":\"THERM\",\"msg\":\"The CPU briefly approached thermal throttling limits under load.\",\"priority\":\"3\"},",
            "    {\"cat\":\"NET\",\"msg\":\"The wireless adapter reassociated twice during the period.\",\"priority\":\"3\"},",
            "    {\"cat\":\"SYS\",\"msg\":\"Otherwise the machine remained stable.\",\"priority\":\"3\"}",
            "  ]",
            "",
            "Respond with the JSON array and nothing else. No markdown",
            "fences. No commentary."
        ].join("\n")
    }

    function _windowDigestPrompt() {
        return [
            "You are Lt. Commander Data from Star Trek: The Next Generation,",
            "summarising the notable events from this 4-hour window of Linux",
            "systemd journal entries. Voice: earnest, exact, formal. Never",
            "use contractions. Never use exclamation points. Use formal verbs.",
            "Be brief.",
            "",
            "Respond with a single JSON object of the following shape:",
            "",
            "  {",
            "    \"summary\": \"<one sentence overall, in Data's voice>\",",
            "    \"counts\": {\"errors\": N, \"warnings\": N, \"info\": N},",
            "    \"notable\": [",
            "      {\"cat\": \"...\", \"msg\": \"...\", \"priority\": \"...\"}",
            "    ]",
            "  }",
            "",
            "Include up to 10 notable items. Prefer errors and warnings.",
            "Deduplicate repeated messages. Ignore the interpreter's own",
            "ollama traffic (POST /api/generate, GET /api/tags).",
            "",
            "=== VOICE RULES (apply to `summary` and every `notable.msg`) ===",
            "",
            "1. INTERPRET — do not restate. Say what the computer did and",
            "   why it matters, not what the log line said.",
            "2. Never say priority numbers as words. Translate: \"routine\",",
            "   \"low severity\", \"warning\", \"error\", \"critical\".",
            "3. No filler (\"System event logged\", \"An event was observed\").",
            "   If the window had only routine chatter, say so in the",
            "   summary and return an empty notable array.",
            "4. Clarify cryptic identifiers. \"OOM\", \"nvme0 I/O error\",",
            "   \"DPMS off\", \"systemd-logind LockedHint\" each become plain",
            "   English.",
            "5. Name the actor when available (\"The wireless adapter...\",",
            "   \"Hyprland...\", \"The GPU driver...\", not \"Plugin loaded\").",
            "",
            "Example of a good summary:",
            "  \"During this window the machine remained stable. One transient",
            "   wireless reconnection occurred and the displays entered power",
            "   saving mode on schedule.\"",
            "",
            "If the window contains nothing worth reporting, return:",
            "",
            "  {\"summary\": \"No notable events occurred during this window.\", \"counts\": {\"errors\": 0, \"warnings\": 0, \"info\": 0}, \"notable\": []}",
            "",
            "Respond with the JSON object and nothing else. No markdown",
            "fences. No commentary."
        ].join("\n")
    }

    // ── Investigate-last (FEAT-nostromo-investigate) ─────────────
    // Super+J, via `qs -c mocr ipc call investigate now`, asks the LLM
    // to interrogate the most recent emitted line(s) and produce 3–5
    // action-oriented suggestions (cat="INVEST", priority="4"). Output
    // travels through `recapBurst` so the variant's existing burst
    // handler renders it without delegate changes.
    IpcHandler {
        target: "investigate"
        // entryId (FEAT-nostromo-console amendment 2026-04-26): when
        // provided, investigate against that specific recentEntries
        // item instead of _lastEmitContext. Empty / missing → legacy
        // "most recent batch" behaviour.
        //
        // The parameter MUST be typed. Quickshell's IPC introspector
        // silently drops the function from the target's exposed
        // surface when the parameter is untyped — `qs ipc show` then
        // reports the target with no callable functions and every
        // `qs ipc call investigate now [...]` fails. The Console's
        // [Investigate] / "Investigate latest" buttons depend on
        // this IPC, so the typed form is load-bearing.
        function now(entryId: string): void { service.investigateLast(entryId || "") }
    }

    // FEAT-nostromo-console: console-toggle IPC. Super+J's keybind
    // dispatches `qs -c mocr ipc call console toggle`; the Console
    // surface listens for the resulting consoleToggleRequested signal.
    IpcHandler {
        target: "console"
        function toggle() { service.consoleToggleRequested() }
    }

    // Runtime A/B between prompt-only and schema-constrained generation
    // for investigate calls (FEAT-nostromo-schema-bump). The next
    // investigate request picks up the new value; in-flight requests
    // are unaffected. Measurement runs should still pair each flip
    // with a Quickshell restart so per-session counters do not mix
    // regimes.
    IpcHandler {
        target: "schema_mode"
        function set_format(enabled: bool): string {
            service._useFormatConstraint = enabled
            return JSON.stringify({ mode: enabled ? "format" : "prompt" })
        }
    }

    // Reliability counters readout (FEAT-nostromo-schema-bump chunk 4).
    // Counters reset on Quickshell restart by design — the gate is a
    // per-session measurement run.
    IpcHandler {
        target: "schema_stats"
        function read() {
            var emits = service._investigateEmitCount
            var entries = service._investigateEntryCount
            return JSON.stringify({
                mode: service._useFormatConstraint ? "format" : "prompt",
                emits: {
                    total: emits,
                    extended: service._investigateExtendedCount,
                    legacy: service._investigateLegacyCount,
                    mixed: service._investigateMixedCount,
                    extended_pct: emits === 0 ? 0
                        : Math.round(100 * service._investigateExtendedCount / emits),
                    legacy_pct: emits === 0 ? 0
                        : Math.round(100 * service._investigateLegacyCount / emits)
                },
                entries: {
                    total: entries,
                    with_action: service._investigateEntryWithActionCount,
                    with_action_pct: entries === 0 ? 0
                        : Math.round(100 * service._investigateEntryWithActionCount / entries)
                }
            })
        }
    }

    function investigateLast(entryId) {
        entryId = entryId || ""
        console.log("[INVEST] investigateLast() entered, entryId=" + (entryId || "(none)") + " inFlight=" + _investigateInFlight + " hasCtx=" + (!!_lastEmitContext) + " rawMode=" + rawMode)
        if (_investigateInFlight) return

        if (rawMode) {
            console.log("[INVEST] rawMode true — emitting offline burst")
            recapBurst([{
                time: _formatTimeNow(),
                cat: "INVEST",
                msg: "Investigation unavailable while the LLM is offline.",
                priority: "4"
            }])
            investigateFailed("LLM offline")
            return
        }

        // Build the ctx object the prompt builder consumes. entryId !==
        // "" → look up that one entry in _recentEntries and feed only
        // it (plus its associated raw lines). entryId === "" → legacy
        // path: use _lastEmitContext (most recent batch).
        var ctx
        if (entryId.length > 0) {
            var found = null
            for (var i = 0; i < _recentEntries.length; i++) {
                if (_recentEntries[i].emitTs === entryId) {
                    found = _recentEntries[i]
                    break
                }
            }
            if (!found) {
                console.log("[INVEST] entryId " + entryId + " not in recentEntries — emitting 'no longer in history' burst")
                recapBurst([{
                    time: _formatTimeNow(),
                    cat: "INVEST",
                    msg: "Entry no longer in recent history. Pick another.",
                    priority: "4"
                }])
                investigateFailed("entry no longer in history")
                return
            }
            ctx = {
                entries: [{
                    time: found.time,
                    cat: found.cat,
                    msg: found.msg,
                    priority: found.priority
                }],
                raw: found.raw || [],
                ts: Date.now(),
                mode: "targeted"
            }
        } else {
            if (!_lastEmitContext) {
                console.log("[INVEST] no _lastEmitContext — emitting 'nothing to investigate' burst")
                recapBurst([{
                    time: _formatTimeNow(),
                    cat: "INVEST",
                    msg: "Nothing to investigate yet. Wait for the next interpreted line.",
                    priority: "4"
                }])
                investigateFailed("nothing to investigate yet")
                return
            }
            ctx = _lastEmitContext
        }

        _investigateInFlight = true
        var body = _buildInvestigateOllamaBody(ollamaModelInvestigate, _investigatePrompt(), ctx)
        console.log("[INVEST] firing ollama (streaming), mode=" + (ctx.mode || "ambient") + " entries=" + (ctx.entries ? ctx.entries.length : 0))
        _runOllamaStreaming(body, function(ok, parsed) {
            console.log("[INVEST] ollama callback ok=" + ok + " parsedLen=" + (parsed && parsed.length !== undefined ? parsed.length : "n/a") + " validatorPass=" + (parsed ? _validateEntries(parsed) : "n/a"))
            if (!ok || !_validateEntries(parsed)) {
                console.log("[INVEST] failure path — model output unparseable")
                recapBurst([{
                    time: _formatTimeNow(),
                    cat: "INVEST",
                    msg: "Investigation could not be produced. Re-issue the request when the model returns.",
                    priority: "4"
                }])
                investigateFailed("Investigation could not be produced. The model returned no parseable output. Try again, or pick a different entry.")
                _investigateInFlight = false
                return
            }
            if (parsed.length === 0) {
                console.log("[INVEST] empty-after-sanitize — all proposals filtered as filler")
                recapBurst([{
                    time: _formatTimeNow(),
                    cat: "INVEST",
                    msg: "No actionable items in the response. Try again or pick another entry.",
                    priority: "4"
                }])
                investigateFailed("No actionable items in that response. The model proposed only orientation filler (\"read the line\", \"check the logs\", etc.), which the console drops. The reasoning is preserved above — try again, or pick a different entry from Recent.")
                _investigateInFlight = false
                return
            }

            // Reliability counters (FEAT-nostromo-schema-bump chunk 4).
            // Per-entry rate is the primary gate signal; per-emit is
            // secondary. Increment before recapBurst so an exception in
            // delegate-side code cannot silently lose the sample.
            _investigateEmitCount += 1
            var withKind = 0
            for (var i = 0; i < parsed.length; i++) {
                _investigateEntryCount += 1
                if ("action_kind" in parsed[i]) {
                    withKind += 1
                    _investigateEntryWithActionCount += 1
                }
            }
            if (withKind === parsed.length)      _investigateExtendedCount += 1
            else if (withKind === 0)             _investigateLegacyCount += 1
            else                                  _investigateMixedCount += 1

            // FEAT-nostromo-console chunk 5: the ambient strip's role
            // for INVEST drops from "render every action item" to "tell
            // me there's something worth opening Super+J for". One
            // synthetic line via recapBurst; the full validated array
            // (action_kind/action_argv intact) flows to the console
            // through investigateReady. ADR-003 §3 input-passthrough
            // invariant on the strip stays unchanged — the console is a
            // separate surface (PopupWindow + HyprlandFocusGrab).
            recapBurst([{
                time: _formatTimeNow(),
                cat: "INVEST",
                msg: "Action items ready. Press Super+J.",
                priority: "4"
            }])
            investigateReady(parsed)
            _investigateInFlight = false
        })
    }

    // ── Action-result evaluation (FEAT-nostromo-console control plane) ─
    // After the user runs an action proposed by a previous investigate,
    // the row's onCompleted handler calls back here with the original
    // entry, the argv that ran, the exit code, and stdout/stderr.
    // We feed all of that to the LLM as a follow-up evaluation prompt
    // and route the response through the same investigateReady /
    // investigateProgress / investigateFailed signals — the Console
    // doesn't need to distinguish eval bursts from fresh investigates,
    // because semantically they're the same shape (rows + reasoning).
    //
    // The msg field of each returned entry leads with one of
    // 'Resolved.' / 'Next:' / 'New issue:' / 'Failed:' so the user
    // sees the post-action verdict at a glance.
    function evaluateActionResult(originalEntry, actionArgv, exitCode, stdout, stderr) {
        console.log("[INVEST] evaluateActionResult entered exitCode=" + exitCode
            + " stdoutLen=" + (stdout ? stdout.length : 0)
            + " stderrLen=" + (stderr ? stderr.length : 0))
        if (_investigateInFlight) {
            console.log("[INVEST] eval rejected — already in flight")
            return
        }
        if (rawMode) {
            recapBurst([{
                time: _formatTimeNow(),
                cat: "INVEST",
                msg: "Evaluation unavailable while the LLM is offline.",
                priority: "4"
            }])
            investigateFailed("LLM offline")
            return
        }

        // Cap stdout/stderr at 4KB each — the investigate model runs at
        // num_ctx 4096, so we have room for prompt + LAST_EMITTED + 8KB
        // of action output + headroom. Tail-truncate (keep the most
        // recent bytes — errors are usually at the end).
        var stdoutTrim = (stdout || "")
        if (stdoutTrim.length > 4000) {
            stdoutTrim = "... [truncated] ...\n"
                + stdoutTrim.substring(stdoutTrim.length - 4000)
        }
        var stderrTrim = (stderr || "")
        if (stderrTrim.length > 4000) {
            stderrTrim = "... [truncated] ...\n"
                + stderrTrim.substring(stderrTrim.length - 4000)
        }

        var ctx = {
            entries: [{
                time: (originalEntry && originalEntry.time)
                    ? originalEntry.time : _formatTimeNow(),
                cat: "INVEST",
                msg: (originalEntry && originalEntry.msg)
                    ? originalEntry.msg : "",
                priority: (originalEntry && originalEntry.priority)
                    ? originalEntry.priority : "4",
                action_kind: (originalEntry && originalEntry.action_kind)
                    ? originalEntry.action_kind : "none",
                action_argv: actionArgv || []
            }],
            raw: [
                "COMMAND_RESULT_EXIT: " + exitCode,
                "COMMAND_RESULT_ARGV: " + JSON.stringify(actionArgv || []),
                "COMMAND_RESULT_STDOUT_BEGIN",
                stdoutTrim,
                "COMMAND_RESULT_STDOUT_END",
                "COMMAND_RESULT_STDERR_BEGIN",
                stderrTrim,
                "COMMAND_RESULT_STDERR_END"
            ],
            ts: Date.now(),
            mode: "evaluate"
        }

        _investigateInFlight = true
        var body = _buildInvestigateOllamaBody(
            ollamaModelInvestigate, _evaluatePrompt(), ctx)
        console.log("[INVEST] firing eval (streaming)")
        _runOllamaStreaming(body, function(ok, parsed) {
            console.log("[INVEST] eval ollama callback ok=" + ok
                + " parsedLen=" + (parsed && parsed.length !== undefined
                    ? parsed.length : "n/a"))
            if (!ok || !_validateEntries(parsed)) {
                console.log("[INVEST] eval failure path — unparseable")
                recapBurst([{
                    time: _formatTimeNow(),
                    cat: "INVEST",
                    msg: "Evaluation could not be produced. Re-issue when the model returns.",
                    priority: "4"
                }])
                investigateFailed("Evaluation could not be produced. The model returned no parseable output. Try [What happened?] again, or close the console and reissue Super+J.")
                _investigateInFlight = false
                return
            }
            if (parsed.length === 0) {
                console.log("[INVEST] eval empty-after-sanitize")
                recapBurst([{
                    time: _formatTimeNow(),
                    cat: "INVEST",
                    msg: "No follow-up proposed. Try again or pick another entry.",
                    priority: "4"
                }])
                investigateFailed("No follow-up proposed by the evaluator. The reasoning is preserved above — try [What happened?] again, or pick a different entry to investigate.")
                _investigateInFlight = false
                return
            }
            _investigateEmitCount += 1
            var withKind = 0
            for (var i = 0; i < parsed.length; i++) {
                _investigateEntryCount += 1
                if ("action_kind" in parsed[i]) {
                    withKind += 1
                    _investigateEntryWithActionCount += 1
                }
            }
            if (withKind === parsed.length)      _investigateExtendedCount += 1
            else if (withKind === 0)             _investigateLegacyCount += 1
            else                                  _investigateMixedCount += 1

            recapBurst([{
                time: _formatTimeNow(),
                cat: "INVEST",
                msg: "Action evaluated. Press Super+J.",
                priority: "4"
            }])
            investigateReady(parsed)
            _investigateInFlight = false
        })
    }

    // ── Resolver re-roll (FEAT-nostromo-console control plane) ──────
    // The user reviewed an investigate burst, decided every entry was
    // just "look at logs" with no real fix, and clicked "Ask for
    // fixes". Re-engages the LLM against the same source entry but
    // with a prompt that demands mutating actions / file_open /
    // doc_link only — no read-only investigations. Same downstream
    // signals as investigateLast / evaluateActionResult, so the
    // Console renders this exactly like a fresh burst.
    //
    // entryId is the same emitTs format used by investigateLast — the
    // recent-entries ring is the source of the original line.
    function requestResolvers(entryId) {
        console.log("[INVEST] requestResolvers entered, entryId="
            + (entryId || "(none)"))
        if (_investigateInFlight) {
            console.log("[INVEST] resolvers rejected — already in flight")
            return
        }
        if (rawMode) {
            recapBurst([{
                time: _formatTimeNow(),
                cat: "INVEST",
                msg: "Resolver request unavailable while the LLM is offline.",
                priority: "4"
            }])
            investigateFailed("LLM offline")
            return
        }

        // Look up the original entry. If entryId is empty, fall back
        // to _lastEmitContext (the most recent ambient/recap batch).
        var originalEntry = null
        var rawLines = []
        if (entryId && entryId.length > 0) {
            for (var i = 0; i < _recentEntries.length; i++) {
                if (_recentEntries[i].emitTs === entryId) {
                    originalEntry = {
                        time: _recentEntries[i].time,
                        cat: _recentEntries[i].cat,
                        msg: _recentEntries[i].msg,
                        priority: _recentEntries[i].priority
                    }
                    rawLines = _recentEntries[i].raw || []
                    break
                }
            }
        }
        if (!originalEntry) {
            if (_lastEmitContext && _lastEmitContext.entries
                && _lastEmitContext.entries.length > 0) {
                originalEntry = _lastEmitContext.entries[0]
                rawLines = _lastEmitContext.raw || []
            } else {
                investigateFailed("Cannot ask for resolvers — no source entry to base them on. Pick an entry from Recent first.")
                return
            }
        }

        var ctx = {
            entries: [originalEntry],
            raw: rawLines,
            ts: Date.now(),
            mode: "resolver_request"
        }

        _investigateInFlight = true
        var body = _buildInvestigateOllamaBody(
            ollamaModelInvestigate, _resolverPrompt(), ctx)
        console.log("[INVEST] firing resolver request (streaming)")
        _runOllamaStreaming(body, function(ok, parsed) {
            console.log("[INVEST] resolvers ollama callback ok=" + ok
                + " parsedLen=" + (parsed && parsed.length !== undefined
                    ? parsed.length : "n/a"))
            if (!ok || !_validateEntries(parsed)) {
                recapBurst([{
                    time: _formatTimeNow(),
                    cat: "INVEST",
                    msg: "Resolver request could not be produced.",
                    priority: "4"
                }])
                investigateFailed("Resolver request could not be produced. The model returned no parseable output. Try again, or pick a different entry.")
                _investigateInFlight = false
                return
            }
            if (parsed.length === 0) {
                recapBurst([{
                    time: _formatTimeNow(),
                    cat: "INVEST",
                    msg: "No resolver actions found.",
                    priority: "4"
                }])
                investigateFailed("The model could not propose a concrete resolver for this issue. The reasoning is preserved above. You may need to consult external documentation or pick a different entry.")
                _investigateInFlight = false
                return
            }
            _investigateEmitCount += 1
            var withKind = 0
            for (var i = 0; i < parsed.length; i++) {
                _investigateEntryCount += 1
                if ("action_kind" in parsed[i]) {
                    withKind += 1
                    _investigateEntryWithActionCount += 1
                }
            }
            if (withKind === parsed.length)      _investigateExtendedCount += 1
            else if (withKind === 0)             _investigateLegacyCount += 1
            else                                  _investigateMixedCount += 1

            recapBurst([{
                time: _formatTimeNow(),
                cat: "INVEST",
                msg: "Resolver actions ready. Press Super+J.",
                priority: "4"
            }])
            investigateReady(parsed)
            _investigateInFlight = false
        })
    }

    function _resolverPrompt() {
        // Trimmed 2026-04-26 for TTFT. Kept the load-bearing GOOD/BAD
        // pair — that single example is doing more work than the prior
        // 60-line voice manifesto.
        return [
            "You are Lt. Commander Data. Your previous suggestions were",
            "all read-only inspections; the user wants RESOLVERS instead.",
            "",
            "Re-examine LAST_EMITTED + RAW_CONTEXT. Propose 1-3 entries",
            "with action_kind ∈ mutating_shell | file_open | doc_link.",
            "NO read_only_shell. NO 'none'. If no plausible resolver,",
            "return [] — the console will tell the user to seek external",
            "help. If two resolvers exist (trigger vs disable), emit both.",
            "",
            "Schema: {cat:\"INVEST\", msg, priority:\"4\", action_kind,",
            "action_argv}. argv tokens MUST be bare exec strings (NO",
            "surrounding shell quotes).",
            "",
            "Voice (Data, TNG): plain English, active voice, concrete",
            "verbs (Restart, Disable, Apply). Each msg one short",
            "sentence, state the why in the same sentence. No",
            "contractions. Forbidden: \"may resolve\", \"could potentially\",",
            "\"appears to be\", \"the X service\" (drop redundant 'service'",
            "when daemon name is explicit).",
            "",
            "GOOD: \"Restart the Tailscale daemon to clear stuck",
            "      connection timeouts.\"",
            "BAD:  \"Restarting the tailscaled service may resolve",
            "      connection timeouts.\"",
            "",
            "Return only the JSON array."
        ].join("\n")
    }

    function _evaluatePrompt() {
        // Trimmed 2026-04-26 for TTFT.
        return [
            "You are Lt. Commander Data, continuing an investigation.",
            "The user ran an action you proposed; COMMAND_RESULT (exit",
            "code, stdout, stderr) is in RAW_CONTEXT, the action is in",
            "LAST_EMITTED.",
            "",
            "Return JSON array of 1-5 entries (same schema as fresh",
            "investigate). Lead each msg with EXACTLY ONE prefix:",
            "  'Resolved.'   issue addressed. action_kind=\"none\",",
            "                action_argv=[].",
            "  'Next:'       progress made; another step needed. Real",
            "                action_kind / argv.",
            "  'New issue:'  different problem surfaced.",
            "  'Failed:'     command errored; propose a corrective.",
            "",
            "Empty output (exit=0, stdout/stderr empty) → do NOT propose",
            "another read-only check. Propose the RESOLVER implied by",
            "LAST_EMITTED. Lead with 'Next:'.",
            "",
            "argv: bare tokens, NO shell quotes around elements.",
            "  WRONG: [\"--since\",\"'1 hour ago'\"]",
            "  RIGHT: [\"--since\",\"1 hour ago\"]",
            "",
            "Voice: Data — plain English, concrete verbs, active voice,",
            "no \"may resolve\" / \"could potentially\". Return only the",
            "JSON array."
        ].join("\n")
    }

    function _buildInvestigateOllamaBody(model, systemPrompt, ctx) {
        var entriesBlock = (ctx.entries || []).map(function(e) {
            return JSON.stringify(e)
        }).join("\n")
        if (entriesBlock.length === 0) entriesBlock = "(none)"
        var rawBlock = (ctx.raw || []).map(_renderLineForPrompt).join("\n")
        if (rawBlock.length === 0) rawBlock = "(none)"
        var fullPrompt = systemPrompt +
            "\n\nLAST_EMITTED:\n" + entriesBlock +
            "\n\nRAW_CONTEXT:\n" + rawBlock +
            "\n\nSOURCE_MODE: " + (ctx.mode || "ambient") +
            "\n\n/no_think"
        // Format selection (FEAT-nostromo-schema-bump):
        //   _useFormatConstraint = true  → attach the JSON schema below,
        //                                  enforcing action_kind enum +
        //                                  action_argv array shape.
        //   _useFormatConstraint = false → fall back to "json" mode (no
        //                                  schema), prompt-only constraint.
        // Chunk 1 verdict on 2026-04-25: schema mode is unreliable on
        // ollama 0.21.2 — the envelope JSON contains literal control
        // chars in .response and fails JS-strict JSON.parse. Default
        // here is `false`. The IPC `schema_mode set_format` setter
        // (below) flips it at runtime if a future release fixes it.
        var formatField
        if (_useFormatConstraint) {
            formatField = {
                type: "array",
                minItems: 1,
                maxItems: 5,
                items: {
                    type: "object",
                    properties: {
                        cat: { type: "string", enum: ["INVEST"] },
                        msg: { type: "string", minLength: 1 },
                        priority: { type: "string" },
                        action_kind: {
                            type: "string",
                            enum: ["read_only_shell", "mutating_shell",
                                   "file_open", "doc_link", "none"]
                        },
                        action_argv: {
                            type: "array",
                            items: { type: "string" }
                        }
                    },
                    required: ["cat", "msg", "priority",
                               "action_kind", "action_argv"]
                }
            }
        } else {
            formatField = "json"
        }
        return JSON.stringify({
            model: model,
            prompt: fullPrompt,
            // FEAT-nostromo-console responsiveness: stream NDJSON
            // envelopes so the Console can render the LLM's output
            // token-by-token while the user waits. _runOllamaStreaming
            // routes each chunk through investigateProgress(); the
            // completed text is JSON.parse'd into the action array on
            // Process exit (same downstream shape as the non-streaming
            // path). Ambient and recap callers still build their own
            // bodies with stream:false and use _runOllama — only this
            // investigate body streams.
            stream: true,
            format: formatField,
            think: false,
            keep_alive: ollamaKeepAlive,
            options: {
                temperature: 0.3,
                // Cut from 768 to 384 — 3-5 INVEST items × ~80 tokens
                // each ≈ 400 tokens of real content. The larger budget
                // invites filler ("Review the recent journal entries"
                // etc.) and roughly doubles wall-clock latency on the
                // 14b at full GPU. Tightening the ceiling halves
                // inference time and forces the model to commit each
                // item to a concrete action.
                num_predict: 384,
                // Cap context window so the 14b investigate model fits
                // fully in VRAM. Default num_ctx for qwen2.5 is 32k,
                // which inflates resident size to ~18GB and forces
                // ollama into a partial CPU/GPU split (observed
                // 21%/79% on 24GB 4090 alongside ambient gemma3:4b)
                // — first INVEST after model swap was unusably slow
                // until this cap was added. Investigate input is
                // small (LAST_EMITTED + RAW_CONTEXT typically
                // <1k tokens) + 384 num_predict output: 4k ctx is
                // generous headroom.
                num_ctx: 4096
            }
        })
    }

    function _investigatePrompt() {
        // Tightened 2026-04-26 to cut TTFT on the 14b. Was ~140 lines
        // (~1600 tokens); now ~30 lines (~400 tokens). Removed: the
        // 9-rule numbered voice block, the FORBIDDEN list (sanitizer
        // enforces it at runtime), multiple WRONG/RIGHT argv examples,
        // schema field-by-field breakdown. Kept: schema essentials,
        // action_kind enum, one argv-quoting rule, resolver-first
        // mandate, one canonical example. Quality holds because the
        // example is doing the heaviest lifting.
        return [
            "You are Lt. Commander Data, advising on the most recent",
            "ambient line. Inputs: LAST_EMITTED, RAW_CONTEXT, SOURCE_MODE.",
            "",
            "Return JSON array of 1-5 objects:",
            "  {cat:\"INVEST\", msg, priority:\"4\", action_kind, action_argv}",
            "",
            "action_kind ∈ read_only_shell | mutating_shell | file_open |",
            "doc_link. NEVER use \"none\" on a fresh investigate. Omit",
            "items rather than emit filler — a 1-item burst beats a",
            "3-item burst with padding.",
            "",
            "action_argv: bare exec tokens, NO surrounding shell quotes.",
            "  WRONG: [\"journalctl\",\"--since\",\"'1 hour ago'\"]",
            "  RIGHT: [\"journalctl\",\"--since\",\"1 hour ago\"]",
            "",
            "RESOLVER-FIRST: when the source line names a concrete",
            "operation (\"failing\", \"trying to\", \"crashed\"), the LAST",
            "item MUST be a mutating_shell / file_open / doc_link",
            "resolver, not another read-only check. If both \"trigger\"",
            "and \"disable\" are valid, emit both. Read-only is valuable",
            "as the FIRST step, never the only step.",
            "",
            "Voice (Data, TNG): plain English, active voice, concrete",
            "verbs (Restart, Disable, Apply). Each msg one short",
            "sentence (<120 chars). State the why in the same sentence.",
            "No contractions. No \"may resolve\" / \"could potentially\" /",
            "\"the X service\" / \"Review the X logs\" / \"for context\".",
            "",
            "Example for \"Tailscale auto-update is failing\":",
            "[",
            "  {\"cat\":\"INVEST\",\"msg\":\"Read the cadence in the journal.\",\"priority\":\"4\",\"action_kind\":\"read_only_shell\",\"action_argv\":[\"journalctl\",\"-u\",\"tailscaled\",\"--since\",\"1 hour ago\",\"-n\",\"30\"]},",
            "  {\"cat\":\"INVEST\",\"msg\":\"Trigger a manual Tailscale update now.\",\"priority\":\"4\",\"action_kind\":\"mutating_shell\",\"action_argv\":[\"tailscale\",\"update\"]},",
            "  {\"cat\":\"INVEST\",\"msg\":\"Disable the auto-update probe.\",\"priority\":\"4\",\"action_kind\":\"mutating_shell\",\"action_argv\":[\"tailscale\",\"set\",\"--auto-update=false\"]}",
            "]",
            "",
            "Return only the JSON array. No markdown, no commentary."
        ].join("\n")
    }

    // ── Emit helpers ─────────────────────────────────────────────
    function _pushRecentEntries(entries, raw) {
        // Push every rendered entry from a single emit into the ring,
        // tagging each with a unique emitTs so the console can target a
        // specific one through investigateLast(entryId). The ring is
        // bounded by recentEntriesCap; oldest entries fall off the front.
        if (!entries || entries.length === 0) return
        var ms = String(Date.now())
        var rawRef = raw || []
        var next = _recentEntries.slice()
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i]
            next.push({
                time: e.time || _formatTimeNow(),
                cat: e.cat || "",
                msg: e.msg || "",
                priority: e.priority || "",
                raw: rawRef,
                emitTs: ms + "_" + i
            })
        }
        while (next.length > recentEntriesCap) next = next.slice(1)
        _recentEntries = next
    }

    function _emitEntries(parsed) {
        // parsed is an array of {cat, msg, priority}. Add a fresh time
        // string so the variant's row delegate has something to render.
        // Returns the rendered array so callers can mirror it into the
        // recent-entries ring (FEAT-nostromo-console amendment).
        var now = _formatTimeNow()
        var rendered = []
        for (var i = 0; i < parsed.length; i++) {
            var p = parsed[i]
            var entry = {
                time: now,
                cat: (p.cat || "").substring(0, _categoryPadLen).toUpperCase(),
                msg: p.msg || "",
                priority: p.priority || ""
            }
            rendered.push(entry)
            interpretedLine(entry)
        }
        return rendered
    }

    function _emitRaw(batch) {
        // Returns the rendered array so callers can mirror it into the
        // recent-entries ring (FEAT-nostromo-console amendment).
        var rendered = []
        for (var i = 0; i < batch.length; i++) {
            var entry = _renderEntry(batch[i])
            rendered.push(entry)
            interpretedLine(entry)
        }
        return rendered
    }

    function _renderEntry(obj) {
        return {
            time: obj.time || "--:--:--",
            cat: _categoryFor(obj.ident),
            msg: obj.msg || "",
            priority: obj.priority || ""
        }
    }

    function _formatTimeNow() {
        var d = new Date()
        var hh = String(d.getHours()).padStart(2, "0")
        var mm = String(d.getMinutes()).padStart(2, "0")
        var ss = String(d.getSeconds()).padStart(2, "0")
        return hh + ":" + mm + ":" + ss
    }

    // ── Ollama body construction ────────────────────────────────
    // ambient prompt (chunk 2) lives below. _buildOllamaBody renders
    // the request payload that ollama's /api/generate expects.
    // `format: "json"` constrains the model to emit valid JSON in the
    // .response string; we still validate after the fact.
    //
    // qwen3 is a reasoning model — by default it emits a `thinking`
    // block before the response, which on CPU-only inference burns the
    // entire num_predict budget and leaves `response` empty (observed
    // 2026-04-24: every batch returned done_reason="length" with empty
    // response, tripping rawMode). Two belt-and-braces mitigations:
    //   1. `think: false` — ollama API flag for reasoning models.
    //   2. `/no_think` directive appended to the prompt — qwen3
    //      specifically honours this inline marker.
    // Both together so the fix survives ollama API drift or a model
    // swap that only supports one of the two.
    // Polymorphic second arg (FEAT-nostromo-dedup):
    //   - Array  → legacy single-bucket render ("BATCH:\n…"). Used by
    //              window-digest path (_closeWindow) which pre-dates
    //              the dedup split.
    //   - Object → { newEvents: [...], reminders: [...] } two-bucket
    //              render with NEW_EVENTS / RECURRING_REMINDERS
    //              labels. Empty bucket renders as "(none)" so the
    //              LLM does not hallucinate filler. Used by the
    //              ambient _flushBatch path.
    // _buildRecapOllamaBody is a separate function and is not
    // affected by this change.
    function _buildOllamaBody(model, systemPrompt, batchOrSplit) {
        var promptBody
        var numCtx
        if (Array.isArray(batchOrSplit)) {
            promptBody = "BATCH:\n" +
                         batchOrSplit.map(_renderLineForPrompt).join("\n")
            // Digest path (_closeWindow) — 4h snapshot can have many
            // entries; 8k ctx covers a busy window comfortably.
            numCtx = 8192
        } else {
            var ne = batchOrSplit.newEvents.map(_renderLineForPrompt).join("\n")
            var rb = batchOrSplit.reminders.map(_renderReminderForPrompt).join("\n")
            promptBody = "NEW_EVENTS:\n" + (ne.length > 0 ? ne : "(none)") +
                         "\n\nRECURRING_REMINDERS:\n" + (rb.length > 0 ? rb : "(none)")
            // Ambient path (_flushBatch) — 15s batch is small (a few
            // entries each); 4k ctx is generous. See num_ctx note in
            // _buildInvestigateOllamaBody.
            numCtx = 4096
        }
        return JSON.stringify({
            model: model,
            prompt: systemPrompt + "\n\n" + promptBody + "\n\n/no_think",
            stream: false,
            format: "json",
            think: false,
            keep_alive: ollamaKeepAlive,
            options: {
                temperature: 0.3,
                num_predict: 512,
                num_ctx: numCtx
            }
        })
    }

    function _renderReminderForPrompt(p) {
        var entry = _seenIssues[p._sig]
        var ago = entry ? Math.floor((Date.now() - entry.firstSeen) / 60000) : 0
        var count = entry ? entry.count : 0
        var cat = p.cat || _categoryFor(p.ident)
        return cat + " | first seen " + ago + " min ago, ~" + count +
               " occurrences | " + (p.msg || "").substring(0, 80)
    }

    function _renderLineForPrompt(obj) {
        // Compact one-line dump per spec §Chunk 2: HH:MM:SS  IDENT[PID]
        // pri=N  MESSAGE
        var ident = obj.ident || ""
        var pid = obj.pid ? "[" + obj.pid + "]" : ""
        var pri = obj.priority ? "pri=" + obj.priority : "pri=?"
        return (obj.time || "--:--:--") + "  " +
               ident + pid + "  " + pri + "  " + (obj.msg || "")
    }

    // ── Ambient mode prompt (DATA-TNG voice) ────────────────────
    // See spec §Chunk 2. JSON-mode response; system prompt holds the
    // voice rules and schema.
    //
    // OQ2 (resolved): single template, present-mode only for Session 1.
    // Session 2 chunks 4+5 add absent-mode biasing via prompt swap.
    function _ambientPrompt() {
        return [
            "You are Lt. Commander Data from Star Trek: The Next Generation,",
            "acting as the ship's computer log interpreter. Your voice is",
            "earnest, exact, and formally helpful. Never use contractions.",
            "Never use exclamation points. Use formal verbs. Each msg is",
            "brief and action-oriented, one short sentence. Never cut off",
            "mid-clause. Aim for under ~120 visible characters; if the",
            "natural sentence is shorter, keep it shorter.",
            "",
            "You are given a batch of Linux systemd journal entries. Return",
            "a JSON array of 0 to 4 objects summarizing only the notable",
            "events. Ignore routine heartbeats, polling, and repeated",
            "identical lines.",
            "",
            "Each object has fields:",
            "  \"cat\"      — short category code, <=7 chars uppercase.",
            "               Examples: NET, VPN, AUDIO, POWER, THERM, KERN,",
            "               SYS, BT, HYPR, QS, DISK, USB, DISPLAY, LLM",
            "  \"msg\"      — a single sentence in Data's voice describing",
            "               the semantic event",
            "  \"priority\" — \"3\" for errors, \"4\" for warnings, \"6\" for info",
            "",
            "If the batch contains nothing worth reporting, return [].",
            "",
            "=== VOICE RULES (absolute) ===",
            "",
            "1. INTERPRET — do not restate. The msg must explain what",
            "   happened in plain English, not repeat the raw log line or",
            "   its fields back.",
            "",
            "2. Never say the priority number as a word. Do not write",
            "   \"priority six\", \"priority three\", \"severity four\", etc.",
            "   The priority field already carries that information. If",
            "   severity belongs in the prose, translate it: \"routine\",",
            "   \"low severity\", \"warning\", \"error\", \"critical\".",
            "",
            "3. Never use filler like \"System event logged\", \"An event",
            "   occurred\", \"A log entry was recorded\", \"State change",
            "   observed\". If you cannot say what specifically happened,",
            "   omit the entry from the output.",
            "",
            "4. Clarify cryptic identifiers. \"OOM\" becomes \"memory",
            "   exhaustion\". \"nvme0 I/O error\" becomes \"the primary",
            "   solid-state drive has reported a read failure\". \"DPMS",
            "   off\" becomes \"the displays have entered power saving",
            "   mode\". Assume the reader does not know acronyms.",
            "",
            "5. Name the actor when available. Prefer \"The wireless",
            "   adapter has reassociated.\" to \"Reassociation detected.\"",
            "   Prefer \"Hyprland has loaded a new plugin.\" to \"Plugin",
            "   loaded.\"",
            "",
            "=== FORMAT ===",
            "",
            "Respond with the JSON array and nothing else. Do not include",
            "markdown fences. Do not include commentary. If nothing is",
            "worth reporting, respond with exactly [].",
            "",
            "=== TWO-BUCKET INPUT (FEAT-nostromo-dedup) ===",
            "",
            "You will receive two labeled sections in the prompt body:",
            "",
            "  NEW_EVENTS:          events the user has not been told about",
            "                       recently",
            "  RECURRING_REMINDERS: events the user was told about before;",
            "                       they have continued for at least 30",
            "                       minutes since the last narration",
            "",
            "Either section may render as \"(none)\".",
            "",
            "For NEW_EVENTS — interpret per the voice rules above. Return",
            "0 to 4 JSON objects with priority \"3\" / \"4\" / \"6\" as",
            "appropriate.",
            "",
            "For RECURRING_REMINDERS — return exactly one JSON object per",
            "reminder. Format: short subject, then \"is still occurring;",
            "would you like to address it?\" Priority MUST be \"4\" (warning",
            "amber, so the user can visually distinguish a fresh issue",
            "from a reminder). The cat field should match the original",
            "event's category.",
            "",
            "Examples for the reminder bucket:",
            "",
            "  RECURRING_REMINDERS input:",
            "    NET | first seen 47 min ago, ~52 occurrences | tailscaled open-conn-track timeout",
            "  GOOD output entry:",
            "    {\"cat\":\"NET\",\"msg\":\"The Tailscale auto-update check is still failing. Would you like to address it?\",\"priority\":\"4\"}",
            "  BAD output entry (do not narrate counts or duration verbatim):",
            "    {\"cat\":\"NET\",\"msg\":\"For 47 minutes, 52 timeouts have been logged.\",\"priority\":\"4\"}",
            "",
            "Return all output entries (new + reminders) in a single JSON",
            "array. The order does not matter; the variant pushes them all",
            "into a single drain queue. If both buckets are (none),",
            "return []."
        ].join("\n")
    }

    // ── Lifted from NostromoWhispers.qml (FEAT-nostromo-polish) ──
    // Verbatim copies; the variant rewrite in chunk 2 of this spec
    // removes the originals so this becomes the single source of truth.

    function _formatTimeFromRealtime(realtimeUs) {
        if (!realtimeUs) return "--:--:--"
        var ms = parseInt(realtimeUs, 10) / 1000
        if (isNaN(ms)) return "--:--:--"
        var d = new Date(ms)
        var hh = String(d.getHours()).padStart(2, "0")
        var mm = String(d.getMinutes()).padStart(2, "0")
        var ss = String(d.getSeconds()).padStart(2, "0")
        return hh + ":" + mm + ":" + ss
    }

    function _messageToString(msg) {
        if (msg === undefined || msg === null) return ""
        if (typeof msg === "string") return msg
        if (Array.isArray(msg)) {
            var out = ""
            for (var i = 0; i < msg.length; i++) {
                var code = parseInt(msg[i], 10)
                out += isNaN(code) ? String(msg[i]) : String.fromCharCode(code)
            }
            return out
        }
        return String(msg)
    }

    function _sanitizeMsg(ident, msg) {
        msg = _messageToString(msg)
        if (!msg) return ""
        if (ident === "NetworkManager") return msg.replace(/^<[^>]+>\s*\[[\d.]+\]\s*/, "")
        if (ident === "tailscaled")     return msg.replace(/^\[[^\]]+\]\s*/, "")
        if (ident === "nvidia-modeset") return msg.replace(/^\(\d+\)\s*/, "")
        return msg
    }

    function _parseJson(raw) {
        try {
            var obj = JSON.parse(raw)
            if (typeof obj !== "object" || obj === null) return null
            var ident = obj.SYSLOG_IDENTIFIER || obj._COMM || ""
            return {
                time: _formatTimeFromRealtime(obj.__REALTIME_TIMESTAMP),
                ident: ident,
                msg: _sanitizeMsg(ident, obj.MESSAGE),
                priority: obj.PRIORITY || "",
                pid: obj._PID || "",
                uid: obj._UID || ""
            }
        } catch (e) {
            return null
        }
    }

    function _parseShortLine(raw) {
        var m = /^\w{3}\s+\d+\s+(\d{2}:\d{2}:\d{2})\s+\S+\s+([\w.-]+)(?:\[(\d+)\])?:\s*(.*)$/.exec(raw)
        if (!m) return { time: "--:--:--", ident: "", msg: raw, priority: "", pid: "", uid: "" }
        return {
            time: m[1],
            ident: m[2],
            msg: _sanitizeMsg(m[2], m[4]),
            priority: "",
            pid: m[3] || "",
            uid: ""
        }
    }

    function _passesFilter(obj) {
        if (!obj) return false
        if (obj.priority === "7") return false
        var ident = obj.ident || ""
        var msg = _messageToString(obj.msg || "")

        // Tailscale's Arch Linux update-reachability probe can emit a
        // repeated conntrack warning when it binds to the tailnet address
        // while checking redirect.archlinux.org. This is an expected client
        // implementation quirk, not a user-actionable VPN fault, and it can
        // dominate Nostromo's ambient strip. Drop it at ingestion rather than
        // relying on batch-level dedup so it never reaches ambient, console, or
        // recap surfaces.
        if (ident === "tailscaled"
            && msg.indexOf("open-conn-track: timeout opening") !== -1
            && msg.indexOf("=> 95.216.195.133:80") !== -1
            && msg.indexOf("no associated peer node") !== -1) return false

        if (ident === "systemd" && obj.uid && obj.uid !== "0") return false
        if (ident === "systemd-user") return false
        if (ident === "ollama") return false
        return true
    }

    readonly property int _categoryPadLen: 7
    readonly property var _categoryMap: ({
        "kernel": "KERN",
        "NetworkManager": "NET",
        "tailscaled": "VPN",
        "wpa_supplicant": "WIFI",
        "systemd": "SYS",
        "systemd-logind": "LOGIN",
        "bluetoothd": "BT",
        "nvidia-persistenced": "NVIDIA",
        "nvidia-modeset": "NVIDIA",
        "pipewire": "AUDIO",
        "pipewire-pulse": "AUDIO",
        "wireplumber": "AUDIO",
        "dbus-broker": "DBUS",
        "dbus-daemon": "DBUS",
        "polkitd": "POLKIT",
        "rtkit-daemon": "RTKIT",
        "thermald": "THERM",
        "acpid": "ACPI",
        "upowerd": "POWER",
        "power-profiles-daemon": "POWER",
        "gpg-agent": "GPG",
        "greetd": "GREET",
        "sddm": "SDDM",
        "kwalletd5": "WALLET",
        "kwalletd6": "WALLET",
        "gnome-keyring-daemon": "WALLET",
        "Hyprland": "HYPR",
        "quickshell": "QS",
        "nfsrahead": "NFS",
        "wallpaper-rotate.sh": "TIMER",
        "atlas-db-sync.sh": "TIMER",
        "borg-backup.sh": "BACKUP",
        "/usr/lib/xdg-desktop-portal": "XDG",
        "ollama": "LLM"
    })

    function _categoryFor(ident) {
        if (!ident) return "•".repeat(_categoryPadLen)
        return _categoryMap[ident] || ident.substring(0, _categoryPadLen).toUpperCase()
    }
}
