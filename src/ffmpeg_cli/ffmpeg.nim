## Module that facilitates execution of FFmpeg jobs.
## 
## In most cases, you will also need to import the "definitions" module to get full use out of this module.
## 
## See below for some examples on how to use this module.

runnableExamples "--threads:on":
    # Convert a video to WEBM

    import std/[os, asyncdispatch]
    import "."/[ffmpeg, definitions]

    try:
        let filePath = "input.mp4"

        waitFor startFfmpegProcess(job = FfmpegJob(
            inputFile: filePath,
            outputFile: "output.webm"
        )).future
    except:
        echo "Something went wrong: " & getCurrentExceptionMsg()

runnableExamples "--threads:on":
    # Downscale a video to 720p WEBM

    import std/[os, asyncdispatch]
    import "."/[ffmpeg, definitions]

    let filePath = "input.mp4"

    try:
        waitFor startFfmpegProcess(job = FfmpegJob(
            inputFile: filePath,
            outputFile: "output.webm",
            settings: EncodeSettings(
                kind: EncodeSettingsKind.Video,
                videoFilters: @[downscale(PreserveAspectRatio, 720)] # Note: you should use PreserveAspectRatioDivisibleByTwo when encoding to MP4
            )
        )).future
    except:
        echo "Something went wrong: " & getCurrentExceptionMsg()

runnableExamples "--threads:on":
    # Print the progress percentage of an encode job

    import std/[os, asyncdispatch, math, strutils, options]
    import "."/[ffmpeg, ffprobe, definitions]

    let filePath = "input.mp4"

    try:
        # First probe the file to get its total duration, then convert it to microseconds
        let probeRes = probeFile(inputFile = filePath)
        let totalDuration = parseFloat(probeRes.format.get.duration.get) * 1_000_000

        # Create listener proc
        proc progressListener(prog: FfmpegEncodeProgress) =
            echo $floor((prog.currentTimeMicroseconds.int / totalDuration.int) * 100) & '%'
        
        # Start process
        var process = startFfmpegProcess(job = FfmpegJob(
            inputFile: filePath,
            outputFile: "output.webm"
        ))

        # Add listener to be called when progress is reported
        process.addProgressListener(progressListener)

        # Block thread until the process is complete.
        # This does not inhibit the progress listener from being called because progress listeners are called on this thread during execution.
        waitFor process.future
    except:
        echo "Something went wrong: " & getCurrentExceptionMsg()


import std/[osproc, asyncfutures, asyncdispatch, options, os, streams, strutils, nre, strformat]
import "."/[definitions]

type FfmpegEncodeProgressListener* = proc (progress: FfmpegEncodeProgress)
    ## An FFmpeg processing progress listener callback.
    ## Note that listeners should not contain any heavy/long-running logic, otherwise they will delay the process manager and block other listeners.

type FfmpegProcess* = ref object
    ## A running, finished or failed FFmpeg processing job.
    
    # Private values
    progressListeners: seq[FfmpegEncodeProgressListener]
        ## Currently registered progress listeners

    probeResult*: Option[FfprobeResult]
        ## The result of the probe performed before the process, or none if no probe was performed

    # Public values
    job*: FfmpegJob
        ## The job that is/was being processed
    
    future*: Future[void]
        ## A Future that will be completed if the process was successful, or failed if it failed.
        ## All listeners will be called before this Future is completed.
    
    lastProgress*: Option[FfmpegEncodeProgress]
        ## The last progress report received, or none if nothing has been received yet
    
    shouldCancel*: bool
        ## Whether the process should be canceled.
        ## Used internally only.

type FfmpegError* = object of IOError
    ## An error thrown when an FFmpeg process fails

    exitCode*: int
        ## The exit code from FFmpeg
    
    errorOutput*: Option[string]
        ## The error output from FFmpeg, if any
    
    args*: seq[string]
        ## The arguments passed to the FFmpeg CLI

proc addProgressListener*(this: FfmpegProcess, listener: FfmpegEncodeProgressListener) =
    ## Adds a new process progress listener
    
    this.progressListeners.add(listener)

func removeProgressListener*(this: FfmpegProcess, listener: FfmpegEncodeProgressListener) =
    ## Removes an existing progress listener
    
    for (i, progList) in this.progressListeners.pairs:
        if listener == progList:
            this.progressListeners.del(i)
            return

func clearProgressListeners*(this: FfmpegProcess) =
    ## Clears all existing progress listeners
    
    this.progressListeners.setLen(0)

