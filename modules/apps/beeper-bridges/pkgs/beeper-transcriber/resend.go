package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// Beeper's apps drop a transcript for good when it reaches them before the
// voice message itself: they handle all chats of a sync at once, so a
// transcript that arrives in the same sync as its voice message (an app
// catching up after being closed, a phone opened hours later) finds no
// message to attach to ("is not synced yet, dropping" in Beeper's logs).
//
// So transcripts are sent again once the account reads their chat: a read
// receipt means the reading app has the voice message by now, and the
// repeated transcript reaches it in a later sync, where it attaches. Each
// transcript is repeated a few times at most, only for a read that came
// after its last sending, and is forgotten after a few days.
const (
	maxResends     = 3
	resendSpacing  = 10 * time.Minute
	resendLifetime = 3 * 24 * time.Hour
)

type pendingTranscript struct {
	VoiceEvent id.EventID     `json:"voice_event"`
	Content    map[string]any `json:"content"`
	LastSent   int64          `json:"last_sent"` // unix ms
	FirstSent  int64          `json:"first_sent"`
	Resends    int            `json:"resends"`
}

// pendingStore keeps the transcripts that may still need repeating, by chat,
// in pending.json in the state directory so a restart doesn't lose them.
type pendingStore struct {
	path  string
	lock  sync.Mutex
	rooms map[id.RoomID][]*pendingTranscript
}

func loadPendingStore(cfg config) *pendingStore {
	s := &pendingStore{path: filepath.Join(cfg.stateDir, "pending.json"), rooms: map[id.RoomID][]*pendingTranscript{}}
	if data, err := os.ReadFile(s.path); err == nil {
		_ = json.Unmarshal(data, &s.rooms)
	}
	return s
}

// saveLocked writes the store; the caller holds the lock.
func (s *pendingStore) saveLocked() {
	data, err := json.Marshal(s.rooms)
	if err == nil {
		tmp := s.path + ".tmp"
		if err = os.WriteFile(tmp, data, 0o600); err == nil {
			err = os.Rename(tmp, s.path)
		}
	}
	if err != nil {
		logger.Warn().Err(err).Msg("Couldn't save pending transcripts")
	}
}

func (s *pendingStore) add(roomID id.RoomID, voiceEvent id.EventID, content map[string]any) {
	s.lock.Lock()
	defer s.lock.Unlock()
	now := time.Now()
	for room, items := range s.rooms {
		var keep []*pendingTranscript
		for _, p := range items {
			if now.Sub(time.UnixMilli(p.FirstSent)) <= resendLifetime {
				keep = append(keep, p)
			}
		}
		if len(keep) == 0 {
			delete(s.rooms, room)
		} else {
			s.rooms[room] = keep
		}
	}
	s.rooms[roomID] = append(s.rooms[roomID], &pendingTranscript{VoiceEvent: voiceEvent, Content: content, LastSent: now.UnixMilli(), FirstSent: now.UnixMilli()})
	s.saveLocked()
}

// due picks the chat's transcripts to send again after a read at readAt,
// marking them as sent, and drops the ones that are done with.
func (s *pendingStore) due(roomID id.RoomID, readAt time.Time) []*pendingTranscript {
	s.lock.Lock()
	defer s.lock.Unlock()
	items := s.rooms[roomID]
	if len(items) == 0 {
		return nil
	}
	now := time.Now()
	var keep, due []*pendingTranscript
	for _, p := range items {
		if now.Sub(time.UnixMilli(p.FirstSent)) > resendLifetime {
			continue
		}
		lastSent := time.UnixMilli(p.LastSent)
		if readAt.After(lastSent.Add(2*time.Second)) && now.Sub(lastSent) > resendSpacing {
			p.Resends++
			p.LastSent = now.UnixMilli()
			due = append(due, p)
		}
		if p.Resends < maxResends {
			keep = append(keep, p)
		}
	}
	if len(keep) == 0 {
		delete(s.rooms, roomID)
	} else {
		s.rooms[roomID] = keep
	}
	s.saveLocked()
	return due
}

// onReceipt sends a chat's recent transcripts again when the account reads it.
func (t *transcriber) onReceipt(ctx context.Context, evt *event.Event) {
	receipts := evt.Content.AsReceipt()
	if receipts == nil {
		return
	}
	var readAt time.Time
	for _, byType := range *receipts {
		for _, receiptType := range []event.ReceiptType{event.ReceiptTypeRead, event.ReceiptTypeReadPrivate} {
			if r, ok := byType[receiptType][t.client.UserID]; ok && r.Timestamp.After(readAt) {
				readAt = r.Timestamp
			}
		}
	}
	if readAt.IsZero() {
		return
	}
	due := t.pending.due(evt.RoomID, readAt)
	if len(due) == 0 {
		return
	}
	go func() {
		for _, p := range due {
			if err := t.postTranscript(ctx, p.Content); err != nil {
				logger.Warn().Err(err).Stringer("event", p.VoiceEvent).Msg("Couldn't send transcript again")
			}
		}
		logger.Info().Stringer("room", evt.RoomID).Int("count", len(due)).Msg("Sent transcripts again after the chat was read")
	}()
}
