## Module that provides definitions for various FFmpeg-related data and utilities for working with them.
## While you will likely be importing this module, it does not do any actual work.

import std/[options, sequtils, strutils, strformat, sugar, json, math, times]

# Definitions

type MovFlag* = distinct string
    ## A MOV flag to pass to the H.264 encoder

type Dimension* = distinct range[-2..high(int)]
    ## An FFmpeg dimension.
    ## Used for video scaling and similar options that require dimensions.
    ## Negative numbers are special values, see PreserveAspectRatio and PreserveAspectRatioDivisibleByTwo.

type Dimensions* = object
    ## A pair of width and height FFmpeg dimensions
    
    width*: Dimension
    height*: Dimension

const PreserveAspectRatio* = Dimension(-1)
    ## Special dimension value to tell FFmpeg that the video should have its aspect ratio preserved by ignoring this dimension

const PreserveAspectRatioDivisibleByTwo* = Dimension(-2)
    ## Same as PreserveAspectRatio, but the output video dimensions should be divisible by two.
    ## Necessary for certain codecs like H264.

type BitrateMeasurement* {.pure.} = enum
    ## FFmpeg bitrate measurements

    Bit
        ## 1 bit
    Kilobit
        ## 1,000 bits
    Megabit
        ## 1,000,000 bits

type Bitrate* {.pure.} = object
    ## FFmpeg bitrate value

    case measurement*: BitrateMeasurement
    of Bit:
        bitsPerSecond: int
    of Kilobit:
        kilobitsPerSecond: int
    of Megabit:
        megabitsPerSecond: int

type BitrateFloat* {.pure.} = object
    ## FFmpeg bitrate value represented by a floating point number
    
    case measurement*: BitrateMeasurement
    of Bit:
        bitsPerSecond*: float
    of Kilobit:
        kilobitsPerSecond*: float
    of Megabit:
        megabitsPerSecond*: float

type AudioEncoderKind* {.pure.} = enum
    ## Kinds of FFmpeg audio encoders
    
    LibMp3Lame = "libmp3lame"
        ## libmp3lame
        ## MP3 audio is often found in MP3 audio files and sometimes in MP4 video files.
        ## It was superceded by AAC (aac).

    Aac = "aac"
        ## aac
        ## AAC audio is often found in MP4 video files and M4A audio files.
    
    LibOpus = "libopus"
        ## libopus
        ## Opus audio is often found in OGG audio files and WEBM video files.
    
    LibVorbis = "libvorbis"
        ## libvorbis
        ## Vorbis audio is often found in OGG audio files and OGV video files.
    
    Flac = "flac"
        ## flac
        ## FLAC audio is often found in FLAC audio files.

    CopyStream = "copy"
        ## The stream should be copied from the source instead of being encoded

    Other
        ## Another encoder, specified by a string

type AudioEncoder* = object
    case kind*: AudioEncoderKind
    of AudioEncoderKind.Other:
        name*: string
            ## The encoder name
    else:
        ## No additional options available for this encoder

type H26XPreset* = enum
    ## H264/H265 encoding presets
    
    UltraFast = "ultrafast"
    SuperFast = "superfast"
    VeryFast = "veryfast"
    Faster = "faster"
    Fast = "fast"
    Medium = "medium"
        ## Default preset
    Slow = "slow"
    Slower = "slower"
    VerySlow = "veryslow"
    Placebo = "placebo"
        ## Ignore this as it is not useful

type VideoEncoderKind* {.pure.} = enum
    ## Kinds of FFmpeg video encoders
    
    LibX264 = "libx264"
        ## libx264
        ## H.264 video is often found in MP4 video files and MOV video files.
        ## It was superceded by HEVC (libx265), though as of 2023, adoption of HEVC is relatively low.
    
    LibX265 = "libx265"
        ## libx265
        ## HEVC video is often found in MP4 video files.
        ## As of 2023, adoption of HEVC is relatively low.
    
    LibVpx = "libvpx"
        ## libvpx
        ## VP8 video is often found in WEBM video files.
        ## It was superceded by VP9 (libvpx-vp9).
    
    LibVpxVp9 = "libvpx-vp9"
        ## libvpx-vp9
        ## VP9 video is often found in WEBM video files.
        ## It was superceded by AV1 (), though as of 2023, AV1 encoders are prohibitively slow.
    
    LibAomAv1 = "libaom-av1"
        ## libaom-av1
        ## AV1 video is often found in WEBM video files.
        ## As of 2023, this encoder is incredibly slow and does not scale over multiple threads well.
        ## Using a tool like av1an would be preferred to encoding AV1 with FFmpeg on a machine with many threads.
    
    CopyStream = "copy"
        ## The stream should be copied from the source instead of being encoded

    Other
        ## Another encoder, specified by a string

