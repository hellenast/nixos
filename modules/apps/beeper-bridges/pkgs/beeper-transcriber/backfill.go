package main

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// scanResult is what scan found in the account's chats over a period.
type scanResult struct {
	chats         int
	voice         []*event.Event                // voice messages (or edits into one) to transcribe, oldest first
	transcripts   map[id.EventID]map[string]any // latest transcript of each voice message that has one
	skipped       map[string]int                // other audio messages, by skipReason
	undecryptable int
}

// scan goes through every chat's messages since `since`, four chats at a
// time. It only reaches messages whose encryption keys this device
// received, i.e. from after `login`.
func (t *transcriber) scan(ctx context.Context, since time.Time) (*scanResult, error) {
	res := &scanResult{transcripts: t.transcriptsSince(ctx, since), skipped: map[string]int{}}
	rooms, err := t.client.JoinedRooms(ctx)
	if err != nil {
		return nil, fmt.Errorf("listing chats: %w", err)
	}
	res.chats = len(rooms.JoinedRooms)
	var (
		lock  sync.Mutex
		wg    sync.WaitGroup
		slots = make(chan struct{}, 4)
	)
	for _, roomID := range rooms.JoinedRooms {
		if roomID == transcriptionsRoom {
			continue
		}
		wg.Add(1)
		slots <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-slots }()
			evts, failed, err := t.roomMessagesSince(ctx, roomID, since, event.EventMessage)
			if err != nil {
				logger.Warn().Err(err).Stringer("room", roomID).Msg("Couldn't read chat history")
			}
			lock.Lock()
			defer lock.Unlock()
			res.undecryptable += failed
			for _, evt := range evts {
				switch reason := t.skipReason(evt); reason {
				case "":
					res.voice = append(res.voice, evt)
				case notAudio:
				default:
					res.skipped[reason]++
				}
			}
		}()
	}
	wg.Wait()
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	sort.Slice(res.voice, func(i, j int) bool { return res.voice[i].Timestamp < res.voice[j].Timestamp })
	// One per message: a voice message and an edit of it are the same one.
	seen := map[id.EventID]bool{}
	unique := res.voice[:0]
	for _, evt := range res.voice {
		if target, _ := voiceMessage(evt); !seen[target] {
			seen[target] = true
			unique = append(unique, evt)
		}
	}
	res.voice = unique
	return res, nil
}

// catchUp transcribes what came in while the service was down, since the
// last sync before that (run calls it at startup).
func (t *transcriber) catchUp(ctx context.Context, since time.Time) {
	if oldest := time.Now().Add(-7 * 24 * time.Hour); since.Before(oldest) {
		since = oldest
	}
	logger.Info().Time("since", since).Msg("Catching up on voice messages from while the service was down")
	res, err := t.scan(ctx, since)
	if err != nil {
		logger.Error().Err(err).Msg("Couldn't catch up")
		return
	}
	queued := 0
	for _, evt := range res.voice {
		if target, _ := voiceMessage(evt); res.transcripts[target] == nil {
			t.enqueue(ctx, evt, true)
			queued++
		}
	}
	logger.Info().Int("voice_messages", len(res.voice)).Int("queued", queued).Msg("Caught up")
}

// backfill goes over the last period's voice messages: it transcribes the
// ones without a transcript, and sends the existing transcripts of the
// others again, for the Beeper apps that dropped them (see resend.go).
//
// It uses the same device as `run`, so the service shouldn't be running at
// the same time (beeper-transcriber-backfill stops it).
func backfill(ctx context.Context, cfg config, period string) error {
	window, err := parsePeriod(period)
	if err != nil {
		return err
	}
	since := time.Now().Add(-window)
	t, helper, err := connect(ctx, cfg)
	if err != nil {
		return err
	}
	defer helper.Close()

	fmt.Printf("Looking through the chats for voice messages since %s...\n", since.Format(time.DateTime))
	res, err := t.scan(ctx, since)
	if err != nil {
		return err
	}
	var missing, again []*event.Event
	for _, evt := range res.voice {
		if target, _ := voiceMessage(evt); res.transcripts[target] != nil {
			again = append(again, evt)
		} else {
			missing = append(missing, evt)
		}
	}
	fmt.Printf("%d voice messages in %d chats:\n", len(res.voice), res.chats)
	fmt.Printf("  %d with a transcript: sending it again (Beeper drops transcripts that reach it before the voice message)\n", len(again))
	fmt.Printf("  %d without one: transcribing\n", len(missing))
	for reason, n := range res.skipped {
		fmt.Printf("Not transcribed, %s: %d\n", reason, n)
	}
	if res.undecryptable > 0 {
		fmt.Printf("%d messages unreadable: from before the transcriber's login, or encryption keys it never got.\n", res.undecryptable)
	}

	resendFailures := 0
	for _, evt := range again {
		target, _ := voiceMessage(evt)
		if err = t.postTranscript(ctx, res.transcripts[target]); err != nil {
			if errors.Is(err, context.Canceled) {
				return err
			}
			resendFailures++
			logger.Error().Err(err).Stringer("event", target).Msg("Couldn't send transcript again")
		}
	}
	failures := 0
	for i, evt := range missing {
		if err = t.process(ctx, evt); err != nil {
			if errors.Is(err, context.Canceled) {
				return err
			}
			failures++
			logger.Error().Err(err).Stringer("room", evt.RoomID).Stringer("event", evt.ID).Msg("Couldn't transcribe voice message")
		}
		fmt.Printf("\r%d/%d", i+1, len(missing))
	}
	if len(missing) > 0 {
		fmt.Println()
	}
	fmt.Printf("Done: %d transcribed (%d failed), %d sent again (%d failed).\n", len(missing)-failures, failures, len(again)-resendFailures, resendFailures)
	return nil
}

