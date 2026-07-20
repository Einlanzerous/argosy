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
	// videoCodec returns "-c:v <enc>" plus the shared encode flags (preset, GOP)
	// for the requested output codec (CodecH264 or CodecHEVC).
	videoCodec(codec string) []string
	// rateControl returns the per-output rate-control flags. idx < 0 is the
	// single-output case (no stream specifier); idx >= 0 targets ladder output i.
	rateControl(idx int, r rung) []string
}

// Output video codecs. H.264 is the universal baseline; HEVC is used for
// >1080p (true 4K) output to capable clients, where H.264's bitrate is
// impractical. See ffmpegEncoder for the per-backend ffmpeg encoder names.
const (
	CodecH264 = "h264"
	CodecHEVC = "hevc"
)

// ffmpegEncoder maps (backend, output codec) to the concrete ffmpeg encoder.
// Adding a backend or codec is a table entry, not a new code path.
var ffmpegEncoder = map[string]map[string]string{
	EncoderSoftware: {CodecH264: "libx264", CodecHEVC: "libx265"},
	EncoderQSV:      {CodecH264: "h264_qsv", CodecHEVC: "hevc_qsv"},
	EncoderVAAPI:    {CodecH264: "h264_vaapi", CodecHEVC: "hevc_vaapi"},
	EncoderNVENC:    {CodecH264: "h264_nvenc", CodecHEVC: "hevc_nvenc"},
}

// resolveCodec normalizes an output codec, defaulting to H.264.
func resolveCodec(c string) string {
	if c == CodecHEVC {
		return CodecHEVC
	}
	return CodecH264
}

// encoderFor resolves a backend name to its implementation. Anything not yet
// implemented falls back to software, so selecting an un-wired backend degrades
// gracefully rather than failing.
func encoderFor(name string) videoEncoder {
	switch name {
	case EncoderQSV:
		return qsvEncoder{}
	case EncoderVAAPI:
		return vaapiEncoder{}
	case EncoderNVENC:
		return nvencEncoder{}
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

func (softwareEncoder) scale(height int) string {
	// format=nv12 forces 8-bit 4:2:0 output. Without it libx264/libx265 preserve
	// the source bit depth, so a 10-bit source (HEVC Main 10) would re-encode to
	// 10-bit again — defeating the reason we transcode it: browser/mobile clients
	// software-decode 10-bit and stutter, but hardware-decode 8-bit reliably (see
	// planPlayback's high-bit-depth gate). The GPU backends already pin nv12; this
	// keeps the software fallback consistent. Cheap repack for 8-bit sources.
	return fmt.Sprintf("scale=-2:%d,format=nv12", height)
}

func (softwareEncoder) videoCodec(codec string) []string {
	codec = resolveCodec(codec)
	args := []string{
		"-c:v", ffmpegEncoder[EncoderSoftware][codec], "-preset", "veryfast",
		"-g", "48", "-keyint_min", "48", "-sc_threshold", "0",
	}
	if codec == CodecHEVC {
		// hvc1 tag so the fMP4 sample entry is one MSE/Safari recognize.
		args = append(args, "-tag:v", "hvc1")
	}
	return args
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

func (qsvEncoder) videoCodec(codec string) []string {
	codec = resolveCodec(codec)
	args := []string{"-c:v", ffmpegEncoder[EncoderQSV][codec], "-preset", "veryfast", "-g", "48"}
	if codec == CodecHEVC {
		args = append(args, "-tag:v", "hvc1")
	}
	return args
}

// VAAPIDevice is the DRM render node VAAPI initializes. renderD128 is the Intel
// iGPU (also exposes VAAPI); renderD129 is the discrete AMD card. Overridable so
// a host can target a specific GPU; a config/env knob can set it in main.
var VAAPIDevice = "/dev/dri/renderD128"

// vaapiEncoder is the VAAPI path (Intel/AMD). Unlike QSV — which uploads frames
// to the GPU internally — VAAPI needs the frames explicitly uploaded to a GPU
// surface (format=nv12,hwupload) after a CPU scale, with the device initialized
// before the input via -vaapi_device. Verified on this box (renderD128):
// h264_vaapi + hevc_vaapi, single-rung and multi-rung ladder.
type vaapiEncoder struct{ softwareEncoder }

func (vaapiEncoder) name() string { return EncoderVAAPI }

func (vaapiEncoder) globalArgs() []string { return []string{"-vaapi_device", VAAPIDevice} }

func (vaapiEncoder) scale(height int) string {
	// CPU scale to nv12, then upload to a VAAPI surface for the GPU encoder.
	return fmt.Sprintf("scale=-2:%d,format=nv12,hwupload", height)
}

func (vaapiEncoder) videoCodec(codec string) []string {
	codec = resolveCodec(codec)
	args := []string{"-c:v", ffmpegEncoder[EncoderVAAPI][codec], "-g", "48"}
	if codec == CodecHEVC {
		args = append(args, "-tag:v", "hvc1")
	}
	return args
}

// nvencEncoder is the NVIDIA NVENC path. Like QSV it's encode-only (NVENC
// accepts system-memory frames and uploads them internally), so it differs from
// software only in the codec + scale-format. NOTE: not verified on this box (no
// NVIDIA GPU); it stays inert unless Probe detects an NVIDIA device, so shipping
// it is safe. Recipe follows the standard h264_nvenc/hevc_nvenc encode-only form.
type nvencEncoder struct{ softwareEncoder }

func (nvencEncoder) name() string { return EncoderNVENC }

func (nvencEncoder) scale(height int) string {
	// nv12 so 10-bit sources downconvert for the 8-bit NVENC encoders.
	return fmt.Sprintf("scale=-2:%d,format=nv12", height)
}

func (nvencEncoder) videoCodec(codec string) []string {
	codec = resolveCodec(codec)
	// NVENC presets are p1..p7 (p4 ~= medium quality/speed).
	args := []string{"-c:v", ffmpegEncoder[EncoderNVENC][codec], "-preset", "p4", "-g", "48"}
	if codec == CodecHEVC {
		args = append(args, "-tag:v", "hvc1")
	}
	return args
}
