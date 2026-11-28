// beeper-transcriber transcribes voice messages arriving on a Beeper account
// with Whisper (a whisper.cpp server), and attaches each transcript the way
// Beeper's own (paid) transcription does: a com.beeper.transcription event in
// the account's !transcriptions:beeper.local room, pointing at the voice
// message. Beeper's apps pick it up on sync and show it under the message
// (format read from Beeper Desktop 4.3's setTranscription/
// handleTranscriptionEvent). Nothing is sent into the chat itself, so no
// bridge forwards it to the other side.
//
// Usage:
//
//	beeper-transcriber login            log in and verify this device (interactive, once)
//	beeper-transcriber run              transcribe new voice messages until stopped
//	beeper-transcriber backfill PERIOD  transcribe the last PERIOD's (2d, 12h) voice messages that have no transcript, send the others' again
//	beeper-transcriber test FILE        transcribe a local audio file and print the result
//
// Settings come from environment variables; see loadConfig.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"github.com/rs/zerolog"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/cryptohelper"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

const transcriptionsRoom = id.RoomID("!transcriptions:beeper.local")

var transcriptionEventType = event.Type{Type: "com.beeper.transcription", Class: event.MessageEventType}

var logger = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.DateTime}).With().Timestamp().Logger()

type config struct {
	stateDir      string
	whisperURL    string
	modelName     string
	language      string
	maxDuration   time.Duration
	maxAge        time.Duration
	allAudio      bool
	transcribeOwn bool
}

func env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

func envSeconds(name string, fallback int) time.Duration {
	n, err := strconv.Atoi(env(name, strconv.Itoa(fallback)))
	if err != nil {
		n = fallback
	}
	return time.Duration(n) * time.Second
}

