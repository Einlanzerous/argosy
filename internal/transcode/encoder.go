package transcode

import "fmt"

// videoEncoder builds the backend-specific portions of a transcode command: any
// global hardware init placed before the input, the scale-filter expression for
// a target height, and the video codec + rate-control flags. There is one
// implementation per backend; software (libx264) is always the floor.
//
// The hardware backends (qsv/vaapi/nvenc) plug in here in follow-up work
// (ARGY-30 QSV, ARGY-61 VAAPI/NVENC) — the build path in ffmpeg.go asks the
// encoder for these pieces instead of hardcoding libx264, so adding a backend is
// a new implementation, not a rewrite of the argument builder.
type videoEncoder interface {
	// name reports the backend, matching the Encoder* constants.
	name() string
	// globalArgs returns args placed before "-i" (hwaccel device init + decode
	// acceleration). Software returns nil.
	globalArgs() []string
	// scale returns a filtergraph scale expression to height, e.g.
	// "scale=-2:720" (software) or "scale_qsv=w=-2:h=720" (QSV).
	scale(height int) string
	// videoCodec returns "-c:v <enc>" plus the shared encode flags (preset, GOP).
	videoCodec() []string
	// rateControl returns the per-output rate-control flags. idx < 0 is the
	// single-output case (no stream specifier); idx >= 0 targets ladder output i.
	rateControl(idx int, r rung) []string
}

// encoderFor resolves a backend name to its implementation. Anything not yet
// implemented falls back to software, so selecting an un-wired backend degrades
// gracefully rather than failing.
func encoderFor(name string) videoEncoder {
	switch name {
	case EncoderQSV:
		return qsvEncoder{}
	// case EncoderVAAPI, EncoderNVENC: ...    // ARGY-61
	default:
		return softwareEncoder{}
	}
}

// isHardwareEncoder reports whether name is a GPU backend (anything but
// software) — used to decide whether a startup failure should retry on software.
func isHardwareEncoder(name string) bool {
	return name != "" && name != EncoderSoftware
}

// ResolvedEncoder reports the backend that will actually be used for name —
// useful for truthful logging when a selected backend isn't wired up yet and
// silently resolves to software.
func ResolvedEncoder(name string) string { return encoderFor(name).name() }

// softwareEncoder is the libx264 path: no hardware init, software scaling, and
// CBR-ish VBV rate control per rung. It is the universal fallback.
type softwareEncoder struct{}

func (softwareEncoder) name() string { return EncoderSoftware }

func (softwareEncoder) globalArgs() []string { return nil }

func (softwareEncoder) scale(height int) string { return fmt.Sprintf("scale=-2:%d", height) }

func (softwareEncoder) videoCodec() []string {
	return []string{
		"-c:v", "libx264", "-preset", "veryfast",
		"-g", "48", "-keyint_min", "48", "-sc_threshold", "0",
	}
}

func (softwareEncoder) rateControl(idx int, r rung) []string { return vbrRateControl(idx, r) }

// vbrRateControl emits VBV-constrained VBR flags for output idx (idx < 0 = the
// single output, no stream specifier). libx264 and h264_qsv both accept this
// shape, so the backends share it.
func vbrRateControl(idx int, r rung) []string {
	if idx < 0 {
		return []string{"-b:v", r.videoBitrate, "-maxrate", r.maxRate, "-bufsize", r.bufSize}
	}
	return []string{
		fmt.Sprintf("-b:v:%d", idx), r.videoBitrate,
		fmt.Sprintf("-maxrate:v:%d", idx), r.maxRate,
		fmt.Sprintf("-bufsize:v:%d", idx), r.bufSize,
	}
}

// qsvEncoder is the Intel Quick Sync path. It uses the software pipeline (CPU
// decode + scale) but encodes with h264_qsv, which uploads frames to the iGPU
// internally — an "encode-only" model. On this hardware that proved both faster
// and far more robust than a full-GPU pipeline: libmfx's GPU scaler (scale_qsv)
// is unimplemented, and the multi-rung GPU ladder hit surface-submission limits,
// whereas encode-only ran the 1080p ladder ~73% faster than libx264 and a single
// 720p rung at ~16x realtime. So QSV differs from software only in the codec.
//
// If the GPU/codec can't be used at all, the session layer (Manager.run) retries
// on software, so this never hard-fails playback.
type qsvEncoder struct{ softwareEncoder }

func (qsvEncoder) name() string { return EncoderQSV }

func (qsvEncoder) scale(height int) string {
	// h264_qsv only accepts 8-bit nv12, so convert after scaling. Without this a
	// 10-bit source (e.g. HEVC Main 10 from a 4K rip) fails with "Current pixel
	// format is unsupported"; for 8-bit sources the conversion is a cheap repack.
	return fmt.Sprintf("scale=-2:%d,format=nv12", height)
}

func (qsvEncoder) videoCodec() []string {
	return []string{"-c:v", "h264_qsv", "-preset", "veryfast", "-g", "48"}
}