type VideoEncoder* = object
    case kind*: VideoEncoderKind
    of [LibX264, LibX265]:
        movFlags*: seq[MovFlag]
            ## Additional MOV flags to pass to the encoder.
            ## The preceding "+" on flags will be added by the program, you should not add them yourself.
        
        maxMuxingQueueSize*: Option[int]
            ## A custom maximum muxing queue size.
            ## Useful for videos that have an abnormally large muxing queue size, such as videos that only contain an image and audio.

        profile*: Option[string]
            ## An H264/H265 encoding profile
            
        level*: Option[float]
            ## An H264/H265 encoding level
        
        preset*: Option[H26XPreset]
            ## An H264/H265 encoding preset

    of VideoEncoderKind.Other:
        name*: string
            ## The encoder name

    else:
        ## No additional options available for this encoder
    
    constantRateFactor*: Option[int]
        ## Applies a constant rate factor.
        ## If specified, it will override the video bitrate setting.
        ## Not available for all codecs.
        ## Currently in FFmpeg it is known to be supported by libx264, libx265 and libvpx.
        ## If used for an incompatible codec, it will be ignored.

type EncodeSettingsKind* {.pure.} = enum
    ## Kinds of FFmpeg encoding settings
    
    Audio
        ## Enables settings for primarily audio.
        ## The same settings available for this kind are also available for Video.

    Video
        ## Enables settings for primarily video.
        ## Also includes settings available for Audio.
        ## Suitable for images and other files that FFmpeg treat as video.

type VideoFilterKind* {.pure.} = enum
    ## Kinds of FFmpeg video filters
    
    Scale
        ## Scales the video
    
    Fps
        ## Changes the video's framerate
    
    Format
        ## The video's pixel format.
        ## This filter overrides the default, which as of 2023/01/21 is "yuv420p".
    
    Other
        ## Another filter, specified by a string

type EncoderStrictness* {.pure.} = enum
    ## Levels of encoder strictness
    
    Normal = "normal"
        ## Normal strictness level (default)

    Very = "very"
        ## Strictly conform to an older more strict version of the spec or reference software
    
    Strict = "strict"
        ## Strictly conform to all the things in the spec no matter what consequences
    
    Unofficial = "unofficial"
        ## Allow unofficial extensions
    
    Experimental = "experimental"
        ## Allow non standardized experimental things, experimental (unfinished/work in progress/not well tested) decoders and encoders.
        ## Note: experimental decoders can pose a security risk, do not use this for decoding untrusted input.

type VideoFilter* = object
    ## A video filter
    
    case kind*: VideoFilterKind:
    of Scale:
        scaleDimensions*: Dimensions
            ## The video scaling target dimensions
        
        downscaleOnly*: bool
            ## Whether to only downscale video, and ignore scaling if the source video stream is smaller the the provided scale dimensions
    of Fps:
        framerate*: float
            ## The desired video framerate

        fpsLimitOnly*: bool
            ## Whether to only limit the video's framerate, and ignore changing FPS if the source cideo's FPS is lower than the provided FPS
    of Format:
        pixelFormat*: string
            ## The video's pixel format (e.g. "yuv420p")
    
    of VideoFilterKind.Other:
        filterStr*: string
            ## The raw video filter string

type VideoFilters* = seq[VideoFilter]
    ## A list of video filters

type ContainerFormat* = distinct string
    ## A media container format

