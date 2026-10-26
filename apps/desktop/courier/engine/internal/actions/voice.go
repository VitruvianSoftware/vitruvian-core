// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"go.mau.fi/util/ffmpeg"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
)

// MaxFileCeiling is the 2 GiB upper bound applied when a streaming bridge (Telegram) advertises a per-kind FileFeatures.MaxSize.
const MaxFileCeiling int64 = 2 * 1024 * 1024 * 1024

// MaxInMemoryFileCeiling is the 100 MiB upper bound applied to non-streaming bridges (WhatsApp, Signal, Google Messages, Slack)
// that call Bot.DownloadMedia into a []byte in memory rather than DownloadMediaToFile.
const MaxInMemoryFileCeiling int64 = 100 * 1024 * 1024

// FFmpegSearchPaths are the standard macOS package-manager paths probed when ffmpeg is not in a GUI app's minimal PATH.
var FFmpegSearchPaths = []string{
	"/opt/homebrew/bin/ffmpeg",
	"/usr/local/bin/ffmpeg",
	"/opt/local/bin/ffmpeg",
}

// FFprobeSearchPaths are the standard macOS package-manager paths probed when ffprobe is not in PATH.
var FFprobeSearchPaths = []string{
	"/opt/homebrew/bin/ffprobe",
	"/usr/local/bin/ffprobe",
	"/opt/local/bin/ffprobe",
}

// ConfigureFFmpeg locates ffmpeg and ffprobe via lookPath or FFmpegSearchPaths/FFprobeSearchPaths and registers
// them with go.mau.fi/util/ffmpeg.
func ConfigureFFmpeg(stat func(string) (os.FileInfo, error), lookPath func(string) (string, error)) (ffmpegPath, ffprobePath string) {
	if stat == nil {
		stat = os.Stat
	}
	if lookPath == nil {
		lookPath = exec.LookPath
	}
	findBin := func(name string, searchPaths []string) string {
		if p, err := lookPath(name); err == nil && p != "" {
			if fi, serr := stat(p); serr == nil && !fi.IsDir() && fi.Mode()&0o111 != 0 {
				return p
			}
		}
		for _, candidate := range searchPaths {
			if fi, serr := stat(candidate); serr == nil && !fi.IsDir() && fi.Mode()&0o111 != 0 {
				return candidate
			}
		}
		return ""
	}
	ffmpegPath = findBin("ffmpeg", FFmpegSearchPaths)
	ffprobePath = findBin("ffprobe", FFprobeSearchPaths)
	ffmpeg.SetPath(ffmpegPath)
	ffmpeg.SetProbePath(ffprobePath)
	return ffmpegPath, ffprobePath
}

// ErrVoiceTranscodeUnavailable means the room's bridge requires a voice container that differs from the
// input recording and ffmpeg is not available to transcode it.
var ErrVoiceTranscodeUnavailable = errors.New("voice note transcoding requires ffmpeg")

// SendResult is the outcome of sending a voice note or location message.
type SendResult struct {
	EventID string
}

// SendVoiceOpts configures an outgoing voice note.
type SendVoiceOpts struct {
	DurationMS int
	Waveform   []int
	ReplyTo    string
	FFmpegPath string // optional override for tests; defaults to ffmpeg.Supported() + exec.LookPath("ffmpeg")
	Hold       time.Duration
}

// maxSizeForKind returns the byte limit for sending a media attachment of kind and mimeType in a room with features f.
// When the bridge advertises a per-kind MaxSize, that cap (clamped to MaxFileCeiling = 2 GiB) is used; otherwise
// a.maxFile (90 MB default) applies.
func (a *Actions) maxSizeForKind(f Features, kind event.MessageType, mimeType string) int64 {
	var fk *FileKindFeatures
	switch kind {
	case event.CapMsgVoice:
		fk = f.VoiceFeatures
		if fk == nil {
			fk = f.AudioFeatures
		}
	case event.MsgImage:
		if mimeType == "image/gif" && f.GIFFeatures != nil && f.GIFFeatures.MaxSize > 0 {
			fk = f.GIFFeatures
		} else {
			fk = f.ImageFeatures
		}
	case event.MsgVideo:
		fk = f.VideoFeatures
	case event.MsgAudio:
		fk = f.AudioFeatures
	case event.MsgFile:
		fk = f.FileFeatures
	}
	if (fk == nil || fk.MaxSize <= 0) && f.FileFeatures != nil && f.FileFeatures.MaxSize > 0 {
		fk = f.FileFeatures
	}
	if fk != nil && fk.MaxSize > 0 {
		limit := min(fk.MaxSize, MaxFileCeiling)
		if a.maxFile > 0 && a.maxFile != MaxFileBytes && a.maxFile < limit {
			return a.maxFile
		}
		return limit
	}
	return a.maxFile
}

