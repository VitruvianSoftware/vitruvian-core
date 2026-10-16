# Courier Milestone 1: prove the local store with WhatsApp

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a Go engine where the stock mautrix-whatsapp bridge runs against our own local store instead of a Matrix server. The test command line can link WhatsApp, show incoming messages, and send replies.

**Architecture:** mautrix-go's bridge framework (`bridgev2`) talks to "Matrix" only through two interfaces, `MatrixConnector` and `MatrixAPI`. We implement both on top of a SQLite store (`courier.db`) and a content-addressed media folder. A fake network connector proves the glue in CI. A small CLI drives the real WhatsApp connector for the by-hand milestone check.

**Tech Stack:** Go 1.26 (repo `go.work`); maunium.net/go/mautrix v0.31.0 (`bridgev2`); go.mau.fi/mautrix-whatsapp v0.2609.0; go.mau.fi/util v0.10.1 (`dbutil`, cgo SQLite via the `litestream` driver); zerolog; github.com/mdp/qrterminal/v3; Bazel rules_go and gazelle.

**Spec:** `docs/superpowers/specs/2026-10-15-courier-iteration-1-design.md`. This plan covers milestone 1 in §7 only. Milestones 2–6 get their own plans after this one's result.

## Global Constraints

- Module path `github.com/VitruvianSoftware/courier/engine`, at `apps/desktop/courier/engine`, listed in the root `go.work`.
- Pinned versions: `maunium.net/go/mautrix v0.31.0`, `go.mau.fi/mautrix-whatsapp v0.2609.0`, `go.mau.fi/util v0.10.1`. Do not float them.
- SQLite goes through cgo (`github.com/mattn/go-sqlite3`, registered by `go.mau.fi/util/dbutil/litestream` as driver name `sqlite3-fk-wal`). The Bazel LLVM toolchain is pinned to the macOS 26 SDK (`MODULE.bazel`, `llvm.sysroot`); do not change that.
- The local server name is `courier.local`. The local user is `@me:courier.local`.
- Data lives under `~/Library/Application Support/Courier/`: `courier.db`, `bridges/<network>.db` and `media/`. Tests use `t.TempDir()`.
- No real network accounts in CI. Real WhatsApp is touched only in Task 9, by hand.
- Never commit session databases, QR data, phone numbers or message content.
- The whole `apps/desktop/courier/` tree is AGPL-3.0 because it embeds AGPL bridges (spec §8).
- After adding or moving any `.go` file, run `bazel run //:gazelle`. After changing Go deps, run `bazel mod tidy` so `use_repo` stays in step.

## Review Focus

1. **The same remote message delivered twice** (reconnect, or a backfill overlapping live sync) must be stored once, not duplicated. Covered in Task 2 (`TestInsertEventIsIdempotent`) and Task 4 (deterministic IDs from `MessageMeta`).
2. **The engine restarts after linking.** The WhatsApp login must resume from `bridges/whatsapp.db` without re-linking. Covered in Task 7 (`TestHostRestartReloadsLogin`).
3. **Bridges send concurrently** from many portal goroutines. SQLite must not return "database is locked". Covered in Task 2 (`TestConcurrentInsertsDoNotLock`).
4. **Media referenced but missing on disk** (cleared storage, partial write) must give a clear error, not a panic or a zero-byte file. Covered in Task 3 (`TestOpenMissingMediaErrors`).
5. **Non-ASCII content** (emoji, Vietnamese diacritics, very long text) must round-trip byte-exactly through store and API. Covered in Task 4 (`TestSendMessageRoundTripsUnicode`).

---

## File structure

```
apps/desktop/courier/
  LICENSE                         AGPL-3.0 text
  engine/
    go.mod / go.sum
    BUILD.bazel                   gazelle prefix + package defaults
    internal/sqlite/open.go       opens a dbutil database on the cgo driver
    internal/store/schema.sql     courier.db schema (embedded)
    internal/store/store.go       rooms, members, state, events, receipts, bridge state, change feed
    internal/media/media.go       content-addressed media files
    internal/ids/ids.go           ghost MXIDs, deterministic room/event IDs, content URIs
    internal/localmatrix/connector.go   bridgev2.MatrixConnector
    internal/localmatrix/intent.go      bridgev2.MatrixAPI
    internal/fakenet/fakenet.go   in-memory NetworkConnector for tests
    internal/host/host.go         runs one network connector with its own DB, config and permissions
    cmd/courier-engine-cli/main.go  link / chats / tail / send
  engine/docs/m1-result.md        Task 9 outcome and kill-criterion decision
```

---

### Task 1: Engine module, licence and a cgo SQLite smoke test under Bazel

**Files:**
- Create: `apps/desktop/courier/LICENSE`, `apps/desktop/courier/engine/go.mod`, `apps/desktop/courier/engine/BUILD.bazel`, `apps/desktop/courier/engine/internal/sqlite/open.go`
- Modify: `go.work` (add `./apps/desktop/courier/engine`)
- Test: `apps/desktop/courier/engine/internal/sqlite/open_test.go`

**Interfaces:**
- Produces: `sqlite.Open(path string) (*dbutil.Database, error)`. It opens the file with the `sqlite3-fk-wal` driver, WAL mode, `busy_timeout=5000` and foreign keys on.

- [ ] **Step 1: Add the licence and module**

```bash
curl -sS https://www.gnu.org/licenses/agpl-3.0.txt -o apps/desktop/courier/LICENSE
mkdir -p apps/desktop/courier/engine/internal/sqlite
cd apps/desktop/courier/engine
go mod init github.com/VitruvianSoftware/courier/engine
go get maunium.net/go/mautrix@v0.31.0 go.mau.fi/util@v0.10.1 github.com/mattn/go-sqlite3 github.com/rs/zerolog github.com/stretchr/testify
cd - && go work use ./apps/desktop/courier/engine
```

`apps/desktop/courier/engine/BUILD.bazel`:

```python
# gazelle:prefix github.com/VitruvianSoftware/courier/engine
package(default_visibility = ["//apps/desktop/courier:__subpackages__"])
```

- [ ] **Step 2: Write the failing test**

`internal/sqlite/open_test.go`:

```go
package sqlite

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOpenCreatesWALDatabase(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "x.db"))
	require.NoError(t, err)
	defer db.Close()
	var mode string
	require.NoError(t, db.QueryRow(context.Background(), "PRAGMA journal_mode").Scan(&mode))
	require.Equal(t, "wal", mode)
	var timeout int
	require.NoError(t, db.QueryRow(context.Background(), "PRAGMA busy_timeout").Scan(&timeout))
	require.Equal(t, 5000, timeout)
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd apps/desktop/courier/engine && go test ./internal/sqlite/`
Expected: FAIL with `undefined: Open`.

- [ ] **Step 4: Implement**

`internal/sqlite/open.go`:

```go
// Package sqlite opens courier's SQLite files on the cgo driver the bridge stack expects.
package sqlite

import (
	"fmt"

	"go.mau.fi/util/dbutil"
	_ "go.mau.fi/util/dbutil/litestream" // registers the cgo sqlite3 drivers
)

// Open opens (creating if needed) a SQLite database in WAL mode with a 5 s busy timeout.
func Open(path string) (*dbutil.Database, error) {
	uri := fmt.Sprintf("file:%s?_txlock=immediate&_busy_timeout=5000&_journal_mode=WAL&_foreign_keys=on", path)
	db, err := dbutil.NewWithDialect(uri, "sqlite3-fk-wal")
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	return db, nil
}
```

- [ ] **Step 5: Run the test under go, then under Bazel**

Run: `go test ./internal/sqlite/` then `bazel run //:gazelle && bazel mod tidy && bazel test //apps/desktop/courier/engine/...`
Expected: PASS in both. If Bazel fails linking cgo with "unknown architecture", stop and report. That is the SDK/toolchain issue described in `MODULE.bazel`, not something to work around here.

- [ ] **Step 6: Commit**

```bash
git add go.work apps/desktop/courier MODULE.bazel
git commit -m "feat(courier): engine module with cgo SQLite under Bazel"
```

---

### Task 2: The local store (`courier.db`)

**Files:**
- Create: `internal/store/schema.sql`, `internal/store/store.go`
- Test: `internal/store/store_test.go`

**Interfaces:**
- Consumes: `sqlite.Open`.
- Produces (package `store`):

```go
type Room struct{ ID, Network, Name, Topic, AvatarURI string; IsDirect bool; CreatedAt time.Time }
type Event struct {
	RoomID, EventID, Sender, Type string
	StateKey *string
	Content  json.RawMessage
	TS       time.Time
	Status   string // "", "pending", "sent", "failed"
	StatusReason string
}
type Change struct{ Kind, RoomID, EventID string } // Kind: "room", "event", "status", "member", "read", "bridge"
func Open(path string) (*Store, error)
func (s *Store) Close() error
func (s *Store) UpsertRoom(ctx context.Context, r Room) error
func (s *Store) GetRoom(ctx context.Context, roomID string) (Room, bool, error)
func (s *Store) ListRooms(ctx context.Context) ([]Room, error)
func (s *Store) DeleteRoom(ctx context.Context, roomID string) error
func (s *Store) SetMember(ctx context.Context, roomID, userID string, content json.RawMessage) error
func (s *Store) Members(ctx context.Context, roomID string) (map[string]json.RawMessage, error)
func (s *Store) SetState(ctx context.Context, roomID, evType, stateKey string, content json.RawMessage) error
func (s *Store) GetState(ctx context.Context, roomID, evType, stateKey string) (json.RawMessage, bool, error)
func (s *Store) InsertEvent(ctx context.Context, e Event) (inserted bool, err error) // idempotent on EventID
func (s *Store) GetEvent(ctx context.Context, eventID string) (Event, bool, error)
func (s *Store) Events(ctx context.Context, roomID string, limit int) ([]Event, error) // newest first
func (s *Store) SetStatus(ctx context.Context, eventID, status, reason string) error
func (s *Store) SetRead(ctx context.Context, roomID, eventID string, ts time.Time) error
func (s *Store) SetBridgeState(ctx context.Context, network string, state json.RawMessage) error
func (s *Store) BridgeState(ctx context.Context, network string) (json.RawMessage, bool, error)
func (s *Store) Subscribe() (<-chan Change, func())
```