func loadConfig() config {
	return config{
		// STATE_DIRECTORY is set by systemd's StateDirectory=.
		stateDir:   env("TRANSCRIBER_STATE_DIR", env("STATE_DIRECTORY", filepath.Join(env("XDG_STATE_HOME", os.ExpandEnv("$HOME/.local/state")), "beeper-transcriber"))),
		whisperURL: os.Getenv("WHISPER_URL"),
		// Stored with each transcript, as Beeper does with its own engine.
		modelName: env("WHISPER_MODEL_NAME", "whisper.cpp"),
		language:  os.Getenv("TRANSCRIBE_LANGUAGE"),
		// Longer voice messages are skipped: past 10 minutes it's rarely a
		// voice note, and it would hold up the ones behind it.
		maxDuration: envSeconds("TRANSCRIBE_MAX_SECONDS", 600),
		// Live messages older than this are left alone: history the bridges
		// backfill when an account is added. What came in while this was
		// down is caught up on separately, at startup (catchUp).
		maxAge:        envSeconds("TRANSCRIBE_MAX_AGE_SECONDS", 6*3600),
		allAudio:      env("TRANSCRIBE_ALL_AUDIO", "false") == "true",
		transcribeOwn: env("TRANSCRIBE_OWN", "false") == "true",
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: beeper-transcriber login | run | backfill PERIOD | test FILE")
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	cfg := loadConfig()
	var err error
	switch os.Args[1] {
	case "login":
		err = login(ctx, cfg)
	case "run":
		err = run(ctx, cfg)
	case "backfill":
		if len(os.Args) < 3 {
			err = errors.New("usage: beeper-transcriber backfill PERIOD (e.g. 2d, 12h)")
			break
		}
		err = backfill(ctx, cfg, os.Args[2])
	case "test":
		if len(os.Args) < 3 {
			err = errors.New("usage: beeper-transcriber test FILE")
			break
		}
		err = testFile(ctx, cfg, os.Args[2])
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil && !errors.Is(err, context.Canceled) {
		logger.Fatal().Err(err).Msg("Failed")
	}
}

func testFile(ctx context.Context, cfg config, path string) error {
	w, err := newWhisper(cfg)
	if err != nil {
		return err
	}
	audio, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	t, err := w.transcribe(ctx, audio, filepath.Base(path))
	if err != nil {
		return err
	}
	fmt.Printf("[%s] %s\n", t.language, strings.Join(strings.Fields(t.text), " "))
	return nil
}

func setupCrypto(ctx context.Context, cfg config, client *mautrix.Client, sess *session) (*cryptohelper.CryptoHelper, error) {
	helper, err := cryptohelper.NewCryptoHelper(client, sess.PickleKey, cryptoDBPath(cfg))
	if err != nil {
		return nil, err
	}
	if err = helper.Init(ctx); err != nil {
		return nil, fmt.Errorf("setting up encryption: %w", err)
	}
	client.Crypto = helper
	return helper, nil
}

type transcriber struct {
	cfg     config
	client  *mautrix.Client
	whisper *whisper
	queue   chan *event.Event
	pending *pendingStore

	seenLock sync.Mutex
	seen     map[id.EventID]time.Time
}

// connect sets up the saved login, its encryption, and Whisper — what both
// `run` and `backfill` need. The caller closes the returned crypto helper.
func connect(ctx context.Context, cfg config) (*transcriber, *cryptohelper.CryptoHelper, error) {
	sess, err := loadSession(cfg)
	if err != nil {
		return nil, nil, err
	}
	w, err := newWhisper(cfg)
	if err != nil {
		return nil, nil, err
	}
	client, err := mautrix.NewClient(beeperMatrixURL, sess.UserID, sess.AccessToken)
	if err != nil {
		return nil, nil, err
	}
	client.DeviceID = sess.DeviceID
	client.Log = logger.Level(zerolog.WarnLevel)
	client.Store = &fileSyncStore{path: filepath.Join(cfg.stateDir, "sync.json")}
	client.Syncer.(*mautrix.DefaultSyncer).FilterJSON = syncFilter()
	helper, err := setupCrypto(ctx, cfg, client, sess)
	if err != nil {
		return nil, nil, err
	}
	t := &transcriber{cfg: cfg, client: client, whisper: w, queue: make(chan *event.Event, 100), pending: loadPendingStore(cfg), seen: map[id.EventID]time.Time{}}
	return t, helper, nil
}

func run(ctx context.Context, cfg config) error {
	t, helper, err := connect(ctx, cfg)
	if err != nil {
		return err
	}
	defer helper.Close()
	syncer := t.client.Syncer.(*mautrix.DefaultSyncer)
	syncer.OnEventType(event.EventMessage, t.onMessage)
	syncer.OnEventType(event.EphemeralEventReceipt, t.onReceipt)
	// After being down (a reboot, the machine off overnight), catch up on
	// everything since the last sync: the first sync only brings each
	// chat's last few messages, and older ones fail maxAge anyway. It starts
	// with the second sync, once the first one, which brings the keys to
	// decrypt what came in meanwhile, has been fully handled.
	if lastSync := t.client.Store.(*fileSyncStore).load().SavedAt; lastSync > 0 && time.Since(time.UnixMilli(lastSync)) > 2*time.Minute {
		syncs := 0
		syncer.OnSync(func(ctx context.Context, _ *mautrix.RespSync, _ string) bool {
			if syncs++; syncs == 2 {
				go t.catchUp(ctx, time.UnixMilli(lastSync).Add(-time.Minute))
			}
			return true
		})
	}
	// One at a time: whisper.cpp's server handles one request at a time
	// anyway, and uses every core it's given for it.
	go t.worker(ctx)
	logger.Info().Stringer("user", t.client.UserID).Stringer("device", t.client.DeviceID).Msg("Watching for voice messages")
	err = t.client.SyncWithContext(ctx)
	if errors.Is(err, mautrix.MUnknownToken) {
		return fmt.Errorf("the login was revoked (e.g. the device was removed in Beeper); log in again: %w", err)
	}
	return err
}

// syncFilter keeps syncs to what's needed: message timelines (plain and
// encrypted, so the crypto helper can decrypt them), read receipts (see
// resend.go), plus each room's encryption state and members, which
// encrypting the transcript needs since the transcriptions room is
// encrypted. Encryption keys arrive as to-device events, which filters
// don't touch.
func syncFilter() *mautrix.Filter {
	none := &mautrix.FilterPart{NotTypes: []event.Type{{Type: "*"}}}
	return &mautrix.Filter{
		AccountData: none,
		Presence:    none,
		Room: &mautrix.RoomFilter{
			AccountData: none,
			Ephemeral:   &mautrix.FilterPart{Types: []event.Type{event.EphemeralEventReceipt}},
			State:       &mautrix.FilterPart{Types: []event.Type{event.StateEncryption, event.StateMember}, LazyLoadMembers: true},
			Timeline:    &mautrix.FilterPart{Types: []event.Type{event.EventMessage, event.EventEncrypted}, Limit: 20, LazyLoadMembers: true},
		},
	}
}

// notAudio is skipReason's answer for messages that aren't audio at all.
const notAudio = "-"

// voiceMessage returns the message evt carries and the event a transcript
// of it belongs to. That's evt itself, except for edits: the WhatsApp bridge
// posts a placeholder when it can't decrypt a message right away ("Unavailable
// message" in its log), and edits it into the real message once the phone
// resends it, so a voice message can arrive as an edit — and Beeper shows it
// under the placeholder's event.
func voiceMessage(evt *event.Event) (id.EventID, *event.MessageEventContent) {
	content := evt.Content.AsMessage()
	if replaces := content.RelatesTo.GetReplaceID(); replaces != "" {
		return replaces, content.NewContent
	}
	return evt.ID, content
}

// skipReason says why evt isn't a voice message to transcribe (whatever its
// age), or "" if it is one.
func (t *transcriber) skipReason(evt *event.Event) string {
	if evt.RoomID == transcriptionsRoom || evt.Type != event.EventMessage {
		return notAudio
	}
	_, content := voiceMessage(evt)
	if content == nil || content.MsgType != event.MsgAudio {
		return notAudio
	}
	if !t.cfg.allAudio && content.MSC3245Voice == nil {
		return "audio files, not voice messages" // a song, a recording
	}
	if evt.Sender == t.client.UserID && !t.cfg.transcribeOwn {
		return "sent by you"
	}
	if content.Info != nil && time.Duration(content.Info.Duration)*time.Millisecond > t.cfg.maxDuration {
		return "longer than " + t.cfg.maxDuration.String()
	}
	return ""
}

func (t *transcriber) onMessage(ctx context.Context, evt *event.Event) {
	if reason := t.skipReason(evt); reason != "" {
		if reason != notAudio {
			logger.Info().Stringer("event", evt.ID).Str("reason", reason).Msg("Skipping audio")
		}
		return
	}
	if time.Since(time.UnixMilli(evt.Timestamp)) > t.cfg.maxAge {
		return
	}
	t.enqueue(ctx, evt, false)
}

// enqueue hands a voice message to the worker, once: the live sync and
// catchUp can both find the same one (or an edit can repeat it). Live messages don't wait for room in
// the queue (that would hold up the sync); catchUp does.
func (t *transcriber) enqueue(ctx context.Context, evt *event.Event, wait bool) {
	target, _ := voiceMessage(evt)
	t.seenLock.Lock()
	_, dup := t.seen[target]
	t.seen[target] = time.Now()
	for evtID, at := range t.seen {
		if time.Since(at) > time.Hour {
			delete(t.seen, evtID)
		}
	}
	t.seenLock.Unlock()
	if dup {
		return
	}
	if wait {
		select {
		case t.queue <- evt:
		case <-ctx.Done():
		}
		return
	}
	select {
	case t.queue <- evt:
	default:
		logger.Warn().Stringer("event", evt.ID).Msg("Queue full, skipping voice message")
	}
}

func (t *transcriber) worker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case evt := <-t.queue:
			if err := t.process(ctx, evt); err != nil && !errors.Is(err, context.Canceled) {
				logger.Error().Err(err).Stringer("room", evt.RoomID).Stringer("event", evt.ID).Msg("Couldn't transcribe voice message")
			}
		}
	}
}

