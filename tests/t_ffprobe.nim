import std/[unittest, os, macros, options, strutils, asyncdispatch]

import ffmpeg_cli/[ffprobe, definitions]

suite "ffprobe":
    setup:
        let mediaPath = getProjectPath() / "tests" / "media"

    test "Probes video":
        let res = probeFile(
            inputFile = mediaPath / "charles_manson_chika_dance.webm"
        )

        # Check that the file title is probed properly
        assert(res.format.get.tags.get.title.get == "1285116814981461", "The embedded title tag is detected")

        # Check the number of streams
        assert(res.streams.get.len == 2, "Both streams are detected")

        # Check the file duration
        let duration = parseFloat(res.format.get.duration.get)
        assert(duration == 19.873, "The video duration is accurately detected")
    
    test "Probes image":
        let res = probeFile(
            inputFile = mediaPath / "cat_thumbs_up.jpg"
        )

        # Check the number of streams
        assert(res.streams.get.len == 1, "The image stream is detected")

        # Check dimensions
        let stream = res.streams.get[0]
        assert(stream.width.get == 500 and stream.height.get == 500, "Image dimensions are accurately detected")
    
    test "Probes audio":
        let res = probeFile(
            inputFile = mediaPath / "scott_brownish_melody_by_tas.mp3"
        )

        # Check the number of streams
        assert(res.streams.get.len == 1, "The audio stream is detected")

        # Check the file duration
        let duration = parseFloat(res.format.get.duration.get)
        assert(duration == 11.64, "The audio duration is accurately detected")
    
    test "Raises error when trying to probe nonexistent file":
        try:
            echo probeFile(
                inputFile = mediaPath / "doesnt_exist.mp4"
            )
            check false
        except:
            check true

    test "Async convenience method works":
        discard waitFor probeFileAsync(
            inputFile = mediaPath / "cat_thumbs_up.jpg"
        )
        check true