- [ ] **Step 1: Write the failing tests**

`internal/store/store_test.go`:

```go
package store

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func open(t *testing.T) *Store {
	s, err := Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return s
}

func TestRoomRoundTrip(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp", Name: "Mum", IsDirect: true}))
	r, ok, err := s.GetRoom(ctx, "!r:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Mum", r.Name)
	require.True(t, r.IsDirect)
}

func TestInsertEventIsIdempotent(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	e := Event{RoomID: "!r:courier.local", EventID: "$a", Sender: "@x:courier.local", Type: "m.room.message",
		Content: json.RawMessage(`{"body":"hi"}`), TS: time.Unix(10, 0)}
	ins, err := s.InsertEvent(ctx, e)
	require.NoError(t, err)
	require.True(t, ins)
	ins, err = s.InsertEvent(ctx, e)
	require.NoError(t, err)
	require.False(t, ins, "second delivery of the same event must not insert")
	evs, err := s.Events(ctx, "!r:courier.local", 10)
	require.NoError(t, err)
	require.Len(t, evs, 1)
}

func TestEventsNewestFirstAndStatus(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	for i := 1; i <= 3; i++ {
		_, err := s.InsertEvent(ctx, Event{RoomID: "!r:courier.local", EventID: fmt.Sprintf("$%d", i), Sender: "@x:courier.local",
			Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Unix(int64(i), 0), Status: "pending"})
		require.NoError(t, err)
	}
	require.NoError(t, s.SetStatus(ctx, "$3", "failed", "network down"))
	evs, err := s.Events(ctx, "!r:courier.local", 2)
	require.NoError(t, err)
	require.Equal(t, []string{"$3", "$2"}, []string{evs[0].EventID, evs[1].EventID})
	require.Equal(t, "failed", evs[0].Status)
	require.Equal(t, "network down", evs[0].StatusReason)
}

func TestStateAndMembers(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	require.NoError(t, s.SetState(ctx, "!r:courier.local", "m.room.power_levels", "", json.RawMessage(`{"users_default":0}`)))
	got, ok, err := s.GetState(ctx, "!r:courier.local", "m.room.power_levels", "")
	require.NoError(t, err)
	require.True(t, ok)
	require.JSONEq(t, `{"users_default":0}`, string(got))
	require.NoError(t, s.SetMember(ctx, "!r:courier.local", "@a:courier.local", json.RawMessage(`{"membership":"join"}`)))
	m, err := s.Members(ctx, "!r:courier.local")
	require.NoError(t, err)
	require.Contains(t, m, "@a:courier.local")
}

func TestSubscribeReceivesChanges(t *testing.T) {
	s, ctx := open(t), context.Background()
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	select {
	case c := <-ch:
		require.Equal(t, Change{Kind: "room", RoomID: "!r:courier.local"}, c)
	case <-time.After(time.Second):
		t.Fatal("no change delivered")
	}
}

func TestConcurrentInsertsDoNotLock(t *testing.T) {
	s, ctx := open(t), context.Background()
	for r := 0; r < 8; r++ {
		require.NoError(t, s.UpsertRoom(ctx, Room{ID: fmt.Sprintf("!r%d:courier.local", r), Network: "whatsapp"}))
	}
	var wg sync.WaitGroup
	errs := make(chan error, 8*50)
	for r := 0; r < 8; r++ {
		wg.Add(1)
		go func(r int) {
			defer wg.Done()
			for i := 0; i < 50; i++ {
				_, err := s.InsertEvent(ctx, Event{RoomID: fmt.Sprintf("!r%d:courier.local", r), EventID: fmt.Sprintf("$%d-%d", r, i),
					Sender: "@x:courier.local", Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Now()})
				errs <- err
			}
		}(r)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		require.NoError(t, err)
	}
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `go test ./internal/store/`
Expected: FAIL with `undefined: Open`.

- [ ] **Step 3: Implement the schema and store**

`internal/store/schema.sql`:

```sql
CREATE TABLE IF NOT EXISTS rooms (
  room_id TEXT PRIMARY KEY, network TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', topic TEXT NOT NULL DEFAULT '',
  avatar_uri TEXT NOT NULL DEFAULT '', is_direct INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS members (
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, user_id TEXT NOT NULL, content TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE TABLE IF NOT EXISTS state (
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, type TEXT NOT NULL, state_key TEXT NOT NULL, content TEXT NOT NULL,
  PRIMARY KEY (room_id, type, state_key)
);
CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY, room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, sender TEXT NOT NULL,
  type TEXT NOT NULL, state_key TEXT, content TEXT NOT NULL, ts INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT '', status_reason TEXT NOT NULL DEFAULT '', seq INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS events_room_seq ON events(room_id, seq DESC);
CREATE TABLE IF NOT EXISTS reads (room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE, event_id TEXT NOT NULL, ts INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS bridge_state (network TEXT PRIMARY KEY, state TEXT NOT NULL);
```

`internal/store/store.go`:

```go
// Package store is courier.db: the single source of truth that stands in for a Matrix server.
package store

import (
	"context"
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"go.mau.fi/util/dbutil"

	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
)

//go:embed schema.sql
var schema string

type Room struct {
	ID, Network, Name, Topic, AvatarURI string
	IsDirect                           bool
	CreatedAt                          time.Time
}

type Event struct {
	RoomID, EventID, Sender, Type string
	StateKey                      *string
	Content                       json.RawMessage
	TS                            time.Time
	Status, StatusReason          string
}

type Change struct{ Kind, RoomID, EventID string }

type Store struct {
	db   *dbutil.Database
	seq  int64
	mu   sync.Mutex // guards seq and subs
	subs map[chan Change]struct{}
}

func Open(path string) (*Store, error) {
	db, err := sqlite.Open(path)
	if err != nil {
		return nil, err
	}
	if _, err = db.Exec(context.Background(), schema); err != nil {
		db.Close()
		return nil, err
	}
	s := &Store{db: db, subs: map[chan Change]struct{}{}}
	if err = db.QueryRow(context.Background(), "SELECT COALESCE(MAX(seq),0) FROM events").Scan(&s.seq); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) publish(c Change) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for ch := range s.subs {
		select {
		case ch <- c:
		default: // slow subscriber: drop; it re-reads state on its next query
		}
	}
}

// Subscribe returns a buffered change feed and a cancel function.
func (s *Store) Subscribe() (<-chan Change, func()) {
	ch := make(chan Change, 256)
	s.mu.Lock()
	s.subs[ch] = struct{}{}
	s.mu.Unlock()
	return ch, func() {
		s.mu.Lock()
		delete(s.subs, ch)
		s.mu.Unlock()
	}
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

func (s *Store) UpsertRoom(ctx context.Context, r Room) error {
	if r.CreatedAt.IsZero() {
		r.CreatedAt = time.Now()
	}
	_, err := s.db.Exec(ctx, `INSERT INTO rooms (room_id, network, name, topic, avatar_uri, is_direct, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT(room_id) DO UPDATE SET name=excluded.name, topic=excluded.topic, avatar_uri=excluded.avatar_uri, is_direct=excluded.is_direct`,
		r.ID, r.Network, r.Name, r.Topic, r.AvatarURI, b2i(r.IsDirect), r.CreatedAt.UnixMilli())
	if err == nil {
		s.publish(Change{Kind: "room", RoomID: r.ID})
	}
	return err
}

func scanRoom(row dbutil.Scannable) (Room, error) {
	var r Room
	var direct int
	var created int64
	err := row.Scan(&r.ID, &r.Network, &r.Name, &r.Topic, &r.AvatarURI, &direct, &created)
	r.IsDirect, r.CreatedAt = direct == 1, time.UnixMilli(created)
	return r, err
}

const roomCols = "room_id, network, name, topic, avatar_uri, is_direct, created_at"

func (s *Store) GetRoom(ctx context.Context, roomID string) (Room, bool, error) {
	r, err := scanRoom(s.db.QueryRow(ctx, "SELECT "+roomCols+" FROM rooms WHERE room_id=$1", roomID))
	if errors.Is(err, sql.ErrNoRows) {
		return Room{}, false, nil
	}
	return r, err == nil, err
}

func (s *Store) ListRooms(ctx context.Context) ([]Room, error) {
	rows, err := s.db.Query(ctx, "SELECT "+roomCols+" FROM rooms ORDER BY created_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Room
	for rows.Next() {
		r, err := scanRoom(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Store) DeleteRoom(ctx context.Context, roomID string) error {
	_, err := s.db.Exec(ctx, "DELETE FROM rooms WHERE room_id=$1", roomID)
	if err == nil {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return err
}

func (s *Store) SetMember(ctx context.Context, roomID, userID string, content json.RawMessage) error {
	_, err := s.db.Exec(ctx, `INSERT INTO members (room_id, user_id, content) VALUES ($1,$2,$3)
		ON CONFLICT(room_id, user_id) DO UPDATE SET content=excluded.content`, roomID, userID, string(content))
	if err == nil {
		s.publish(Change{Kind: "member", RoomID: roomID})
	}
	return err
}

func (s *Store) Members(ctx context.Context, roomID string) (map[string]json.RawMessage, error) {
	rows, err := s.db.Query(ctx, "SELECT user_id, content FROM members WHERE room_id=$1", roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]json.RawMessage{}
	for rows.Next() {
		var u, c string
		if err := rows.Scan(&u, &c); err != nil {
			return nil, err
		}
		out[u] = json.RawMessage(c)
	}
	return out, rows.Err()
}

func (s *Store) SetState(ctx context.Context, roomID, evType, stateKey string, content json.RawMessage) error {
	_, err := s.db.Exec(ctx, `INSERT INTO state (room_id, type, state_key, content) VALUES ($1,$2,$3,$4)
		ON CONFLICT(room_id, type, state_key) DO UPDATE SET content=excluded.content`, roomID, evType, stateKey, string(content))
	return err
}

func (s *Store) GetState(ctx context.Context, roomID, evType, stateKey string) (json.RawMessage, bool, error) {
	var c string
	err := s.db.QueryRow(ctx, "SELECT content FROM state WHERE room_id=$1 AND type=$2 AND state_key=$3", roomID, evType, stateKey).Scan(&c)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, nil
	}
	return json.RawMessage(c), err == nil, err
}

func (s *Store) InsertEvent(ctx context.Context, e Event) (bool, error) {
	s.mu.Lock()
	s.seq++
	seq := s.seq
	s.mu.Unlock()
	res, err := s.db.Exec(ctx, `INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(event_id) DO NOTHING`,
		e.EventID, e.RoomID, e.Sender, e.Type, e.StateKey, string(e.Content), e.TS.UnixMilli(), e.Status, e.StatusReason, seq)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	if n == 1 {
		s.publish(Change{Kind: "event", RoomID: e.RoomID, EventID: e.EventID})
	}
	return n == 1, nil
}

const eventCols = "room_id, event_id, sender, type, state_key, content, ts, status, status_reason"

func scanEvent(row dbutil.Scannable) (Event, error) {
	var e Event
	var c string
	var ts int64
	err := row.Scan(&e.RoomID, &e.EventID, &e.Sender, &e.Type, &e.StateKey, &c, &ts, &e.Status, &e.StatusReason)
	e.Content, e.TS = json.RawMessage(c), time.UnixMilli(ts)
	return e, err
}

func (s *Store) GetEvent(ctx context.Context, eventID string) (Event, bool, error) {
	e, err := scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id=$1", eventID))
	if errors.Is(err, sql.ErrNoRows) {
		return Event{}, false, nil
	}
	return e, err == nil, err
}

func (s *Store) Events(ctx context.Context, roomID string, limit int) ([]Event, error) {
	rows, err := s.db.Query(ctx, "SELECT "+eventCols+" FROM events WHERE room_id=$1 ORDER BY seq DESC LIMIT $2", roomID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		e, err := scanEvent(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) SetStatus(ctx context.Context, eventID, status, reason string) error {
	var roomID string
	err := s.db.QueryRow(ctx, "UPDATE events SET status=$2, status_reason=$3 WHERE event_id=$1 RETURNING room_id", eventID, status, reason).Scan(&roomID)
	if err == nil {
		s.publish(Change{Kind: "status", RoomID: roomID, EventID: eventID})
	}
	return err
}

func (s *Store) SetRead(ctx context.Context, roomID, eventID string, ts time.Time) error {
	_, err := s.db.Exec(ctx, `INSERT INTO reads (room_id, event_id, ts) VALUES ($1,$2,$3)
		ON CONFLICT(room_id) DO UPDATE SET event_id=excluded.event_id, ts=excluded.ts`, roomID, eventID, ts.UnixMilli())
	if err == nil {
		s.publish(Change{Kind: "read", RoomID: roomID, EventID: eventID})
	}
	return err
}

func (s *Store) SetBridgeState(ctx context.Context, network string, state json.RawMessage) error {
	_, err := s.db.Exec(ctx, `INSERT INTO bridge_state (network, state) VALUES ($1,$2)
		ON CONFLICT(network) DO UPDATE SET state=excluded.state`, network, string(state))
	if err == nil {
		s.publish(Change{Kind: "bridge", RoomID: network})
	}
	return err
}

func (s *Store) BridgeState(ctx context.Context, network string) (json.RawMessage, bool, error) {
	var c string
	err := s.db.QueryRow(ctx, "SELECT state FROM bridge_state WHERE network=$1", network).Scan(&c)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, nil
	}
	return json.RawMessage(c), err == nil, err
}
```

- [ ] **Step 4: Run the tests**

Run: `go test -race ./internal/store/`
Expected: PASS, including `TestConcurrentInsertsDoNotLock` with no "database is locked".

- [ ] **Step 5: Commit**

```bash
bazel run //:gazelle
git add apps/desktop/courier/engine
git commit -m "feat(courier): local store for rooms, events, state and status"
```

---

### Task 3: IDs and media

**Files:**
- Create: `internal/ids/ids.go`, `internal/media/media.go`
- Test: `internal/ids/ids_test.go`, `internal/media/media_test.go`

**Interfaces:**
- Produces (package `ids`):

```go
const ServerName = "courier.local"
const Me id.UserID = "@me:courier.local"
func GhostMXID(network string, uid networkid.UserID) id.UserID
func ParseGhostMXID(network string, mxid id.UserID) (networkid.UserID, bool)
func RoomID(network string, key networkid.PortalKey) id.RoomID
func EventID(roomID id.RoomID, key networkid.PortalKey, msg networkid.MessageID, part networkid.PartID) id.EventID
func ReactionEventID(roomID id.RoomID, msg networkid.MessageID, part networkid.PartID, sender networkid.UserID, emoji networkid.EmojiID) id.EventID
func RandomEventID() id.EventID
func ContentURI(hash string) id.ContentURIString
func ParseContentURI(uri id.ContentURIString) (hash string, ok bool)
```

- Produces (package `media`):

```go
type Store struct{ Dir string }
var ErrMissing = errors.New("media file missing")
func (m *Store) Put(data []byte) (hash string, err error)
func (m *Store) PutStream(write func(io.Writer) error) (hash string, err error)
func (m *Store) Path(hash string) string
func (m *Store) Read(hash string) ([]byte, error) // ErrMissing if absent
```

- [ ] **Step 1: Write the failing tests**

`internal/ids/ids_test.go`:

```go
package ids

import (
	"testing"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2/networkid"
)

func TestGhostRoundTrip(t *testing.T) {
	uid := networkid.UserID("15551234567@s.whatsapp.net")
	mxid := GhostMXID("whatsapp", uid)
	require.Equal(t, "courier.local", mxid.Homeserver())
	back, ok := ParseGhostMXID("whatsapp", mxid)
	require.True(t, ok)
	require.Equal(t, uid, back)
	_, ok = ParseGhostMXID("signal", mxid)
	require.False(t, ok, "a WhatsApp ghost must not parse as a Signal ghost")
}

func TestDeterministicIDs(t *testing.T) {
	key := networkid.PortalKey{ID: "chat1", Receiver: "me"}
	r1, r2 := RoomID("whatsapp", key), RoomID("whatsapp", key)
	require.Equal(t, r1, r2)
	require.NotEqual(t, r1, RoomID("telegram", key))
	require.Equal(t, EventID(r1, key, "m1", ""), EventID(r1, key, "m1", ""))
	require.NotEqual(t, EventID(r1, key, "m1", ""), EventID(r1, key, "m1", "p2"))
}

func TestContentURIRoundTrip(t *testing.T) {
	hash, ok := ParseContentURI(ContentURI("abc123"))
	require.True(t, ok)
	require.Equal(t, "abc123", hash)
	_, ok = ParseContentURI("mxc://matrix.org/abc")
	require.False(t, ok)
}
```

`internal/media/media_test.go`:

```go
package media

import (
	"io"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestPutReadIsContentAddressed(t *testing.T) {
	m := &Store{Dir: t.TempDir()}
	h1, err := m.Put([]byte("hello"))
	require.NoError(t, err)
	h2, err := m.PutStream(func(w io.Writer) error { _, err := w.Write([]byte("hello")); return err })
	require.NoError(t, err)
	require.Equal(t, h1, h2)
	got, err := m.Read(h1)
	require.NoError(t, err)
	require.Equal(t, "hello", string(got))
}

func TestOpenMissingMediaErrors(t *testing.T) {
	m := &Store{Dir: t.TempDir()}
	_, err := m.Read("0000000000000000000000000000000000000000000000000000000000000000")
	require.ErrorIs(t, err, ErrMissing)
	_, err = m.Read("../../etc/passwd")
	require.Error(t, err, "non-hash names must be rejected, not read")
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `go test ./internal/ids/ ./internal/media/`
Expected: FAIL with undefined symbols.

- [ ] **Step 3: Implement**

`internal/ids/ids.go`:

```go
// Package ids maps network identifiers to the Matrix-shaped IDs the bridges expect.
package ids

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"strings"

	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/id"
)

const ServerName = "courier.local"

const Me id.UserID = "@me:" + ServerName

func h(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, "\x00")))
	return hex.EncodeToString(sum[:])[:32]
}

func GhostMXID(network string, uid networkid.UserID) id.UserID {
	return id.NewUserID(network+"_"+id.EncodeUserLocalpart(string(uid)), ServerName)
}

func ParseGhostMXID(network string, mxid id.UserID) (networkid.UserID, bool) {
	local, server, err := mxid.Parse()
	if err != nil || server != ServerName || !strings.HasPrefix(local, network+"_") {
		return "", false
	}
	dec, err := id.DecodeUserLocalpart(strings.TrimPrefix(local, network+"_"))
	if err != nil {
		return "", false
	}
	return networkid.UserID(dec), true
}

func RoomID(network string, key networkid.PortalKey) id.RoomID {
	return id.RoomID("!" + h("room", network, string(key.ID), string(key.Receiver)) + ":" + ServerName)
}

func EventID(roomID id.RoomID, key networkid.PortalKey, msg networkid.MessageID, part networkid.PartID) id.EventID {
	return id.EventID("$" + h("evt", string(roomID), string(key.ID), string(msg), string(part)))
}

func ReactionEventID(roomID id.RoomID, msg networkid.MessageID, part networkid.PartID, sender networkid.UserID, emoji networkid.EmojiID) id.EventID {
	return id.EventID("$" + h("react", string(roomID), string(msg), string(part), string(sender), string(emoji)))
}

func RandomEventID() id.EventID {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return id.EventID("$" + hex.EncodeToString(b))
}

func ContentURI(hash string) id.ContentURIString {
	return id.ContentURIString("mxc://" + ServerName + "/" + hash)
}

func ParseContentURI(uri id.ContentURIString) (string, bool) {
	rest, ok := strings.CutPrefix(string(uri), "mxc://"+ServerName+"/")
	return rest, ok && rest != ""
}
```

`internal/media/media.go`:

```go
// Package media stores attachment bytes by SHA-256 so the same file is kept once.
package media

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
)

var ErrMissing = errors.New("media file missing")

var hashRE = regexp.MustCompile(`^[0-9a-f]{64}$`)

type Store struct{ Dir string }

func (m *Store) Path(hash string) string { return filepath.Join(m.Dir, hash[:2], hash) }

func (m *Store) Put(data []byte) (string, error) {
	return m.PutStream(func(w io.Writer) error { _, err := w.Write(data); return err })
}

// PutStream writes to a temp file while hashing, then renames into place atomically.
func (m *Store) PutStream(write func(io.Writer) error) (string, error) {
	if err := os.MkdirAll(m.Dir, 0o700); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(m.Dir, ".upload-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name())
	hasher := sha256.New()
	if err = write(io.MultiWriter(tmp, hasher)); err != nil {
		tmp.Close()
		return "", err
	}
	if err = tmp.Close(); err != nil {
		return "", err
	}
	hash := hex.EncodeToString(hasher.Sum(nil))
	if err = os.MkdirAll(filepath.Dir(m.Path(hash)), 0o700); err != nil {
		return "", err
	}
	return hash, os.Rename(tmp.Name(), m.Path(hash))
}

func (m *Store) Read(hash string) ([]byte, error) {
	if !hashRE.MatchString(hash) {
		return nil, fmt.Errorf("invalid media hash %q", hash)
	}
	b, err := os.ReadFile(m.Path(hash))
	if errors.Is(err, fs.ErrNotExist) {
		return nil, fmt.Errorf("%w: %s", ErrMissing, hash)
	}
	return b, err
}
```

- [ ] **Step 4: Run the tests**

Run: `go test ./internal/ids/ ./internal/media/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
bazel run //:gazelle
git add apps/desktop/courier/engine
git commit -m "feat(courier): deterministic IDs and content-addressed media"
```

---

### Task 4: `MatrixAPI` (intent) backed by the store

**Files:**
- Create: `internal/localmatrix/intent.go`
- Test: `internal/localmatrix/intent_test.go`

**Interfaces:**
- Consumes: `store.Store`, `media.Store`, `ids.*`.
- Produces: `type Intent struct` (unexported fields) implementing `bridgev2.MatrixAPI`, built only by the connector (Task 5). Also a test helper used by Task 5: `newIntent(c *Connector, mxid id.UserID, doublePuppet bool) *Intent`.

Behaviour rules:
- **`SendMessage`:** the event ID is `ids.EventID(roomID, MessageMeta.Room, MessageMeta.ID, MessageMeta.PartID)` when `extra.MessageMeta != nil`, `ids.ReactionEventID(...)` when `extra.ReactionMeta != nil`, otherwise `ids.RandomEventID()`. The timestamp is `extra.Timestamp`, or now. A duplicate insert returns the same event ID without error (Review Focus 1).
- **`SendState`:** writes `store.SetState`. For `m.room.member` it also writes `store.SetMember`. For `m.room.name`, `m.room.topic` and `m.room.avatar` it also updates the `rooms` row.
- **`CreateRoom`:** room ID is `req.BeeperLocalRoomID` if set, else `ids.RandomEventID()`-style random ID with a `!` prefix. It upserts the room with name, topic and `IsDirect` from the request, then applies `req.InitialState` through `SendState`.
- **`UploadMedia` / `UploadMediaStream`:** write through `media.Store` and return `ids.ContentURI(hash)` with a nil `EncryptedFileInfo`. Nothing is encrypted locally.
- **`DownloadMedia` / `DownloadMediaToFile`:** resolve through `ids.ParseContentURI` and `media.Store.Read`. Unknown URIs return an error.
- **`MarkRead`:** `store.SetRead`. `MarkTyping`, `MarkUnread`, `TagRoom`, `MuteRoom`, profile setters and `EnsureJoined` / `EnsureInvited` are recorded as member or state rows, or are no-ops returning nil. Each no-op carries a one-line comment saying why.
- **`DeleteRoom`:** `store.DeleteRoom`.
- **`GetEvent`:** read from the store and convert to `*event.Event`.

- [ ] **Step 1: Write the failing tests**

`internal/localmatrix/intent_test.go`:

```go
package localmatrix

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func newTestConnector(t *testing.T) *Connector {
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return New("whatsapp", s, &media.Store{Dir: filepath.Join(dir, "media")})
}

func textContent(body string) *event.Content {
	return &event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: body}}
}

func TestSendMessageRoundTripsUnicode(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("15550001111@s.whatsapp.net")
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{Name: "Gia đình 👨‍👩‍👧", IsDirect: false})
	require.NoError(t, err)
	body := "Chào cả nhà 🌸 " + strings.Repeat("ạ", 20000)
	key := networkid.PortalKey{ID: "chat1"}
	resp, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent(body),
		&bridgev2.MatrixSendExtra{Timestamp: time.Unix(100, 0), MessageMeta: &database.Message{ID: "m1", Room: key}})
	require.NoError(t, err)
	require.Equal(t, ids.EventID(roomID, key, "m1", ""), resp.EventID)
	got, err := ghost.GetEvent(ctx, roomID, resp.EventID)
	require.NoError(t, err)
	require.Equal(t, body, got.Content.AsMessage().Body)
	room, _, err := c.store.GetRoom(ctx, string(roomID))
	require.NoError(t, err)
	require.Equal(t, "Gia đình 👨‍👩‍👧", room.Name)
}

func TestSendMessageTwiceIsOneEvent(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("u1")
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	extra := &bridgev2.MatrixSendExtra{MessageMeta: &database.Message{ID: "m1", Room: networkid.PortalKey{ID: "c"}}}
	r1, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent("a"), extra)
	require.NoError(t, err)
	r2, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent("a"), extra)
	require.NoError(t, err)
	require.Equal(t, r1.EventID, r2.EventID)
	evs, err := c.store.Events(ctx, string(roomID), 10)
	require.NoError(t, err)
	n := 0
	for _, e := range evs {
		if e.Type == event.EventMessage.Type {
			n++
		}
	}
	require.Equal(t, 1, n)
}

func TestUploadThenDownloadMedia(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	uri, file, err := bot.UploadMedia(ctx, "", []byte("PNGDATA"), "a.png", "image/png")
	require.NoError(t, err)
	require.Nil(t, file)
	got, err := bot.DownloadMedia(ctx, uri, nil)
	require.NoError(t, err)
	require.Equal(t, "PNGDATA", string(got))
	_, err = bot.DownloadMedia(ctx, "mxc://elsewhere/x", nil)
	require.Error(t, err)
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `go test ./internal/localmatrix/`
Expected: FAIL with `undefined: New`. Task 5 supplies `New` and `Connector`, so write Tasks 4 and 5 code before running green.

- [ ] **Step 3: Implement `intent.go`**

```go
package localmatrix

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

type Intent struct {
	c            *Connector
	mxid         id.UserID
	doublePuppet bool
}

var _ bridgev2.MatrixAPI = (*Intent)(nil)

func newIntent(c *Connector, mxid id.UserID, doublePuppet bool) *Intent {
	return &Intent{c: c, mxid: mxid, doublePuppet: doublePuppet}
}

func (in *Intent) GetMXID() id.UserID   { return in.mxid }
func (in *Intent) IsDoublePuppet() bool { return in.doublePuppet }

func (in *Intent) SendMessage(ctx context.Context, roomID id.RoomID, evtType event.Type, content *event.Content, extra *bridgev2.MatrixSendExtra) (*mautrix.RespSendEvent, error) {
	evtID := ids.RandomEventID()
	ts := time.Now()
	if extra != nil {
		if !extra.Timestamp.IsZero() {
			ts = extra.Timestamp
		}
		switch {
		case extra.MessageMeta != nil:
			m := extra.MessageMeta
			evtID = ids.EventID(roomID, m.Room, m.ID, m.PartID)
		case extra.ReactionMeta != nil:
			r := extra.ReactionMeta
			evtID = ids.ReactionEventID(roomID, r.MessageID, r.MessagePartID, r.SenderID, r.EmojiID)
		}
	}
	raw, err := json.Marshal(content)
	if err != nil {
		return nil, err
	}
	if _, err = in.c.store.InsertEvent(ctx, store.Event{RoomID: string(roomID), EventID: string(evtID), Sender: string(in.mxid),
		Type: evtType.Type, Content: raw, TS: ts, Status: "sent"}); err != nil {
		return nil, err
	}
	return &mautrix.RespSendEvent{EventID: evtID}, nil
}

func (in *Intent) SendState(ctx context.Context, roomID id.RoomID, evtType event.Type, stateKey string, content *event.Content, ts time.Time) (*mautrix.RespSendEvent, error) {
	raw, err := json.Marshal(content)
	if err != nil {
		return nil, err
	}
	if err = in.c.store.SetState(ctx, string(roomID), evtType.Type, stateKey, raw); err != nil {
		return nil, err
	}
	if err = in.c.applyRoomState(ctx, roomID, evtType, stateKey, raw); err != nil {
		return nil, err
	}
	return &mautrix.RespSendEvent{EventID: ids.RandomEventID()}, nil
}

func (in *Intent) MarkRead(ctx context.Context, roomID id.RoomID, eventID id.EventID, ts time.Time) error {
	return in.c.store.SetRead(ctx, string(roomID), string(eventID), ts)
}

// Unread flags, typing, tags and mutes are user-interface state owned by the app in milestone 3; the engine accepts them.
func (in *Intent) MarkUnread(context.Context, id.RoomID, bool) error { return nil }
func (in *Intent) MarkTyping(context.Context, id.RoomID, bridgev2.TypingType, time.Duration) error {
	return nil
}
func (in *Intent) TagRoom(context.Context, id.RoomID, event.RoomTag, bool) error { return nil }
func (in *Intent) MuteRoom(context.Context, id.RoomID, time.Time) error           { return nil }

func (in *Intent) DownloadMedia(ctx context.Context, uri id.ContentURIString, _ *event.EncryptedFileInfo) ([]byte, error) {
	hash, ok := ids.ParseContentURI(uri)
	if !ok {
		return nil, fmt.Errorf("not a courier media URI: %s", uri)
	}
	return in.c.media.Read(hash)
}

func (in *Intent) DownloadMediaToFile(ctx context.Context, uri id.ContentURIString, file *event.EncryptedFileInfo, _ bool, cb func(*os.File) error) error {
	data, err := in.DownloadMedia(ctx, uri, file)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp("", "courier-dl-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	if _, err = tmp.Write(data); err != nil {
		return err
	}
	if _, err = tmp.Seek(0, io.SeekStart); err != nil {
		return err
	}
	return cb(tmp)
}

func (in *Intent) UploadMedia(ctx context.Context, _ id.RoomID, data []byte, _, _ string) (id.ContentURIString, *event.EncryptedFileInfo, error) {
	hash, err := in.c.media.Put(data)
	if err != nil {
		return "", nil, err
	}
	return ids.ContentURI(hash), nil, nil
}

func (in *Intent) UploadMediaStream(ctx context.Context, _ id.RoomID, _ int64, _ bool, cb bridgev2.FileStreamCallback) (id.ContentURIString, *event.EncryptedFileInfo, error) {
	var buf bytes.Buffer
	res, err := cb(&buf)
	if err != nil {
		return "", nil, err
	}
	data := buf.Bytes()
	if res != nil && res.ReplacementFile != "" {
		if data, err = os.ReadFile(res.ReplacementFile); err != nil {
			return "", nil, err
		}
	}
	return in.UploadMedia(ctx, "", data, "", "")
}

// Profiles live on member events, written through SendState; the store needs no separate profile table.
func (in *Intent) SetDisplayName(context.Context, string) error             { return nil }
func (in *Intent) SetAvatarURL(context.Context, id.ContentURIString) error { return nil }
func (in *Intent) SetExtraProfileMeta(context.Context, any) error          { return nil }
func (in *Intent) SetProfile(context.Context, any) error                   { return nil }

func (in *Intent) CreateRoom(ctx context.Context, req *mautrix.ReqCreateRoom) (id.RoomID, error) {
	roomID := req.BeeperLocalRoomID
	if roomID == "" {
		roomID = id.RoomID("!" + string(ids.RandomEventID())[1:] + ":" + ids.ServerName)
	}
	if err := in.c.store.UpsertRoom(ctx, store.Room{ID: string(roomID), Network: in.c.network, Name: req.Name, Topic: req.Topic, IsDirect: req.IsDirect}); err != nil {
		return "", err
	}
	for _, st := range req.InitialState {
		sk := ""
		if st.StateKey != nil {
			sk = *st.StateKey
		}
		if _, err := in.SendState(ctx, roomID, st.Type, sk, &st.Content, time.Now()); err != nil {
			return "", err
		}
	}
	for _, u := range append([]id.UserID{in.mxid}, req.Invite...) {
		if err := in.c.store.SetMember(ctx, string(roomID), string(u), json.RawMessage(`{"membership":"join"}`)); err != nil {
			return "", err
		}
	}
	return roomID, nil
}

func (in *Intent) DeleteRoom(ctx context.Context, roomID id.RoomID, _ bool) error {
	return in.c.store.DeleteRoom(ctx, string(roomID))
}

func (in *Intent) EnsureJoined(ctx context.Context, roomID id.RoomID, _ ...bridgev2.EnsureJoinedParams) error {
	return in.c.store.SetMember(ctx, string(roomID), string(in.mxid), json.RawMessage(`{"membership":"join"}`))
}

func (in *Intent) EnsureInvited(ctx context.Context, roomID id.RoomID, userID id.UserID) error {
	return in.c.store.SetMember(ctx, string(roomID), string(userID), json.RawMessage(`{"membership":"join"}`))
}

func (in *Intent) GetEvent(ctx context.Context, roomID id.RoomID, eventID id.EventID) (*event.Event, error) {
	e, ok, err := in.c.store.GetEvent(ctx, string(eventID))
	if err != nil {
		return nil, err
	}
	if !ok || e.RoomID != string(roomID) {
		return nil, mautrix.MNotFound
	}
	evt := &event.Event{ID: eventID, RoomID: roomID, Sender: id.UserID(e.Sender), Type: event.Type{Type: e.Type, Class: event.MessageEventType},
		Timestamp: e.TS.UnixMilli(), StateKey: e.StateKey}
	if err = json.Unmarshal(e.Content, &evt.Content); err != nil {
		return nil, err
	}
	_ = evt.Content.ParseRaw(evt.Type)
	return evt, nil
}
```

- [ ] **Step 4: Commit together with Task 5** (the tests need `New`).

---

### Task 5: `MatrixConnector`

**Files:**
- Create: `internal/localmatrix/connector.go`
- Test: `internal/localmatrix/connector_test.go`

**Interfaces:**
- Consumes: `Intent` (Task 4), store, media, ids.
- Produces:

```go
type Connector struct { /* unexported */ }
func New(network string, s *store.Store, m *media.Store) *Connector
var _ bridgev2.MatrixConnector = (*Connector)(nil)
func (c *Connector) Bridge() *bridgev2.Bridge // set by Init; used by host (Task 7) and fakenet tests (Task 6)
```

- [ ] **Step 1: Write the failing tests**

`internal/localmatrix/connector_test.go`:

```go
package localmatrix

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestGhostIDsRoundTripThroughConnector(t *testing.T) {
	c := newTestConnector(t)
	mxid := c.FormatGhostMXID("u1")
	uid, ok := c.ParseGhostMXID(mxid)
	require.True(t, ok)
	require.EqualValues(t, "u1", uid)
	require.Equal(t, ids.ServerName, c.ServerName())
}

func TestMessageStatusUpdatesStore(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	_, err = c.store.InsertEvent(ctx, store.Event{RoomID: string(roomID), EventID: "$mine", Sender: string(ids.Me),
		Type: "m.room.message", Content: json.RawMessage(`{}`), Status: "pending"})
	require.NoError(t, err)
	c.SendMessageStatus(ctx, &bridgev2.MessageStatus{Status: event.MessageStatusFail, Message: "not delivered"},
		&bridgev2.MessageStatusEventInfo{RoomID: roomID, SourceEventID: "$mine"})
	e, _, err := c.store.GetEvent(ctx, "$mine")
	require.NoError(t, err)
	require.Equal(t, "failed", e.Status)
	require.Equal(t, "not delivered", e.StatusReason)
}

func TestBridgeStateIsStored(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	require.NoError(t, c.SendBridgeStatus(ctx, &status.BridgeState{StateEvent: status.StateConnected}))
	raw, ok, err := c.store.BridgeState(ctx, "whatsapp")
	require.NoError(t, err)
	require.True(t, ok)
	require.Contains(t, string(raw), "CONNECTED")
}

func TestMembersReflectCreateRoom(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.GhostIntent("u1").CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me}})
	require.NoError(t, err)
	m, err := c.GetMembers(ctx, roomID)
	require.NoError(t, err)
	require.Contains(t, m, ids.Me)
	require.Contains(t, m, c.FormatGhostMXID("u1"))
}
```

Add `"maunium.net/go/mautrix/id"` to that file's imports.

- [ ] **Step 2: Run them to verify they fail**

Run: `go test ./internal/localmatrix/`
Expected: FAIL with `undefined: New`.

- [ ] **Step 3: Implement `connector.go`**

```go
// Package localmatrix lets stock mautrix bridges run with courier's local store in place of a Matrix server.
package localmatrix

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

type Connector struct {
	network string
	store   *store.Store
	media   *media.Store
	br      *bridgev2.Bridge
	log     zerolog.Logger
}

var _ bridgev2.MatrixConnector = (*Connector)(nil)

func New(network string, s *store.Store, m *media.Store) *Connector {
	return &Connector{network: network, store: s, media: m, log: zerolog.Nop()}
}

func (c *Connector) Bridge() *bridgev2.Bridge { return c.br }

func (c *Connector) Init(br *bridgev2.Bridge) {
	c.br = br
	c.log = br.Log.With().Str("component", "localmatrix").Logger()
}
func (c *Connector) Start(context.Context) error { return nil }
func (c *Connector) PreStop()                    {}
func (c *Connector) Stop()                       {}

func (c *Connector) GetCapabilities() *bridgev2.MatrixCapabilities {
	// AutoJoinInvites: no real invites exist locally. ArbitraryMemberChange: we write any member row directly.
	return &bridgev2.MatrixCapabilities{AutoJoinInvites: true, ArbitraryMemberChange: true}
}

func (c *Connector) ParseGhostMXID(userID id.UserID) (networkid.UserID, bool) {
	return ids.ParseGhostMXID(c.network, userID)
}
func (c *Connector) FormatGhostMXID(userID networkid.UserID) id.UserID {
	return ids.GhostMXID(c.network, userID)
}
func (c *Connector) GhostIntent(userID networkid.UserID) bridgev2.MatrixAPI {
	return newIntent(c, c.FormatGhostMXID(userID), false)
}
func (c *Connector) NewUserIntent(_ context.Context, userID id.UserID, _ string) (bridgev2.MatrixAPI, string, error) {
	// The local user is "double puppeted" by definition: messages sent from other devices appear as sent by @me.
	return newIntent(c, userID, true), "", nil
}
func (c *Connector) BotIntent() bridgev2.MatrixAPI {
	return newIntent(c, id.NewUserID(c.network+"bot", ids.ServerName), false)
}

func (c *Connector) SendBridgeStatus(ctx context.Context, st *status.BridgeState) error {
	raw, err := json.Marshal(st)
	if err != nil {
		return err
	}
	return c.store.SetBridgeState(ctx, c.network, raw)
}

func (c *Connector) SendMessageStatus(ctx context.Context, ms *bridgev2.MessageStatus, info *bridgev2.MessageStatusEventInfo) {
	st := "sent"
	switch ms.Status {
	case event.MessageStatusFail, event.MessageStatusRetriable:
		st = "failed"
	case event.MessageStatusPending:
		st = "pending"
	}
	if err := c.store.SetStatus(ctx, string(info.SourceEventID), st, ms.Message); err != nil {
		c.log.Warn().Err(err).Stringer("event_id", info.SourceEventID).Msg("failed to store message status")
	}
}

func (c *Connector) GenerateContentURI(_ context.Context, mediaID networkid.MediaID) (id.ContentURIString, error) {
	return "", fmt.Errorf("direct media is not supported locally (media %s)", mediaID)
}
func (c *Connector) ParseContentURI(_ context.Context, uri id.ContentURIString) (networkid.MediaID, error) {
	return nil, fmt.Errorf("direct media is not supported locally (%s)", uri)
}

func (c *Connector) GetPowerLevels(ctx context.Context, roomID id.RoomID) (*event.PowerLevelsEventContent, error) {
	pl := &event.PowerLevelsEventContent{}
	raw, ok, err := c.store.GetState(ctx, string(roomID), event.StatePowerLevels.Type, "")
	if err != nil || !ok {
		return pl, err
	}
	var content event.Content
	if err = json.Unmarshal(raw, &content); err != nil {
		return nil, err
	}
	if err = content.ParseRaw(event.StatePowerLevels); err != nil {
		return nil, err
	}
	return content.AsPowerLevels(), nil
}

func (c *Connector) GetMembers(ctx context.Context, roomID id.RoomID) (map[id.UserID]*event.MemberEventContent, error) {
	rows, err := c.store.Members(ctx, string(roomID))
	if err != nil {
		return nil, err
	}
	out := make(map[id.UserID]*event.MemberEventContent, len(rows))
	for u, raw := range rows {
		var m event.MemberEventContent
		if err := json.Unmarshal(raw, &m); err != nil {
			return nil, err
		}
		out[id.UserID(u)] = &m
	}
	return out, nil
}

func (c *Connector) GetMemberInfo(ctx context.Context, roomID id.RoomID, userID id.UserID) (*event.MemberEventContent, error) {
	all, err := c.GetMembers(ctx, roomID)
	if err != nil {
		return nil, err
	}
	return all[userID], nil
}

func (c *Connector) BatchSend(context.Context, id.RoomID, *mautrix.ReqBeeperBatchSend, []*bridgev2.MatrixSendExtra) (*mautrix.RespBeeperBatchSend, error) {
	// GetCapabilities reports BatchSending=false, so bridgev2 backfills through SendMessage instead.
	return nil, fmt.Errorf("batch send not supported")
}

func (c *Connector) GenerateDeterministicRoomID(key networkid.PortalKey) id.RoomID {
	return ids.RoomID(c.network, key)
}
func (c *Connector) GenerateDeterministicEventID(roomID id.RoomID, key networkid.PortalKey, msg networkid.MessageID, part networkid.PartID) id.EventID {
	return ids.EventID(roomID, key, msg, part)
}
func (c *Connector) GenerateReactionEventID(roomID id.RoomID, target *database.Message, sender networkid.UserID, emoji networkid.EmojiID) id.EventID {
	return ids.ReactionEventID(roomID, target.ID, target.PartID, sender, emoji)
}

func (c *Connector) ServerName() string { return ids.ServerName }

// applyRoomState mirrors name/topic/avatar/member state into the rooms and members tables the app reads.
func (c *Connector) applyRoomState(ctx context.Context, roomID id.RoomID, evtType event.Type, stateKey string, raw json.RawMessage) error {
	var fields struct {
		Name  string              `json:"name"`
		Topic string              `json:"topic"`
		URL   id.ContentURIString `json:"url"`
	}
	_ = json.Unmarshal(raw, &fields)
	room, ok, err := c.store.GetRoom(ctx, string(roomID))
	if err != nil {
		return err
	}
	if !ok {
		room = store.Room{ID: string(roomID), Network: c.network, CreatedAt: time.Now()}
	}
	switch evtType {
	case event.StateMember:
		return c.store.SetMember(ctx, string(roomID), stateKey, raw)
	case event.StateRoomName:
		room.Name = fields.Name
	case event.StateTopic:
		room.Topic = fields.Topic
	case event.StateRoomAvatar:
		room.AvatarURI = string(fields.URL)
	default:
		return nil
	}
	return c.store.UpsertRoom(ctx, room)
}
```

- [ ] **Step 4: Run the Task 4 and 5 tests**

Run: `go test -race ./internal/localmatrix/`
Expected: PASS for all of `TestSendMessageRoundTripsUnicode`, `TestSendMessageTwiceIsOneEvent`, `TestUploadThenDownloadMedia`, `TestGhostIDsRoundTripThroughConnector`, `TestMessageStatusUpdatesStore`, `TestBridgeStateIsStored` and `TestMembersReflectCreateRoom`. If the compile fails because a v0.31.0 field name differs (for example on `database.Reaction`), read `bridgev2/database/reaction.go` at v0.31.0 and use the real field. Don't rename the interface methods.

- [ ] **Step 5: Commit**

```bash
bazel run //:gazelle && bazel test //apps/desktop/courier/engine/...
git add apps/desktop/courier/engine
git commit -m "feat(courier): local Matrix connector and intents over the store"
```

---

### Task 6: Fake network and the end-to-end glue test (the CI proof)

**Files:**
- Create: `internal/fakenet/fakenet.go`
- Test: `internal/fakenet/glue_test.go`

**Interfaces:**
- Consumes: `localmatrix.New`, `store.Open`, `media.Store`, `ids.Me`.
- Produces:

```go
type Network struct { Sent chan string /* bodies the bridge delivered to the fake network */ }
func New() *Network                       // implements bridgev2.NetworkConnector
func (n *Network) Login(ctx context.Context, br *bridgev2.Bridge) (*bridgev2.UserLogin, error) // creates login "fake-login" for ids.Me
func (n *Network) Incoming(login *bridgev2.UserLogin, chatID, senderID, msgID, body string)   // queues a remote text message
```

- [ ] **Step 1: Write the failing test**

`internal/fakenet/glue_test.go`:

```go
package fakenet

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/localmatrix"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestRemoteMessageLandsAndReplyGoesOut(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	bdb, err := sqlite.Open(filepath.Join(dir, "fake.db"))
	require.NoError(t, err)
	net := New()
	conn := localmatrix.New("fake", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{CommandPrefix: "!fake",
		Permissions: bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin}}
	br := bridgev2.NewBridge("fake", bdb, zerolog.Nop(), cfg, conn, net, func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	defer br.Stop()

	login, err := net.Login(ctx, br)
	require.NoError(t, err)

	net.Incoming(login, "chat1", "alice", "m1", "hello from the network")

	// Don't assume how bridgev2 picks the room ID: find whichever room received the message.
	var roomID id.RoomID
	require.Eventually(t, func() bool {
		rooms, _ := s.ListRooms(ctx)
		for _, r := range rooms {
			evs, _ := s.Events(ctx, r.ID, 10)
			for _, e := range evs {
				if e.Type == event.EventMessage.Type && strings.Contains(string(e.Content), "hello from the network") {
					roomID = id.RoomID(r.ID)
					return true
				}
			}
		}
		return false
	}, 5*time.Second, 50*time.Millisecond, "remote message never reached courier.db")

	reply := &event.Event{Type: event.EventMessage, RoomID: roomID, Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: "hi alice"}}}
	br.QueueMatrixEvent(ctx, reply)
	select {
	case body := <-net.Sent:
		require.Equal(t, "hi alice", body)
	case <-time.After(5 * time.Second):
		t.Fatal("reply never reached the fake network")
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `go test ./internal/fakenet/`
Expected: FAIL with `undefined: New`.

- [ ] **Step 3: Implement `fakenet.go`**

```go
// Package fakenet is an in-memory chat network so the bridge-to-store glue is tested in CI without real accounts.
package fakenet

import (
	"context"
	"time"

	"go.mau.fi/util/configupgrade"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

type Network struct {
	br   *bridgev2.Bridge
	Sent chan string
}

func New() *Network { return &Network{Sent: make(chan string, 16)} }

var _ bridgev2.NetworkConnector = (*Network)(nil)

func (n *Network) Init(br *bridgev2.Bridge)  { n.br = br }
func (n *Network) Start(context.Context) error { return nil }
func (n *Network) GetName() bridgev2.BridgeName {
	return bridgev2.BridgeName{DisplayName: "Fake", NetworkID: "fake", BeeperBridgeType: "fake", DefaultPort: 0}
}
func (n *Network) GetDBMetaTypes() database.MetaTypes             { return database.MetaTypes{} }
func (n *Network) GetCapabilities() *bridgev2.NetworkGeneralCapabilities { return &bridgev2.NetworkGeneralCapabilities{} }
func (n *Network) GetConfig() (string, any, configupgrade.Upgrader) { return "", nil, configupgrade.NoopUpgrader }
func (n *Network) GetBridgeInfoVersion() (int, int)                 { return 1, 1 }
func (n *Network) GetLoginFlows() []bridgev2.LoginFlow              { return nil }
func (n *Network) CreateLogin(context.Context, *bridgev2.User, string) (bridgev2.LoginProcess, error) {
	return nil, bridgev2.ErrInvalidLoginFlowID
}
func (n *Network) LoadUserLogin(_ context.Context, login *bridgev2.UserLogin) error {
	login.Client = &client{n: n, login: login}
	return nil
}

// Login creates the one test login for the local user without any login flow.
func (n *Network) Login(ctx context.Context, br *bridgev2.Bridge) (*bridgev2.UserLogin, error) {
	user, err := br.GetUserByMXID(ctx, ids.Me)
	if err != nil {
		return nil, err
	}
	login, err := user.NewLogin(ctx, &database.UserLogin{ID: "fake-login", RemoteName: "Me"}, nil)
	if err != nil {
		return nil, err
	}
	login.Client.Connect(ctx)
	return login, nil
}

func (n *Network) Incoming(login *bridgev2.UserLogin, chatID, senderID, msgID, body string) {
	n.br.QueueRemoteEvent(login, &simplevent.Message[string]{
		EventMeta: simplevent.EventMeta{Type: bridgev2.RemoteEventMessage, CreatePortal: true, Timestamp: time.Now(),
			PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: login.ID},
			Sender:    bridgev2.EventSender{Sender: networkid.UserID(senderID)}},
		ID:   networkid.MessageID(msgID),
		Data: body,
		ConvertMessageFunc: func(_ context.Context, _ *bridgev2.Portal, _ bridgev2.MatrixAPI, data string) (*bridgev2.ConvertedMessage, error) {
			return &bridgev2.ConvertedMessage{Parts: []*bridgev2.ConvertedMessagePart{{Type: event.EventMessage,
				Content: &event.MessageEventContent{MsgType: event.MsgText, Body: data}}}}, nil
		},
	})
}

type client struct {
	n     *Network
	login *bridgev2.UserLogin
}

var _ bridgev2.NetworkAPI = (*client)(nil)

func (c *client) Connect(context.Context) {}
func (c *client) Disconnect()             {}
func (c *client) IsLoggedIn() bool        { return true }
func (c *client) LogoutRemote(context.Context) {}
func (c *client) IsThisUser(_ context.Context, uid networkid.UserID) bool { return uid == "me" }
func (c *client) GetChatInfo(context.Context, *bridgev2.Portal) (*bridgev2.ChatInfo, error) {
	name := "Fake chat"
	return &bridgev2.ChatInfo{Name: &name}, nil
}
func (c *client) GetUserInfo(context.Context, *bridgev2.Ghost) (*bridgev2.UserInfo, error) {
	return &bridgev2.UserInfo{}, nil
}
func (c *client) GetCapabilities(context.Context, *bridgev2.Portal) *event.RoomFeatures {
	return &event.RoomFeatures{}
}
func (c *client) HandleMatrixMessage(_ context.Context, msg *bridgev2.MatrixMessage) (*bridgev2.MatrixMessageResponse, error) {
	c.n.Sent <- msg.Content.Body
	return &bridgev2.MatrixMessageResponse{DB: &database.Message{ID: networkid.MessageID("out-" + string(msg.Event.ID)),
		SenderID: "me", Timestamp: time.Now()}}, nil
}
```

- [ ] **Step 4: Run the glue test**

Run: `go test -race -run TestRemoteMessageLandsAndReplyGoesOut -v ./internal/fakenet/`
Expected: PASS. **This is the milestone's technical gate.** If it can't be made to pass because `bridgev2` needs something the local connector can't provide, write down exactly which call failed and why in `engine/docs/m1-result.md`. Then stop and raise the spec's kill criterion (switch to option B) with James instead of working around it. If a field or constant above doesn't exist at v0.31.0 (for example `bridgev2.ErrInvalidLoginFlowID` or `configupgrade.NoopUpgrader`), check the v0.31.0 source for the real name and use that.

- [ ] **Step 5: Commit**

```bash
bazel run //:gazelle && bazel test //apps/desktop/courier/engine/...
git add apps/desktop/courier/engine
git commit -m "test(courier): fake network proves bridge-to-store glue end to end"
```

---

### Task 7: Bridge host: one network connector, its DB, config and restart

**Files:**
- Create: `internal/host/host.go`
- Test: `internal/host/host_test.go`

**Interfaces:**
- Consumes: `store`, `media`, `sqlite.Open`, `localmatrix.New`, `fakenet` (tests only).
- Produces:

```go
type Host struct { Bridge *bridgev2.Bridge; Network string /* unexported rest */ }
// Start opens <dataDir>/bridges/<network>.db, loads the connector's example config as defaults, and starts the bridge with @me as admin.
func Start(ctx context.Context, dataDir, network string, s *store.Store, m *media.Store, nc bridgev2.NetworkConnector, log zerolog.Logger) (*Host, error)
func (h *Host) Stop()
func (h *Host) Me(ctx context.Context) (*bridgev2.User, error)
```

- [ ] **Step 1: Write the failing test**

`internal/host/host_test.go`:

```go
package host

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestHostRestartReloadsLogin(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	m := &media.Store{Dir: filepath.Join(dir, "media")}

	net1 := fakenet.New()
	h1, err := Start(ctx, dir, "fake", s, m, net1, zerolog.Nop())
	require.NoError(t, err)
	_, err = net1.Login(ctx, h1.Bridge)
	require.NoError(t, err)
	h1.Stop()

	h2, err := Start(ctx, dir, "fake", s, m, fakenet.New(), zerolog.Nop())
	require.NoError(t, err)
	defer h2.Stop()
	me, err := h2.Me(ctx)
	require.NoError(t, err)
	require.Len(t, me.GetUserLogins(), 1, "the login made before the restart must be loaded again")
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `go test ./internal/host/`
Expected: FAIL with `undefined: Start`.

- [ ] **Step 3: Implement `host.go`**

```go
// Package host runs one network connector against courier's local store, with its own bridge database.
package host

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/rs/zerolog"
	"gopkg.in/yaml.v3"
	"go.mau.fi/util/dbutil"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/localmatrix"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

type Host struct {
	Bridge  *bridgev2.Bridge
	Network string
	db      *dbutil.Database
}

func Start(ctx context.Context, dataDir, network string, s *store.Store, m *media.Store, nc bridgev2.NetworkConnector, log zerolog.Logger) (*Host, error) {
	if err := os.MkdirAll(filepath.Join(dataDir, "bridges"), 0o700); err != nil {
		return nil, err
	}
	db, err := sqlite.Open(filepath.Join(dataDir, "bridges", network+".db"))
	if err != nil {
		return nil, err
	}
	// Network config: the connector's own example YAML is the default, as mxmain does for standalone bridges.
	if example, data, _ := nc.GetConfig(); data != nil && example != "" {
		var wrapper struct {
			Network yaml.Node `yaml:"network"`
		}
		if err = yaml.Unmarshal([]byte(example), &wrapper); err == nil && wrapper.Network.Kind != 0 {
			if err = wrapper.Network.Decode(data); err != nil {
				db.Close()
				return nil, fmt.Errorf("default %s config: %w", network, err)
			}
		}
	}
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix:   "!" + network,
		Permissions:     bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
		Backfill:        bridgeconfig.BackfillConfig{Enabled: true},
		CleanupOnLogout: bridgeconfig.CleanupOnLogouts{Enabled: false},
	}
	conn := localmatrix.New(network, s, m)
	br := bridgev2.NewBridge(networkid.BridgeID(network), db, log.With().Str("bridge", network).Logger(), cfg, conn, nc,
		func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	if err = br.Start(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("start %s bridge: %w", network, err)
	}
	return &Host{Bridge: br, Network: network, db: db}, nil
}

func (h *Host) Stop() {
	h.Bridge.Stop()
	h.db.Close()
}

func (h *Host) Me(ctx context.Context) (*bridgev2.User, error) { return h.Bridge.GetUserByMXID(ctx, ids.Me) }
```

Add the dependency: `go get gopkg.in/yaml.v3` (already in the root module, so `bazel mod tidy` keeps it).

- [ ] **Step 4: Run the test**

Run: `go test -race ./internal/host/ && bazel run //:gazelle && bazel mod tidy && bazel test //apps/desktop/courier/engine/...`
Expected: PASS. If `BackfillConfig` or `CleanupOnLogouts` has different field names at v0.31.0, read `bridgev2/bridgeconfig/backfill.go` and `config.go` and use the real ones. Backfill on and logout cleanup off are the requirements.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/courier/engine
git commit -m "feat(courier): bridge host with per-network database and restart"
```

---

### Task 8: Test CLI driving the real WhatsApp connector

**Files:**
- Create: `cmd/courier-engine-cli/main.go`
- Modify: `go.mod` (add `go.mau.fi/mautrix-whatsapp@v0.2609.0`, `github.com/mdp/qrterminal/v3`)
- Test: `cmd/courier-engine-cli/main_test.go` (argument parsing only; real WhatsApp is Task 9)

**Interfaces:**
- Consumes: `host.Start`, `store`, `media`, `ids`.
- Produces: `courier-engine-cli [--data DIR] link|chats|tail|send <room-id> <text>`. `--data` defaults to `~/Library/Application Support/Courier-m1`. That's a separate folder, so the milestone check can never touch a future real Courier install.

- [ ] **Step 1: Write the failing test**

```go
package main

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestParseArgs(t *testing.T) {
	a, err := parseArgs([]string{"--data", "/tmp/x", "send", "!r:courier.local", "hello", "there"})
	require.NoError(t, err)
	require.Equal(t, args{data: "/tmp/x", cmd: "send", room: "!r:courier.local", text: "hello there"}, a)
	_, err = parseArgs([]string{"send", "!r:courier.local"})
	require.Error(t, err, "send without text must be rejected")
	_, err = parseArgs([]string{"bogus"})
	require.Error(t, err)
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `go test ./cmd/courier-engine-cli/`
Expected: FAIL with `undefined: parseArgs`.

- [ ] **Step 3: Implement `main.go`**

```go
// courier-engine-cli drives the milestone-1 engine by hand: link WhatsApp, list chats, watch and send.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"time"

	"github.com/mdp/qrterminal/v3"
	"github.com/rs/zerolog"
	"go.mau.fi/mautrix-whatsapp/pkg/connector"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

type args struct{ data, cmd, room, text string }

func parseArgs(argv []string) (args, error) {
	home, _ := os.UserHomeDir()
	fs := flag.NewFlagSet("courier-engine-cli", flag.ContinueOnError)
	data := fs.String("data", filepath.Join(home, "Library", "Application Support", "Courier-m1"), "data directory")
	if err := fs.Parse(argv); err != nil {
		return args{}, err
	}
	rest := fs.Args()
	if len(rest) == 0 {
		return args{}, errors.New("usage: courier-engine-cli [--data DIR] link|chats|tail|send <room-id> <text>")
	}
	a := args{data: *data, cmd: rest[0]}
	switch a.cmd {
	case "link", "chats", "tail":
	case "send":
		if len(rest) < 3 {
			return args{}, errors.New("send needs <room-id> <text>")
		}
		a.room, a.text = rest[1], strings.Join(rest[2:], " ")
	default:
		return args{}, fmt.Errorf("unknown command %q", a.cmd)
	}
	return a, nil
}

func main() {
	a, err := parseArgs(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	if err = run(ctx, a); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, a args) error {
	if err := os.MkdirAll(a.data, 0o700); err != nil {
		return err
	}
	log := zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).Level(zerolog.WarnLevel).With().Timestamp().Logger()
	s, err := store.Open(filepath.Join(a.data, "courier.db"))
	if err != nil {
		return err
	}
	defer s.Close()
	h, err := host.Start(ctx, a.data, "whatsapp", s, &media.Store{Dir: filepath.Join(a.data, "media")}, &connector.WhatsAppConnector{}, log)
	if err != nil {
		return err
	}
	defer h.Stop()
	switch a.cmd {
	case "link":
		return link(ctx, h)
	case "chats":
		rooms, err := s.ListRooms(ctx)
		for _, r := range rooms {
			fmt.Printf("%s\t%s\n", r.ID, r.Name)
		}
		return err
	case "tail":
		return tail(ctx, s)
	case "send":
		evt := &event.Event{Type: event.EventMessage, RoomID: id.RoomID(a.room), Sender: ids.Me, ID: ids.RandomEventID(),
			Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: a.text}}}
		raw, _ := json.Marshal(&evt.Content)
		if _, err = s.InsertEvent(ctx, store.Event{RoomID: a.room, EventID: string(evt.ID), Sender: string(ids.Me),
			Type: evt.Type.Type, Content: raw, TS: time.Now(), Status: "pending"}); err != nil {
			return err
		}
		h.Bridge.QueueMatrixEvent(ctx, evt)
		return waitStatus(ctx, s, string(evt.ID))
	}
	return nil
}

func link(ctx context.Context, h *host.Host) error {
	me, err := h.Me(ctx)
	if err != nil {
		return err
	}
	proc, err := h.Bridge.Network.CreateLogin(ctx, me, "qr")
	if err != nil {
		return fmt.Errorf("start QR login: %w", err)
	}
	step, err := proc.Start(ctx)
	for err == nil && step.Type == bridgev2.LoginStepTypeDisplayAndWait {
		if p := step.DisplayAndWaitParams; p != nil && p.Type == bridgev2.LoginDisplayTypeQR {
			fmt.Println("Scan with WhatsApp → Settings → Linked devices → Link a device:")
			qrterminal.GenerateHalfBlock(p.Data, qrterminal.L, os.Stdout)
		}
		step, err = proc.(bridgev2.LoginProcessDisplayAndWait).Wait(ctx)
	}
	if err != nil {
		return err
	}
	if step.Type != bridgev2.LoginStepTypeComplete {
		return fmt.Errorf("unexpected login step %s", step.Type)
	}
	fmt.Println("Linked. Leave this running a minute so history backfills, then Ctrl-C.")
	<-ctx.Done()
	return nil
}

func tail(ctx context.Context, s *store.Store) error {
	feed, cancel := s.Subscribe()
	defer cancel()
	fmt.Println("Waiting for messages. Ctrl-C to stop.")
	for {
		select {
		case <-ctx.Done():
			return nil
		case c := <-feed:
			if c.Kind != "event" {
				continue
			}
			e, ok, err := s.GetEvent(ctx, c.EventID)
			if err != nil || !ok || e.Type != event.EventMessage.Type {
				continue
			}
			var body struct{ Body string `json:"body"` }
			_ = json.Unmarshal(e.Content, &body)
			fmt.Printf("%s  %s  %s: %s\n", e.TS.Format(time.Kitchen), e.RoomID, e.Sender, body.Body)
		}
	}
}

func waitStatus(ctx context.Context, s *store.Store, eventID string) error {
	deadline := time.After(30 * time.Second)
	for {
		e, _, err := s.GetEvent(ctx, eventID)
		if err != nil {
			return err
		}
		if e.Status == "sent" || e.Status == "failed" {
			fmt.Println("status:", e.Status, e.StatusReason)
			return nil
		}
		select {
		case <-deadline:
			return errors.New("no delivery status within 30 s")
		case <-time.After(200 * time.Millisecond):
		}
	}
}
```

Note: the bridge reports success through `SendMessageStatus` with `event.MessageStatusSuccess`, which Task 5 maps to `"sent"`. If the WhatsApp connector's login flow ID isn't `"qr"` at v0.2609.0, print `h.Bridge.Network.GetLoginFlows()` and use the QR flow's real ID.

- [ ] **Step 4: Run the tests and build**

Run: `go test ./cmd/courier-engine-cli/ && bazel run //:gazelle && bazel mod tidy && bazel build //apps/desktop/courier/engine/cmd/courier-engine-cli`
Expected: PASS and a built binary. If the Bazel build of `go.mau.fi/mautrix-whatsapp` (and its `whatsmeow`, `libsignal` protobufs) needs extra gazelle directives, add them as `gazelle:resolve` or `go_deps.gazelle_override` lines in `MODULE.bazel`, with a comment naming the module.

- [ ] **Step 5: Commit**

```bash
git add go.work apps/desktop/courier/engine MODULE.bazel
git commit -m "feat(courier): test CLI for linking, watching and replying on WhatsApp"
```

---

### Task 9: Milestone check on real WhatsApp, by hand, and record the result

**Files:**
- Create: `apps/desktop/courier/engine/docs/m1-result.md`

- [ ] **Step 1: Link as an extra device (Beeper stays linked)**

Run: `bazel run //apps/desktop/courier/engine/cmd/courier-engine-cli -- link`
Expected: a QR in the terminal. After scanning on James's phone, "Linked." appears, and WhatsApp → Linked devices shows a new device next to Beeper.

- [ ] **Step 2: Receive**

Run `… -- tail` in one terminal. Have a test contact (or a second WhatsApp account James controls) send "courier test 1".
Expected: the line appears within a few seconds. Run `… -- chats` and confirm the chat is listed.

- [ ] **Step 3: Send**

Run: `… -- send '<room-id from chats>' 'courier reply 1'` to a chat with James's own second number or a willing tester. **Never send to real contacts without James's go-ahead.**
Expected: `status: sent`, and the message shows on the phone.

- [ ] **Step 4: Restart**

Ctrl-C everything, run `tail` again, and send another test message.
Expected: received without re-linking.

- [ ] **Step 5: Record the result and the kill-criterion decision**

`docs/m1-result.md` records:
- the date and the commit;
- pass or fail for each of steps 1–4;
- anything the bridge needed that the local store faked (each no-op that turned out to matter);
- the decision: **continue with architecture A**, or **switch to B**, with the one-paragraph reason.

Include no phone numbers, names or message text.

- [ ] **Step 6: Unlink and clean up**

In WhatsApp → Linked devices, remove the milestone-1 device unless James wants to keep it. Then run `rm -rf ~/Library/Application\ Support/Courier-m1`.

- [ ] **Step 7: Commit**

```bash
git add apps/desktop/courier/engine/docs/m1-result.md
git commit -m "docs(courier): milestone 1 result on real WhatsApp"
```