func (t *transcriber) process(ctx context.Context, evt *event.Event) error {
	start := time.Now()
	target, content := voiceMessage(evt)
	audio, err := t.download(ctx, content)
	if err != nil {
		return fmt.Errorf("downloading: %w", err)
	}
	result, err := t.whisper.transcribe(ctx, audio, audioFilename(content))
	if err != nil {
		return err
	}
	// whisper.cpp ends each speech segment with a line break, which would
	// land mid-sentence in Beeper.
	text := strings.Join(strings.Fields(result.text), " ")
	if text == "" {
		return nil
	}
	transcript := map[string]any{
		"msgtype": "com.beeper.transcription",
		"com.beeper.relates_to": map[string]any{
			"room_id":  evt.RoomID,
			"event_id": target,
			"rel_type": "com.beeper.transcription",
		},
		"com.beeper.transcription.model":    t.cfg.modelName,
		"com.beeper.transcription.language": result.language,
		"m.text":                            []map[string]any{{"body": text}},
	}
	if err = t.postTranscript(ctx, transcript); err != nil {
		return err
	}
	t.pending.add(evt.RoomID, target, transcript)
	logger.Info().Stringer("room", evt.RoomID).Stringer("event", target).Str("language", result.language).Int("chars", len(text)).Stringer("took", time.Since(start).Round(time.Millisecond)).Msg("Transcribed voice message")
	return nil
}