type EncodeSettings* = object
    ## FFmpeg encoding settings
    
    extraArgsBeforeInput*: seq[string]
        ## Extra arguments to insert before the -i input argument

    extraArgsAfterInput*: seq[string]
        ## Extra arguments to insert after the -i input argument
    
    extraArgsAfterOutput*: seq[string]
        ## Extra arguments to insert after the output file has been specified

    audioBitrate*: Option[Bitrate]
        ## The audio bitrate to use.
        ## If not specified, FFmpeg will choose a default value.
    
    audioEncoder*: Option[AudioEncoder]
        ## The audio encoder to use.
        ## If not specified, FFmpeg will choose a default value.

    audioSampleRate*: Option[int]
        ## The audio sample rate to use.
        ## If not specified, FFmpeg will choose a default value.

    codecStrictness*: Option[EncoderStrictness]
        ## The level of strictness to use for encoders/decoders.
        ## See "strict" under this section of the FFmpeg docs: http://ffmpeg.org/ffmpeg-codecs.html#Codec-Options

    outputDuration*: Option[Duration]
        ## The maximum duration of the output file
    
    outputEndsAt*: Option[Duration]
        ## The output should end after this duration in the input file.
        ## For example, if the input file is 10 minutes long, then supplying 6 minutes for this parameter will result in the output ending at the six minute mark.
        ## The outputDuration parameter takes precedence over this one.
    
    inputStartsAt*: Option[Duration]
        ## The input should be seeked to this duration before beginning encoding.
        ## If you start at 6 minutes on a 10 minute video, then the output will be 4 minutes long.

    threads*: Option[int]
        ## The number of threads to use for encoding audio/video.
        ## If not specified, FFmpeg will choose a default value based on the encoder used.

    case kind*: EncodeSettingsKind
    of Audio:
        ## All base settings apply to audio, no extra settings are necessary
    of Video:
        videoBitrate*: Option[Bitrate]
            ## The video bitrate to use.
            ## If not specified, FFmpeg will choose a default value.
        
        videoEncoder*: Option[VideoEncoder]
            ## The video encoder to use.
            ## If not specified, FFmpeg will choose a default value.
        
        videoFilters*: seq[VideoFilter]
            ## Video filters to apply
        
        outputFrameCount*: Option[int]
            ## The number of video frames to output.
            ## Useful for taking screenshots of video.

    containerFormat*: Option[ContainerFormat]
        ## The output contain format.
        ## If none, FFmpeg will choose one based on the extension of outputFile.

type FfmpegJob* = object
    ## An FFmpeg encoding job

    inputFile*: string
        ## The path to the input file
    
    settings*: EncodeSettings
        ## Encode settings to use

    outputFile*: string
        ## The path to the output file

type ResultKind* = enum
    ## Kinds of FFmpeg/FFprobe results
    
    Success
    Error

type FfprobeErrorData* = object
    ## An FFprobe error.
    ## Not to be confused with 
    
    code*: int
        ## The error code
    string*: string
        ## The error message string

type FfprobeDisposition* = object
    ## A stream's disposition in an FFprobe result
    
    default*: uint8
        ## 1 if the default track
    dub*: uint8
        ## 1 if a dub track
    original*: uint8
        ## 1 if the original track
    comment*: uint8
        ## 1 if a comment track
    lyrics*: uint8
        ## 1 if a lyrics track
    karaoke*: uint8
        ## 1 if a karaoke track
    forced*: uint8
        ## 1 if a forced track
    hearing_impaired*: uint8
        ## 1 if a track for the hearing impaired
    visual_impaired*: uint8
        ## 1 if a track for the visually impaired
    clean_effects*: uint8
        ## 1 if a clean effects track (meaning not entirely understood)
    attached_pic*: uint8
        ## 1 if an attached picture track
    timed_thumbnails*: uint8
        ## 1 if a timed thumbnails track (perhaps like the preview thumbnails you get when scrolling over a YouTube video's seek bar)
    captions*: uint8
        ## 1 if a captions track
    descriptions*: uint8
        ## 1 if a descriptions track
    metadata*: uint8
        ## 1 if a metadata track
    dependent*: uint8
        ## 1 if a dependent track (unclear meaning)
    still_image*: uint
        ## 1 if a still image track

type FfprobeStreamTags* = object
    ## A stream's tags in an FFprobe result
    
    language*: Option[string]
        ## The track's language code (usually represented using a 3 letter language code, e.g.: "eng")
    handler_name*: Option[string]
        ## The name of the handler which produced the track
    vendor_id*: Option[string]
        ## The ID of the vendor which produced the track
    encoder*: Option[string]
        ## The name of the encoder responsible for creating the stream
    creation_time*: Option[string]
        ## The date (often ISO-formatted, but it may use other formats) when the media was created
    comment*: Option[string]
        ## The comment attached to the stream

type FfprobeStreamCodecType* = enum
    ## A stream type in an FFprobe result
    
    Video = "video"
    Audio = "audio"
    Subtitle = "subtitle"
    Data = "data"

type Bool* = enum
    ## True or false.
    ## Necessary because FFprobe encodes some true/false values as strings.
    
    True = "true"
    False = "false"

