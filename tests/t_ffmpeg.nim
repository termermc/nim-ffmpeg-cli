import std/[unittest, os, macros, options, asyncdispatch]

import ffmpeg_cli/[ffmpeg, ffprobe, definitions]

suite "ffmpeg":
    setup:
        let mediaPath = getProjectPath() / "tests" / "media"
        let tmpPath = getTempDir() / "ffmpeg_cli_test_output"
        removeDir(tmpPath)
        createDir(tmpPath)

        proc doJob(inputFilename: string, outputFilename: string, settings: EncodeSettings = EncodeSettings(kind: EncodeSettingsKind.Video)): FfmpegProcess =
            startFfmpegProcess(
                job = FfmpegJob(
                    inputFile: mediaPath / inputFilename,
                    outputFile: tmpPath / outputFilename,
                    settings: settings
                )
            )

    teardown:
        removeDir(tmpPath)

    test "Converts video to mp4":
        var jobProc = doJob("alex_jones_scream.webm", "out.mp4")

        waitFor jobProc.future
        check true

    test "Raises error when trying to convert nonexistent file":
        try:
            var jobProc = doJob("doesnt_exist.mp4", "out.mp4")
            waitFor jobProc.future
            check false
        except:
            check true

    test "Reports progress":
        var progVals = newSeq[FfmpegEncodeProgress]()

        var jobProc = doJob("charles_manson_chika_dance.webm", "out.mp4")
        jobProc.addProgressListener(proc (prog: FfmpegEncodeProgress) = progVals.add(prog))
        waitFor jobProc.future

        assert(progVals.len > 0, "At least one progress value was received by the progress listener")

    test "Resizes image":
        var jobProc = doJob("cat_thumbs_up.jpg", "out.jpg", EncodeSettings(
            kind: EncodeSettingsKind.Video,
            videoFilters: @[downscale(PreserveAspectRatioDivisibleByTwo, 100)]
        ))
        waitFor jobProc.future

        let probeRes = probeFile(inputPath = tmpPath / "out.jpg")
        let stream = probeRes.streams.get[0]

        assert(stream.width.get == 100 and stream.height.get == 100, "Image is resized to 100x100")

    test "Converts audio to opus in ogg container":
        var jobProc = doJob("scott_brownish_melody_by_tas.mp3", "out.ogg", EncodeSettings(
            kind: EncodeSettingsKind.Audio,
            audioEncoder: some AudioEncoder(kind: LibOpus),
            containerFormat: some format("ogg")
        ))
        waitFor jobProc.future

        check true

    test "Converts video to MP4 using complex H264 options":
        var jobProc = doJob("charles_manson_chika_dance.webm", "out.mp4", EncodeSettings(
            kind: EncodeSettingsKind.Video,
            audioEncoder: some AudioEncoder(kind: Aac),
            audioSampleRate: some 44100,
            audioBitrate: some 128.kbps,
            videoEncoder: some VideoEncoder(
                kind: LibX264,
                constantRateFactor: some(25),
                movFlags: @[MovFlag("faststart")],
                maxMuxingQueueSize: some(102400)
            ),
            videoFilters: @[
                downscale(PreserveAspectRatioDivisibleByTwo, 480),
                limitFps(30),
                pixelFormat("yuv420p")
            ],
            codecStrictness: some Unofficial
        ))
        waitFor jobProc.future

        check true

    test "Conversion overwrites existing file":
        waitFor doJob("alex_jones_scream.webm", "out.mp4").future
        let size1 = getFileSize(tmpPath / "out.mp4")

        waitFor doJob("charles_manson_chika_dance.webm", "out.mp4").future
        let size2 = getFileSize(tmpPath / "out.mp4")

        assert(size1 != size2, "File was proven to be overwritten because the new file size does not match")
