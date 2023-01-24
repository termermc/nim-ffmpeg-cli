## Module that facilitates execution of FFprobe commands

import std/[osproc, options, strformat, asyncdispatch]
import "."/[definitions]

type FfprobeError* = object of IOError
    ## An error thrown when FFprobe returns an error in its result data

    code*: int
        ## The error code specified in the FFprobe result
    
    resultMessage*: string
        ## The error message specified in the FFprobe result

proc probeFile*(
    ffprobePath: string = "ffprobe",
    inputFile: string,
    showFormat: bool = true,
    showStreams: bool = true,
    showChapters: bool = true
): FfprobeResult =
    ## Probes a file with FFprobe and returns the result.
    ## Raises FfprobeError if FFprobe return an error result.

    # Construct FFprobe CLI arguments
    var args = @[
        "-v", "quiet",
        "-print_format", "json",
        "-show_error"
    ]

    if showFormat:
        args.add("-show_format")
    if showStreams:
        args.add("-show_streams")
    if showChapters:
        args.add("-show_chapters")

    args.add(inputFile)

    let res = execProcess(ffprobePath, args = args, options = {poUsePath}).toFfprobeResult()

    # Check if there was an error
    if res.probeError.isSome:
        let errRes = res.probeError.get
        var err = new FfprobeError
        err.msg = fmt"FFprobe returned an error result with message '{errRes.`string`}' and code {errRes.code}"
        err.code = errRes.code
        err.resultMessage = errRes.`string`

        raise err

    return res

type FfprobeThreadResult = object
    ## Result from an FFprobe executor thread
    
    result: Option[FfprobeResult]
        ## The FFprobe result, if any

    exception: Option[ref FfprobeError]
        ## The exception associated with the result, if any

type FfprobeThreadContext = object
    ## Context passed to an FFmpeg process executor thread
    
    ffprobePath: string
        ## Path to the FFprobe executable on the system

    inputFile: string
        ## Path to the file to probe

    showFormat: bool
        ## Whether to return format info

    showStreams: bool
        ## Whether to return stream info

    showChapters: bool
        ## Whether to return chapter info

    resultChan: Channel[FfprobeThreadResult]
        ## Channel where the thread sends the FFprobe result

proc ffprobeThread(ctx: ref FfprobeThreadContext) =
    ## An FFprobe process executor thread
    
    try:
        let res = probeFile(ctx.ffprobePath, ctx.inputFile, ctx.showFormat, ctx.showStreams, ctx.showChapters)
        ctx.resultChan.send(FfprobeThreadResult(result: some res))
    except:
        var ex: ref FfprobeError
        ex[] = cast[FfprobeError](getCurrentException())
        ctx.resultChan.send(FfprobeThreadResult(exception: some ex))

proc probeFileAsync*(
    ffprobePath: string = "ffprobe",
    inputFile: string,
    showFormat: bool = true,
    showStreams: bool = true,
    showChapters: bool = true
): Future[FfprobeResult] =
    ## Probes a file with FFprobe and returns the result.
    ## Raises FfprobeError if FFprobe return an error result.
    ## This proc runs FFprobe in a new thread, and is provided for convenience only.
    ## Creating the thread where the process is handled is expensive, and therefore you should use the blocking version in a thread pool if it is expected to be called frequently.
    
    var future = newFuture[FfprobeResult]()
    var thread: Thread[ref FfprobeThreadContext]

    # Initialize thread context
    var ctx = new FfprobeThreadContext
    ctx.ffprobePath = ffprobePath
    ctx.inputFile = inputFile
    ctx.showFormat = showFormat
    ctx.showStreams = showStreams
    ctx.showChapters = showChapters
    ctx.resultChan.open()

    createThread(thread, ffprobeThread, ctx)

    proc eventDispatcher() {.async.} =
        ## Checks the thread channel and completes or fails the future when a result is received

        try:
            while thread.running:
                await sleepAsync(10)

                let chanRes = ctx.resultChan.tryRecv()
                if chanRes.dataAvailable:
                    let res = chanRes.msg
                    
                    if res.result.isSome:
                        future.complete(res.result.get)
                    else:
                        future.fail(res.exception.get)
                    
                    break
        finally:
            ctx.resultChan.close()

    asyncCheck eventDispatcher()

    return future