// SendVoice stores and queues a voice note (m.audio + org.matrix.msc3245.voice + org.matrix.msc1767.audio),
// selecting the container from the room's CapMsgVoice FileFeatures rather than by network name.
func (a *Actions) SendVoice(ctx context.Context, roomID, path string, opts SendVoiceOpts) (SendResult, error) {
	if a.m == nil {
		return SendResult{}, errors.New("no media store: cannot send voice notes")
	}
	if err := a.checkHold(opts.Hold); err != nil {
		return SendResult{}, err
	}
	room, h, err := a.sendTarget(ctx, roomID)
	if err != nil {
		return SendResult{}, err
	}
	inFile, err := os.Open(path)
	if err != nil {
		return SendResult{}, err
	}
	defer inFile.Close()
	fi, err := inFile.Stat()
	if err != nil {
		return SendResult{}, err
	}
	if !fi.Mode().IsRegular() {
		return SendResult{}, fmt.Errorf("%s is not a regular file", path)
	}
	if fi.Size() > networkFileCeiling(room.Network) {
		return SendResult{}, ErrTooLarge
	}
	feats, err := a.Features(ctx, roomID)
	if err != nil {
		return SendResult{}, err
	}
	rel, err := a.relation(ctx, roomID, feats, SendOptions{ReplyTo: opts.ReplyTo})
	if err != nil {
		return SendResult{}, err
	}

	head := make([]byte, 512)
	n, err := io.ReadFull(inFile, head)
	if err != nil && !errors.Is(err, io.EOF) && !errors.Is(err, io.ErrUnexpectedEOF) {
		return SendResult{}, err
	}
	ext := strings.ToLower(filepath.Ext(path))
	targetMime, targetExt, needsTranscode, err := selectVoiceContainer(feats, head[:n], ext)
	if err != nil {
		return SendResult{}, err
	}

	srcFile := inFile
	fileName := filepath.Base(path)
	if needsTranscode {
		ffmpegBin, ferr := resolveFFmpeg(opts.FFmpegPath)
		if ferr != nil {
			return SendResult{}, ferr
		}
		tmpOut, terr := transcodeVoice(ctx, ffmpegBin, path, targetExt)
		if terr != nil {
			return SendResult{}, terr
		}
		defer os.Remove(tmpOut)
		tf, oerr := os.Open(tmpOut)
		if oerr != nil {
			return SendResult{}, oerr
		}
		defer tf.Close()
		srcFile = tf
		base := strings.TrimSuffix(fileName, filepath.Ext(fileName))
		if base == "" {
			base = "voice"
		}
		fileName = base + targetExt
	} else if _, err = srcFile.Seek(0, io.SeekStart); err != nil {
		return SendResult{}, err
	}

	if err := refuseBridgeCommand(room.Network, fileName, "a file named"); err != nil {
		return SendResult{}, err
	}

	limit := a.maxSizeForKind(feats, event.CapMsgVoice, targetMime)
	srcStat, err := srcFile.Stat()
	if err != nil {
		return SendResult{}, err
	}
	if srcStat.Size() > limit {
		return SendResult{}, ErrTooLarge
	}

	var size int64
	hash, err := a.m.PutStream(func(w io.Writer) error {
		var cerr error
		size, cerr = io.Copy(w, io.LimitReader(srcFile, limit+1))
		if cerr == nil && size > limit {
			return ErrTooLarge
		}
		return cerr
	})
	if err != nil {
		return SendResult{}, err
	}

	timer, err := a.chatTimer(ctx, roomID)
	if err != nil {
		return SendResult{}, err
	}
	waveform := slices.Clone(opts.Waveform)
	if waveform == nil {
		waveform = []int{}
	}
	content := &event.MessageEventContent{
		MsgType:                 event.MsgAudio,
		Body:                    fileName,
		FileName:                fileName,
		URL:                     ids.ContentURI(hash),
		Info:                    &event.FileInfo{MimeType: targetMime, Size: int(size), Duration: opts.DurationMS},
		MSC3245Voice:            &event.MSC3245Voice{},
		MSC1767Audio:            &event.MSC1767Audio{Duration: opts.DurationMS, Waveform: waveform},
		RelatesTo:               rel,
		BeeperDisappearingTimer: timer,
	}
	eventID, err := a.dispatch(ctx, h, room, content, opts.Hold, Source{Entities: []richtext.Entity{}, ReplyTo: opts.ReplyTo})
	if err != nil {
		return SendResult{}, err
	}
	return SendResult{EventID: eventID}, nil
}