// parsePeriod accepts Go durations (12h, 90m) and days (2d).
func parsePeriod(s string) (time.Duration, error) {
	if days, ok := strings.CutSuffix(s, "d"); ok {
		if n, err := strconv.Atoi(days); err == nil && n > 0 {
			return time.Duration(n) * 24 * time.Hour, nil
		}
	} else if d, err := time.ParseDuration(s); err == nil && d > 0 {
		return d, nil
	}
	return 0, fmt.Errorf("invalid period %q (e.g. 2d, 12h)", s)
}

// roomMessagesSince pages a chat's history of evtType events back to
// `since`, decrypting what it can. It returns how many encrypted events it
// couldn't read.
func (t *transcriber) roomMessagesSince(ctx context.Context, roomID id.RoomID, since time.Time, evtType event.Type) (evts []*event.Event, undecryptable int, err error) {
	filter := &mautrix.FilterPart{Types: []event.Type{evtType, event.EventEncrypted}}
	from := ""
	for {
		resp, err := t.client.Messages(ctx, roomID, from, "", mautrix.DirectionBackward, filter, 100)
		if err != nil {
			return evts, undecryptable, err
		}
		for _, evt := range resp.Chunk {
			if time.UnixMilli(evt.Timestamp).Before(since) {
				return evts, undecryptable, nil
			}
			if evt = t.readEvent(ctx, roomID, evt); evt == nil {
				undecryptable++
				continue
			}
			evts = append(evts, evt)
		}
		if resp.End == "" || len(resp.Chunk) == 0 {
			return evts, undecryptable, nil
		}
		from = resp.End
	}
}

// transcriptsSince collects the transcripts sent since `since`, ours or
// Beeper's own, from the transcriptions room: the latest one of each voice
// message. Transcripts come after their messages, so going back to `since`
// covers every message in the window. If the room can't be read, the scan
// carries on: a message transcribed twice just shows the newer transcript.
func (t *transcriber) transcriptsSince(ctx context.Context, since time.Time) map[id.EventID]map[string]any {
	found := map[id.EventID]map[string]any{}
	evts, _, err := t.roomMessagesSince(ctx, transcriptionsRoom, since, transcriptionEventType)
	if err != nil {
		logger.Warn().Err(err).Msg("Couldn't read existing transcripts; some messages may get a second one")
	}
	// Newest first, so the first one seen for a message is its latest.
	for _, evt := range evts {
		if rel, ok := evt.Content.Raw["com.beeper.relates_to"].(map[string]any); ok {
			if evtID, ok := rel["event_id"].(string); ok {
				if _, seen := found[id.EventID(evtID)]; !seen {
					found[id.EventID(evtID)] = evt.Content.Raw
				}
			}
		}
	}
	return found
}

// readEvent parses an event from /messages and decrypts it if needed; nil
// means it couldn't be read.
func (t *transcriber) readEvent(ctx context.Context, roomID id.RoomID, evt *event.Event) *event.Event {
	evt.RoomID = roomID
	// Custom types like com.beeper.transcription have no parsed form; their
	// content stays readable through Content.Raw.
	err := evt.Content.ParseRaw(evt.Type)
	if err != nil && !errors.Is(err, event.ErrContentAlreadyParsed) && !errors.Is(err, event.ErrUnsupportedContentType) {
		return nil
	}
	if evt.Type != event.EventEncrypted {
		return evt
	}
	decrypted, err := t.client.Crypto.Decrypt(ctx, evt)
	if err != nil {
		return nil
	}
	return decrypted
}