type FfprobeStream* = object
    ## A stream in an FFprobe result

    index*: int
        ## The stream index
    codec_name*: Option[string]
        ## The codec's name
    codec_long_name*: Option[string]
        ## The codec's long (detailed) name
    profile*: Option[string]
        ## The codec profile
    codec_type*: FfprobeStreamCodecType
        ## The type of codec (video, audio, subtitle, etc)
    codec_tag_string*: string
        ## The codec tag (technical name)
    codec_tag*: string
        ## The codec tag ID
    sample_fmt*: Option[string]
        ## The audio sample format (not present if codec_type is not Audio)
    sample_rate*: Option[string]
        ## A string representation of an integer showing the audio sample rate (not present if codec_type is not Audio)
    channels*: Option[int]
        ## The audio track's channel count (not present if codec_type is not Audio)
    channel_layout*: Option[string]
        ## The audio track's channel layout (e.g. "stereo", "mono", "5.1") (not present if codec_type is not "audio")
    bits_per_sample*: Option[int]
        ## Bits per audio sample (might not be accurate, may just be 0) (not present if codec_type is not Audio)
    width*: Option[int]
        ## The video stream width (also available for images) (not present if codec_type is not Video)
    height*: Option[int]
        ## The stream height (also available for images) (not present if codec_type is not Video)
    coded_width*: Option[int]
        ## The stream's coded width (shouldn't vary from "width") (not present if codec_type is not Video)
    coded_height*: Option[int]
        ## The stream's coded height (shouldn't vary from "height") (not present if codec_type is not Video)
    closed_captions*: Option[uint8]
        ## Set to 1 if closed captions are present in stream... I think (not present if codec_type is not Video)
    has_b_frames*: Option[uint8]
        ## Set to 1 if the stream has b-frames... I think (not present if codec_type is not Video)
    sample_aspect_ratio*: Option[string]
        ## The sample aspect ratio (you probably want "display_aspect_ratio") (not present if codec_type is not Video)
    display_aspect_ratio*: Option[string]
        ## The display (real) aspect ratio (e.g. "16:9") (not present if codec_type is not Video)
    pix_fmt*: Option[string]
        ## The pixel format used (not present if codec_type is not Video)
    level*: Option[int]
        ## Unknown (not present if codec_type is not Video)
    color_range*: Option[string]
        ## The color range used (e.g. "tv") (not present if codec_type is not Video)
    color_space*: Option[string]
        ## The color space used (not present if codec_type is not Video)
    color_transfer*: Option[string]
        ## The color transfer used (not present if codec_type is not Video)
    color_primaries*: Option[string]
        ## The color primaries used (not present if codec_type is not Video)
    chroma_location*: Option[string]
        ## The chroma location (not present if codec_type is not Video)
    refs*: Option[int]
        ## Unknown (not present if codec_type is not Video)
    is_avc*: Option[Bool]
        ## Whether the stream is AVC (not present if codec_type is not Video)
    nal_length_size*: Option[string]
        ## Unknown string representing a number (not present if codec_type is not Video)
    r_frame_rate*: string
        ## Odd formatting of the frame rate, possibly "real frame rate"? (e.g. "30/1")
    avg_frame_rate*: string
        ## Odd formatting of the average frame rate (e.g. "30/1")
    time_base*: string
        ## The division equation to use for converting integer representations of timestamps into seconds (e.g. "1/30000" turns 80632552 into 2687.751733 seconds)
    start_pts*: Option[int]
        ## Unknown
    start_time*: Option[string]
        ## A string representation of a floating point integer showing the start time in seconds
    duration_ts*: Option[int]
        ## The stream's duration in integer timestamp format (defined by time_base)
    duration*: Option[string]
        ## A string representation of a floating point integer showing the stream duration in seconds
    bit_rate*: Option[string]
        ## The string representation of an integer showing the stream bit rate (not present on lossless formats such as FLAC)
    bits_per_raw_sample*: Option[string]
        ## A string representation of an integer showing the bits per raw sample (not present if codec_type is not Video)
    nb_frames*: Option[string]
        ## A string representation of an integer showing the total number of frames in the stream
    disposition*: FfprobeDisposition
        ## The stream's disposition
    tags*: Option[FfprobeStreamTags]
        ## The stream's tags

type FfprobeChapterTags* = object
    ## A chapter's tags in an FFprobe result
    
    title*: string
        ## The chapter title