func cancel*(this: FfmpegProcess) =
    ## Cancels a currently processing FFmpeg job.
    ## The output file will not be deleted.
    ## The FFmpeg process will not be terminated immediately. Instead, a message will be sent to the FFmpeg manager thread to terminate it.
    
    this.shouldCancel = true

func finished*(this: FfmpegProcess): bool {.inline.} =
    ## Returns whether the processing job is finished.
    ## Will be true even if the process failed.
    ## Use .failed to check whether the process failed, or alternatively .succeeded to check whether the process succeeded.
    
    this.future.finished

func failed*(this: FfmpegProcess): bool {.inline.} =
    ## Returns whether the proessing job failed.
    ## Will be false if the process hasn't finished yet.
    ## Use .finished to check whether it is finished before using this function.
    
    this.future.finished and this.future.failed

type FfmpegThreadProgress = object
    ## Progress message from an FFmpeg manager thread
    
    encodeProgress: Option[FfmpegEncodeProgress]
        ## The FFmpeg encode progress, if any

    finished: bool
        ## Whether the encode is finished

    exception: Option[ref FfmpegError]
        ## The exception associated with the progress, if any

type FfmpegThreadContext = object
    ## Context passed to an FFmpeg process executor thread
    
    ffmpegPath: string
        ## Path to the FFmpeg executable on the system

    args: seq[string]
        ## FFmpeg CLI arguments

    progressChan: Channel[FfmpegThreadProgress]
        ## Channel where the thread sends FFmpeg progress data
    
    canceled: bool
        ## Whether the process should be terminated

proc ffmpegThread(ctx: ref FfmpegThreadContext) {.thread.} =
    ## An FFmpeg process executor thread

    try:
        let progBitratePattern = re"((?:\d+\.)?\d+)(\w+)?\/s"
            ## Regex pattern for the bitrate value in FFmpeg progress output

        var ffmpegProc = startProcess(ctx.ffmpegPath, args = ctx.args, options = {poUsePath})

        proc terminate() =
            # Kill process
            ffmpegProc.kill()
            ffmpegProc.close()

            # Construct error for termination
            var ex = new FfmpegError
            ex.msg = fmt"FFmpeg process was terminated"
            ex.exitCode = -1
            ex.errorOutput = none[string]()
            ex.args = ctx.args
            
            # Send error progress for termination
            ctx.progressChan.send(FfmpegThreadProgress(
                encodeProgress: none[FfmpegEncodeProgress](),
                finished: true,
                exception: some(ex)
            ))

        var curProg = FfmpegEncodeProgress()
        var ln: string
        var receivedEndProg = false
        while true:
            sleep(10)

            # First check if the context was marked as canceled
            if ctx.canceled:
                terminate()

                # Nothing else to do; end thread
                return

            if ffmpegProc.outputStream.readLine(ln):
                let eqIdx = ln.find('=')
                if eqIdx < 0:
                    continue

                # Parse the line
                let key = ln.substr(0, eqIdx - 1)
                let val = ln.substr(eqIdx + 1).strip()

                # Ignore values of "N/A"
                if val != "N/A":
                    # Determine what to do with the key
                    case key:
                    of "frame":
                        curProg.frame = some(parseInt(val))
                    of "fps":
                        curProg.fps = some(parseFloat(val))
                    of "bitrate":
                        # Parse bitrate
                        let matchRes = val.match(progBitratePattern)
                        if matchRes.isSome:
                            let captures = matchRes.get.captures
                            let num = parseFloat(captures[0])
                            let measurement = captures[1]

                            curProg.bitrate =
                                case measurement:
                                of ["kbits", "kbps"]:
                                    kbps(num)
                                of ["mbits", "mbps"]:
                                    mbps(num)
                                else:
                                    bps(num)
                            
                    of "total_size":
                        curProg.currentOutputSize = parseBiggestUInt(val)
                    of ["out_time_us", "out_time_ms"]:
                        curProg.currentTimeMicroseconds = parseBiggestUInt(val)
                    of "dup_frames":
                        curProg.duplicatedFrames = some(parseInt(val))
                    of "drop_frames":
                        curProg.droppedFrames = some(parseInt(val))
                    of "speed":
                        curProg.speed = parseFloat(val.substr(0, val.len - 2))
                    of "progress":
                        # Send progress
                        let ended = val == "end"
                        ctx.progressChan.send(FfmpegThreadProgress(
                            encodeProgress: some(curProg),
                            finished: ended,
                            exception: none[ref FfmpegError]()
                        ))

                        if ended:
                            receivedEndProg = true
                            break
                        else:
                            curProg = FfmpegEncodeProgress()
            elif not ffmpegProc.running:
                break
        
        # Terminate before waiting for exit if the process is canceled
        if ctx.canceled:
            terminate()
            return

        # Wait for exit before handling result
        let code = ffmpegProc.waitForExit()

        # If the process ended without receiving a progress ended report, then something went wrong
        if not receivedEndProg:
            var ex = new FfmpegError
            ex.args = ctx.args

            # Figure out what error needs to be sent based on the error code and error output
            if code > 0:
                let errOut = ffmpegProc.peekableErrorStream.peekStr(1024).strip()

                ex.msg = fmt"FFmpeg exited with code {code}"
                ex.exitCode = code
                ex.errorOutput = if errOut.len > 0: some(errOut) else: none[string]()
            else:
                ex.msg = fmt"FFmpeg exited with code {code} but no encode progress was recieved during the process lifetime"
                ex.exitCode = code
                ex.errorOutput = none[string]()
            
            # Send error progress
            ctx.progressChan.send(FfmpegThreadProgress(
                encodeProgress: none[FfmpegEncodeProgress](),
                finished: true,
                exception: some(ex)
            ))
    except:
        # Catch all errors in thread and return them
        var ex = new FfmpegError
        ex.msg = fmt"Error occurred in FFmpeg process manager thread"
        ex.exitCode = -1
        ex.args = ctx.args
        ex.parent = getCurrentException()

        ctx.progressChan.send(FfmpegThreadProgress(
            encodeProgress: none[FfmpegEncodeProgress](),
            finished: true,
            exception: some(ex)
        ))