// postTranscript sends a transcript event (new, or one sent before again).
func (t *transcriber) postTranscript(ctx context.Context, content map[string]any) error {
	if _, err := t.client.SendMessageEvent(ctx, transcriptionsRoom, transcriptionEventType, content); err != nil {
		return fmt.Errorf("posting the transcript: %w", err)
	}
	return nil
}

func (t *transcriber) download(ctx context.Context, content *event.MessageEventContent) ([]byte, error) {
	if content.File != nil {
		uri, err := content.File.URL.Parse()
		if err != nil {
			return nil, err
		}
		data, err := t.client.DownloadBytes(ctx, uri)
		if err != nil {
			return nil, err
		}
		// Handles Beeper's FLOE file encryption as well as standard AES-CTR.
		return content.File.DecryptInPlaceReturn(data)
	}
	uri, err := content.URL.Parse()
	if err != nil {
		return nil, err
	}
	return t.client.DownloadBytes(ctx, uri)
}

// audioFilename gives Whisper backends a file name whose extension matches
// the audio, which is how they tell the format apart.
func audioFilename(content *event.MessageEventContent) string {
	mime := ""
	if content.Info != nil {
		mime = content.Info.MimeType
	}
	ext := map[string]string{
		"audio/ogg": ".ogg", "audio/opus": ".ogg", "audio/mpeg": ".mp3", "audio/mp4": ".m4a", "audio/aac": ".m4a",
		"audio/x-m4a": ".m4a", "audio/wav": ".wav", "audio/x-wav": ".wav", "audio/webm": ".webm", "audio/flac": ".flac",
	}[strings.TrimSpace(strings.Split(mime, ";")[0])]
	if ext == "" {
		ext = ".ogg" // what WhatsApp, Signal and Telegram voice notes are
	}
	return "voice" + ext
}

// fileSyncStore keeps the sync position across restarts, and when it was
// last saved, which tells catchUp how long the service was down.
type fileSyncStore struct {
	path string
	lock sync.Mutex
}

type syncState struct {
	FilterID  string `json:"filter_id"`
	NextBatch string `json:"next_batch"`
	SavedAt   int64  `json:"saved_at"` // unix ms
}

func (s *fileSyncStore) load() syncState {
	var st syncState
	if data, err := os.ReadFile(s.path); err == nil {
		_ = json.Unmarshal(data, &st)
	}
	return st
}

func (s *fileSyncStore) update(change func(*syncState)) error {
	s.lock.Lock()
	defer s.lock.Unlock()
	st := s.load()
	change(&st)
	data, err := json.Marshal(st)
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err = os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

func (s *fileSyncStore) SaveFilterID(_ context.Context, _ id.UserID, filterID string) error {
	return s.update(func(st *syncState) { st.FilterID = filterID })
}

func (s *fileSyncStore) LoadFilterID(_ context.Context, _ id.UserID) (string, error) {
	return s.load().FilterID, nil
}

func (s *fileSyncStore) SaveNextBatch(_ context.Context, _ id.UserID, token string) error {
	return s.update(func(st *syncState) { st.NextBatch, st.SavedAt = token, time.Now().UnixMilli() })
}

func (s *fileSyncStore) LoadNextBatch(_ context.Context, _ id.UserID) (string, error) {
	return s.load().NextBatch, nil
}