type FfprobeChapter* = object
    ## A chapter in an FFprobe result
    
    id*: int
        ## The chapter ID
    time_base*: string
        ## The division equation to use for converting integer representations of timestamps into seconds (e.g. "1/30000" turns 80632552 into 2687.751733 seconds)
    start*: int
        ## When the chapter starts in integer timestamp format (defined by time_base)
    start_time*: string
        ## The string representation of a floating point integer showing when the chapter starts in seconds
    `end`*: int
        ## When the chapter end in integer timestamp format (defined by time_base)
    end_time*: string
        ## The string representation of a floating point integer showing when the chapter ends in seconds
    tags*: FfprobeChapterTags
        ## The chapter's tags

type FfprobeFormatTags* = object
    ## A format's tags in an FFprobe result
    
    major_brand*: Option[string]
        ## Not clear, probably the media type brand, but not sure
    minor_version*: Option[string]
        ## The brand version perhaps, but not sure
    compatible_brands*: Option[string]
        ## The brands that are compatible with the referenced brands perhaps, but not sure
    title*: Option[string]
        ## The media's title (song metadata uses an all uppercase version)
    artist*: Option[string]
        ## The media artist (song metadata uses an all uppercase version)
    date*: Option[string]
        ## The media's creation date, seems to be in YYYYMMDD format (song metadata uses an all uppercase version)
    encoder*: Option[string]
        ## The name of the encoder responsible for encoding the media
    comment*: Option[string]
        ## The comment attached to the file
    description*: Option[string]
        ## The description attached to the file
    creation_time*: Option[string]
        ## The ISO-formatted date (although it may use other formats) when the media was created
    ALBUM*: Option[string]
        ## The album (only present in audio files)
    album_artist*: Option[string]
        ## The album arist (only present in audio files)
    ALBUMARTISTSORT*: Option[string]
        ## The album artist name used for sorting probably (only present in audio files)
    ARTIST*: Option[string]
        ## The song artist (only present in audio files)
    DATE*: Option[string]
        ## The date when the song was created (no particular format, often the year) (only present in audio files)
    disc*: Option[string]
        ## The string representation of an integer showing the song's disc number (only present in audio files)
    DISCTOTAL*: Option[string]
        ## The string representation of an integer showing the total number of discs comprising the album the song is in (only present in audio files)
    ISRC*: Option[string]
        ## The song's International Standard Recording Code
    GENRE*: Option[string]
        ## The song's genre (only present in audio files)
    TITLE*: Option[string]
        ## The song's title (only present in audio files)
    track*: Option[string]
        ## The string representation of an integer showing the song's track number (only present in audio files)
    TRACKTOTAL*: Option[string]
        ## The string representation of an integer showing the total number of tracks in the album the song is in (only present in audio files)
    YEAR*: Option[string]
        ## The string representation of an integer showing the year the song was created (only present in audio files)
    BPM*: Option[string]
        ## The string representation of an integer showing the song's BPM (only present in audio files)
    PUBLISHER*: Option[string]
        ## The song's publisher (only present in audio files)

type FfprobeFormat* = object
    ## A format in an FFprobe result

    filename*: string
        ## The path of the probed file (as specified in the input file argument)
    nb_streams*: int
        ## The total number of streams present
    nb_programs*: int
        ## The total number of programs present
    format_name*: string
        ## The name of the format (a comma separated list of applicable file extensions for the format)
    format_long_name*: string
        ## The long (detailed) name of the format
    start_time*: Option[string]
        ## The string representation of a floating point integer showing the file's starting time
    duration*: Option[string]
        ## The string representation of a floating point integer showing the file's duration in seconds (seems to be a non-accurate, rounded version of the real duration)
    size*: string
        ## The string representation of a long integer showing the file's size in bytes
    bit_rate*: Option[string]
        ## The string representation of a long integer showing the file's stated bitrate (may vary between streams, probably applies to just video if a video file)
    probe_score*: int
        ## Probably the coverage of the probe, looks to be 0 to 100
    tags*: Option[FfprobeFormatTags]
        ## The format's tags

type FfprobeResult* = object
    ## An FFprobe result

    streams*: Option[seq[FfprobeStream]]
        ## The probed file's streams (showStreams must be true)        
    chapters*: Option[seq[FfprobeChapter]]
        ## The probed file's chapters (showChapters must be true)
    format*: Option[FfprobeFormat]
        ## The probed file's format data (showFormat must be true)
    error: Option[FfprobeErrorData]
        ## The error that occurred when trying to probe the file, or none if the probe was successful.
        ## This property is not exposed to consumers, and should be internally access using the probeError function.