proc startFfmpegProcess*(
    ffmpegPath: string = "ffmpeg",
    args: seq[string],
    timeoutMs: int = 0
): FfmpegProcess =
    ## Starts an FFmpeg process with the specified CLI arguments.
    ## Use the overload that takes FfmpegJob to use a more user-friendly interface.
    ## The process can optionally be terminated in the number of milliseconds specified by timeoutMs, or 0 to never time out.
    ## This proc will add certain extra arguments in addition to the ones provided explicitly.
    ## Do not provide any of the following arguments:
    ##  -hide_banner
    ##  -v
    ##  -progress
    ##  -y

    var process = new FfmpegProcess
    process.future = newFuture[void]()
    var thread: Thread[ref FfmpegThreadContext]

    # Initialize thread context
    var ctx = new FfmpegThreadContext
    ctx.ffmpegPath = ffmpegPath
    var ctxArgs = @["-hide_banner", "-v", "error"]
    ctxArgs.add(args)
    ctxArgs.add(["-progress", "pipe:1", "-y"])
    ctx.args = ctxArgs
    ctx.progressChan.open()

    createThread(thread, ffmpegThread, ctx)

    proc timeout() {.async.} =
        await sleepAsync(timeoutMs)
        ctx.canceled = true
    
    if timeoutMs > 0:
        asyncCheck timeout()

    proc eventDispatcher() {.async.} =
        ## Checks the thread channel and dispatches events to listeners
        
        try:
            var lastProg: Option[FfmpegThreadProgress]

            var chanRes: tuple[dataAvailable: bool, msg: FfmpegThreadProgress]

            proc tryRecvProg(): bool =
                chanRes = ctx.progressChan.tryRecv()
                return chanRes.dataAvailable

            # Loop while there is still data to be read from the progress channel OR the thread is running
            while tryRecvProg() or thread.running:
                await sleepAsync(10)

                # Tell the thread to cancel the process if signified
                if process.shouldCancel:
                    ctx.canceled = true

                if chanRes.dataAvailable:
                    let prog = chanRes.msg
                    lastProg = some(prog)

                    # Dispatch event to listeners if there was process progress
                    if prog.encodeProgress.isSome:
                        for listener in process.progressListeners:
                            listener(prog.encodeProgress.get)
                    
                    if prog.finished:
                        break
            
            if lastProg.isSome:
                let prog = lastProg.get

                if prog.exception.isSome:
                    process.future.fail(prog.exception.get)
                else:
                    process.future.complete()
            else:
                process.future.fail(newException(IOError, "FFmpeg process executor thread terminated, but no input was received from it"))
        finally:
            ctx.progressChan.close()

    asyncCheck eventDispatcher()

    return process

proc startFfmpegProcess*(
    ffmpegPath: string = "ffmpeg",
    job: FfmpegJob,
    timeoutMs: int = 0
): FfmpegProcess =
    ## Starts an FFmpeg process with the specified job.
    ## Use the overload that takes a seq of args to use a more fine-grained interface.
    ## The process can optionally be terminated in the number of milliseconds specified by timeoutMs, or 0 to never time out.

    startFfmpegProcess(ffmpegPath, job.toFfmpegArgs(), timeoutMs)