func selectVoiceContainer(feats Features, head []byte, ext string) (targetMime, targetExt string, transcode bool, err error) {
	var mimes []string
	if feats.VoiceFeatures != nil && feats.VoiceFeatures.Supported {
		mimes = feats.VoiceFeatures.MimeTypes
	} else if feats.Source != SourceNone {
		return "", "", false, ErrNotSupported
	} else {
		mimes = []string{"*/*"}
	}

	has := func(m string) bool { return slices.Contains(mimes, m) }
	anyMime := has("*/*")

	isOgg := bytes.HasPrefix(head, []byte("OggS")) || ext == ".ogg" || ext == ".oga" || ext == ".opus"
	isM4A := ext == ".m4a" || ext == ".mp4" || ext == ".aac" || (len(head) >= 8 && string(head[4:8]) == "ftyp")

	switch {
	case isOgg:
		switch {
		case has("audio/ogg; codecs=opus"):
			return "audio/ogg; codecs=opus", ".ogg", false, nil
		case has("audio/ogg") || anyMime:
			return "audio/ogg", ".ogg", false, nil
		case has("audio/mp4"):
			return "audio/mp4", ".m4a", true, nil
		case has("audio/aac"):
			return "audio/aac", ".aac", true, nil
		}
	case isM4A:
		switch {
		case has("audio/mp4") || anyMime:
			return "audio/mp4", ".m4a", false, nil
		case has("audio/aac"):
			return "audio/aac", ".aac", false, nil
		case has("audio/ogg; codecs=opus"):
			return "audio/ogg; codecs=opus", ".ogg", true, nil
		case has("audio/ogg"):
			return "audio/ogg", ".ogg", true, nil
		}
	default:
		if ext == ".mp3" && (has("audio/mpeg") || anyMime) {
			return "audio/mpeg", ".mp3", false, nil
		}
		switch {
		case has("audio/ogg; codecs=opus"):
			return "audio/ogg; codecs=opus", ".ogg", true, nil
		case has("audio/ogg"):
			return "audio/ogg", ".ogg", true, nil
		case has("audio/mp4") || anyMime:
			return "audio/mp4", ".m4a", true, nil
		case has("audio/aac"):
			return "audio/aac", ".aac", true, nil
		}
	}
	return "", "", false, ErrNotSupported
}

func resolveFFmpeg(override string) (string, error) {
	if override != "" {
		fi, err := os.Stat(override)
		if err != nil || fi.IsDir() || fi.Mode()&0o111 == 0 {
			return "", ErrVoiceTranscodeUnavailable
		}
		return override, nil
	}
	ffPath, _ := ConfigureFFmpeg(os.Stat, exec.LookPath)
	if ffPath == "" || !ffmpeg.Supported() {
		return "", ErrVoiceTranscodeUnavailable
	}
	return ffPath, nil
}

func transcodeVoice(ctx context.Context, ffmpegBin, inPath, targetExt string) (string, error) {
	tmp, err := os.CreateTemp("", "courier-voice-*"+targetExt)
	if err != nil {
		return "", err
	}
	outPath := tmp.Name()
	_ = tmp.Close()

	var args []string
	switch targetExt {
	case ".ogg":
		args = []string{"-y", "-i", inPath, "-c:a", "libopus", "-application", "voip", "-f", "ogg", outPath}
	case ".m4a":
		args = []string{"-y", "-i", inPath, "-c:a", "aac", "-f", "ipod", outPath}
	case ".aac":
		args = []string{"-y", "-i", inPath, "-c:a", "aac", "-f", "adts", outPath}
	default:
		_ = os.Remove(outPath)
		return "", ErrNotSupported
	}
	cmd := exec.CommandContext(ctx, ffmpegBin, args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		_ = os.Remove(outPath)
		return "", fmt.Errorf("ffmpeg transcode failed: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return outPath, nil
}

// SendLocation queues an m.location event with GeoURI ("geo:<lat>,<lon>") and body,
// returning ErrNotSupported when the room's features do not support locations.
func (a *Actions) SendLocation(ctx context.Context, roomID string, lat, lon float64, label, replyTo string) (SendResult, error) {
	room, h, err := a.sendTarget(ctx, roomID)
	if err != nil {
		return SendResult{}, err
	}
	feats, err := a.Features(ctx, roomID)
	if err != nil {
		return SendResult{}, err
	}
	if !feats.LocationSupported {
		return SendResult{}, ErrNotSupported
	}
	geoURI := "geo:" + strconv.FormatFloat(lat, 'f', -1, 64) + "," + strconv.FormatFloat(lon, 'f', -1, 64)
	body := strings.TrimSpace(label)
	if body == "" {
		body = geoURI
	}
	if err := refuseBridgeCommand(room.Network, body, "location"); err != nil {
		return SendResult{}, err
	}
	rel, err := a.relation(ctx, roomID, feats, SendOptions{ReplyTo: replyTo})
	if err != nil {
		return SendResult{}, err
	}
	timer, err := a.chatTimer(ctx, roomID)
	if err != nil {
		return SendResult{}, err
	}
	content := &event.MessageEventContent{
		MsgType:                 event.MsgLocation,
		Body:                    body,
		GeoURI:                  geoURI,
		RelatesTo:               rel,
		BeeperDisappearingTimer: timer,
	}
	eventID, err := a.dispatch(ctx, h, room, content, 0, Source{Text: body, Entities: []richtext.Entity{}, ReplyTo: replyTo})
	if err != nil {
		return SendResult{}, err
	}
	return SendResult{EventID: eventID}, nil
}