type FfmpegEncodeProgress* = object
    ## An FFmpeg encode progress report
    
    frame*: Option[int]
        ## The current frame, or none if not applicable

    fps*: Option[float]
        ## The current frames per second of the encoding process, or none if not applicable
    
    bitrate*: BitrateFloat
        ## The current encoding bitrate

    currentOutputSize*: uint64
        ## The output file's current size in bytes
    
    currentTimeMicroseconds*: uint64
        ## The timestamp of the current encoding progress on encoding in microseconds (1/1,000,000 of a second)
    
    duplicatedFrames*: Option[int]
        ## The total number of duplicated frames currently, or none if not applicable
    
    droppedFrames*: Option[int]
        ## The total number of dropped frames currently, or none if not applicable

    speed*: float
        ## The current encoding speed as a multiplier of the speed of the input.
        ## For example, if a 30 FPS video is being encoded at 90 FPS, then this value will be 2.5.

# Data helpers

func `$`*(this: Bitrate): string =
    ## Returns the textual representation of the bitrate that will be passed to FFmpeg
    
    case this.measurement:
    of Bit:
        $this.bitsPerSecond
    of Kilobit:
        $this.kilobitsPerSecond & 'k'
    of Megabit:
        $this.megabitsPerSecond & 'm'

func `$`*(this: MovFlag): string = '+' & string(this)
    ## Returns the MOV flag with a preceding "+"

func `$`*(this: Dimension): string =
    $int(this)

func `$`*(this: AudioEncoder|VideoEncoder): string =
    ## Returns the name of an encoder

    if this.kind == (when this is AudioEncoder: AudioEncoderKind.Other else: VideoEncoderKind.Other):
        this.name
    else:
        $this.kind

func `$`*(this: VideoFilter): string =
    ## Returns an FFmpeg video filter parameter
    
    case this.kind:
    of Scale:
        proc procDim(this: VideoFilter, dim: Dimension, name: string): string {.inline.} =
            if dim.int >= 0 and this.downscaleOnly:
                fmt"min({dim},{name})"
            else:
                $dim

        let dims = this.scaleDimensions
        let widthStr = procDim(this, dims.width, "iw")
        let heightStr = procDim(this, dims.height, "ih")
        fmt"scale={widthStr}:{heightStr}"

    of Fps:
        if this.fpsLimitOnly:
            fmt"fps=min({this.framerate},source_fps)"
        else:
            fmt"fps={this.framerate}"

    of Format:
        fmt"format={this.pixelFormat}"
    
    of VideoFilterKind.Other:
        this.filterStr

func `$`*(this: VideoFilters): string =
    ## Returns an FFmpeg parameter-ready string list of video filters
    
    const replacements = {
        "\\": "\\\\",
        ",": "\\,"
    }

    seq[VideoFilter](this)
        .map(vf => ($vf).multiReplace(replacements))
        .join(",")

func `$`*(this: ContainerFormat): string =
    ## Returns the name of a container format
    
    string(this)

func dimensions*(
    width: int|Dimension = PreserveAspectRatioDivisibleByTwo,
    height: int|Dimension = PreserveAspectRatioDivisibleByTwo
): Dimensions {.inline.} =
    ## Convenient abstraction over using the Dimensions constructor.
    ## Omitted arguments default to PreserveAspectRatioDivisibleByTwo.

    Dimensions(
        width: when width is int: Dimension(width) else: width,
        height: when height is int: Dimension(height) else: height
    )

func bps*(num: int): Bitrate {.inline.} =
    ## Creates an instance of Bitrate for the specified bits per second
    
    Bitrate(measurement: Bit, bitsPerSecond: num)

func kbps*(num: int): Bitrate {.inline.} =
    ## Creates an instance of Bitrate for the specified kilobits (1,000 bits) per second
    
    Bitrate(measurement: Kilobit, kilobitsPerSecond: num)

func mbps*(num: int): Bitrate {.inline.} =
    ## Creates an instance of Bitrate for the specified megabits (1,000,000 bits) per second
    
    Bitrate(measurement: Megabit, megabitsPerSecond: num)

func bps*(num: float): BitrateFloat {.inline.} =
    ## Creates an instance of Bitrate for the specified bits per second
    
    BitrateFloat(measurement: Bit, bitsPerSecond: num)

func kbps*(num: float): BitrateFloat {.inline.} =
    ## Creates an instance of Bitrate for the specified kilobits (1,000 bits) per second
    
    BitrateFloat(measurement: Kilobit, kilobitsPerSecond: num)

func mbps*(num: float): BitrateFloat {.inline.} =
    ## Creates an instance of Bitrate for the specified megabits (1,000,000 bits) per second
    
    BitrateFloat(measurement: Megabit, megabitsPerSecond: num)

func encoder*(kind: AudioEncoderKind|VideoEncoderKind): AudioEncoder|VideoEncoder {.inline.} =
    ## Creates an instance of AudioEncoder or VideoEncoder for the specified encoder kind

    when kind is AudioEncoderKind:
        AudioEncoder(kind: kind)
    else:
        VideoEncoder(kind: kind)

func format*(name: string): ContainerFormat {.inline.} =
    ## Convenient abstraction to create ContainerFormat instances
    
    ContainerFormat(name)

func copyAudioStream*(): AudioEncoder {.inline.} =
    ## Convenient abstraction over using the AudioEncoder constructor with the CopyStream kind

    AudioEncoder(kind: AudioEncoderKind.CopyStream) 

func copyVideoStream*(): VideoEncoder {.inline.} =
    ## Convenient abstraction over using the VideoEncoder constructor with the CopyStream kind

    VideoEncoder(kind: VideoEncoderKind.CopyStream)

func toBool*(b: Bool): bool {.inline.} =
    ## Converts a Bool enum to an actual bool
    
    return b == Bool.True

proc toFfprobeResult*(json: string): FfprobeResult =
    ## Unmarshals a JSON string into an FfprobeResult object
    
    parseJson(json).to(FfprobeResult)

func currentTimeMilliseconds*(this: FfmpegEncodeProgress): int {.inline.} =
    ## Convenience function for getting currentTimeMicroseconds, but in milliseconds.
    ## The value is divided by 1,000 and floored.
    
    floor(this.currentTimeMicroseconds.int / 1_000).int

func currentTimeSeconds*(this: FfmpegEncodeProgress): int {.inline.} =
    ## Convenience function for getting currentTimeMicroseconds, but in seconds.
    ## The vlaue is divided by 1,000,000 and floored.
    
    float(this.currentTimeMicroseconds.int / 1_000_000).int

func scale*(width: int|Dimension, height: int|Dimension, downscaleOnly: bool): VideoFilter {.inline.} =
    ## Convenient abstraction over using the VideoFilter constructor with the Scale kind
    
    VideoFilter(
        kind: VideoFilterKind.Scale,
        scaleDimensions: dimensions(width, height),
        downscaleOnly: downscaleOnly
    )

func downscale*(width: int|Dimension, height: int|Dimension): VideoFilter {.inline.} =
    ## Same as scale, but specifies true for downscaleOnly argument
    
    scale(width, height, true)

func fps*(framerate: float, limitOnly: bool): VideoFilter {.inline.} =
    ## Convenient abstraction over using the VideoFilter constructor with the Fps kind
    
    VideoFilter(
        kind: VideoFilterKind.Fps,
        framerate: framerate,
        fpsLimitOnly: limitOnly
    )

func limitFps*(framerate: float): VideoFilter {.inline.} =
    ## Same as fps, but specifies true for limitOnly
    
    fps(framerate, true)

func pixelFormat*(format: string): VideoFilter {.inline.} =
    ## Convienct abstraction over using VideoFilter constructor with the Format kind
    
    VideoFilter(
        kind: VideoFilterKind.Format,
        pixelFormat: format
    )

func toFfmpegDurationStr*(this: Duration): string {.inline.} =
    ## Returns an FFmpeg duration string for the provided Duration
    
    fmt"{this.inNanoseconds.int / 1_000_000_000}s"

func probeError*(this: FfprobeResult): Option[FfprobeErrorData] {.inline.} =
    ## Returns the error that occurred during a probe, or none.
    ## For internal use only, will always return none if called on the output of probeFile in the ffprobe module.
    
    this.error

proc toFfmpegArgs*(job: FfmpegJob): seq[string] {.raises: ValueError.} =
    ## Generates FFmpeg CLI arguments for the provided FfmpegJob object.
    ## Raises ValueError if some any options in the FfmpegJob object are invalid (such as applying filters on video when the encoder is set to "copy").

    template ifAndNotCopy(cond: bool, useCopy: bool, msg: string, body: untyped) =
        if cond:
            if useCopy:
                raise newException(ValueError, msg)
            else:
                body

    let enc = job.settings
    var args = newSeq[string]()

    args.add(enc.extraArgsBeforeInput)
    args.add(["-i", job.inputFile])
    args.add(enc.extraArgsAfterInput)

    if enc.audioEncoder.isSome:
        args.add(["-c:a", $enc.audioEncoder.get])
    
    if enc.codecStrictness.isSome:
        args.add(["-strict", $enc.codecStrictness.get])

    if enc.threads.isSome:
        args.add(["-threads", $enc.threads.get])

    if enc.outputDuration.isSome:
        args.add(["-t", enc.outputDuration.get.toFfmpegDurationStr()])
    
    if enc.outputEndsAt.isSome:
        args.add(["-t", enc.outputEndsAt.get.toFfmpegDurationStr()])

    if enc.inputStartsAt.isSome:
        args.add(["-ss", enc.inputStartsAt.get.toFfmpegDurationStr()])

    let audUseCopy = enc.audioEncoder.isSome and enc.audioEncoder.get.kind == AudioEncoderKind.CopyStream

    ifAndNotCopy(enc.audioBitrate.isSome, audUseCopy, "Cannot specify bitrate for audio stream that is being copied"):
        args.add(["-b:a", $enc.audioBitrate.get])
    
    ifAndNotCopy(enc.audioSampleRate.isSome, audUseCopy, "Cannot specify sample rate for audio stream that is being copied"):
        args.add(["-ar", $enc.audioSampleRate.get])

    if enc.kind == EncodeSettingsKind.Video:
        if enc.videoEncoder.isSome:
            args.add(["-c:v", $enc.videoEncoder.get])
        
        let vidUseCopy = enc.videoEncoder.isSome and enc.videoEncoder.get.kind == VideoEncoderKind.CopyStream

        if enc.outputFrameCount.isSome:
            args.add(["-frames:v", $enc.outputFrameCount.get])

        ifAndNotCopy(enc.videoBitrate.isSome, vidUseCopy, "Cannot specify bitrate for video stream that is being copied"):
            args.add(["-b:v", $enc.videoBitrate.get])
        
        ifAndNotCopy(enc.videoFilters.len > 0, vidUseCopy, "Cannot specify video filters for video stream that is being copied"):
            args.add(["-vf", $enc.videoFilters])
        
        if enc.videoEncoder.isSome:
            # Apply encoder-specific settings
            let vidEnc = enc.videoEncoder.get
            case vidEnc.kind:
            of [LibX264, LibX265]:
                ifAndNotCopy(vidEnc.movFlags.len > 0, vidUseCopy, "Cannot specify MOV flags for video stream that is being copied"):
                    var flags = ""
                    for flag in vidEnc.movFlags:
                        flags &= $flag
                    args.add(["-movflags", flags])
                
                ifAndNotCopy(vidEnc.maxMuxingQueueSize.isSome, vidUseCopy, "Cannot specify max muxing queue size for video stream that is being copied"):
                    args.add(["-max_muxing_queue_size", $vidEnc.maxMuxingQueueSize.get])
                
                ifAndNotCopy(vidEnc.profile.isSome, vidUseCopy, "Cannot specify H264/H265 encoding profile for video stream that is being copied"):
                    args.add(["-profile:v", vidEnc.profile.get])
                
                ifAndNotCopy(vidEnc.level.isSome, vidUseCopy, "Cannot specify H264/H265 encoding level for video stream that is being copied"):
                    args.add(["-level", $vidEnc.preset.get])

                ifAndNotCopy(vidEnc.preset.isSome, vidUseCopy, "Cannot specify H264/H265 encoding preset for video stream that is being copied"):
                    args.add(["-preset", $vidEnc.preset.get])
            else:
                ## No encoder-specific arguments to apply
            
            # Evaluate whether the encoder support CRF
            if vidEnc.kind == LibX264 or vidEnc.kind == LibX265 or vidEnc.kind == LibVpx:
                if vidEnc.constantRateFactor.isSome:
                    args.add(["-crf", $vidEnc.constantRateFactor.get])

    args.add(job.outputFile)

    args.add(enc.extraArgsAfterOutput)

    if enc.containerFormat.isSome:
        args.add(["-f", $enc.containerFormat.get])

    return args
