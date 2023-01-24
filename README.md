# ffmpeg_cli
`ffmpeg_cli` is a Nim library for interfacing with the FFmpeg CLI to start, observe and terminate encode jobs with an intuitive API.

You can use an argument builder for programmatic CLI argument construction, or pass your own arguments directly.

Media files can be probed with FFprobe, and the probe result can be accessed from a serialized object.

# Threading and Async
The `startFfmpegProcess` proc spawns a process manager thread and then immediately returns an `FfmpegProcess` object with an attached `Future`. No blocking I/O is performed on the caller's thread, and the caller may choose to asynchronously `await` the `Future`, or use `waitFor` to block the thread until the process is complete, or fails.

The `probeFile` proc is **blocking**, and immediately returns the probe result or raises an error. A version that is run in a worker thread is provided for convenience as `probeFileAsync`, but note that spawning the thread that runs it is expensive, and you may be better off running the blocking version on a thread pool.

# Error Handling
Errors returned by FFmpeg and FFprobe are raised as Nim exceptions, and can be handled normally.
When an FFmpeg error occurs, an `FfmpegError` will be raised, and the exact process exit code and error message can be accessed from it.

# FFmpeg Support
This library was tested with FFmpeg version n5.1.2 on ArchLinux, and was compiled with the following flags:

```
--prefix=/usr --disable-debug --disable-static --disable-stripping --enable-amf --enable-avisynth --enable-cuda-llvm --enable-lto --enable-fontconfig --enable-gmp --enable-gnutls --enable-gpl --enable-ladspa --enable-libaom --enable-libass --enable-libbluray --enable-libbs2b --enable-libdav1d --enable-libdrm --enable-libfreetype --enable-libfribidi --enable-libgsm --enable-libiec61883 --enable-libjack --enable-libmfx --enable-libmodplug --enable-libmp3lame --enable-libopencore_amrnb --enable-libopencore_amrwb --enable-libopenjpeg --enable-libopus --enable-libpulse --enable-librav1e --enable-librsvg --enable-libsoxr --enable-libspeex --enable-libsrt --enable-libssh --enable-libsvtav1 --enable-libtheora --enable-libv4l2 --enable-libvidstab --enable-libvmaf --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libx264 --enable-libx265 --enable-libxcb --enable-libxml2 --enable-libxvid --enable-libzimg --enable-nvdec --enable-nvenc --enable-opencl --enable-opengl --enable-shared --enable-version3 --enable-vulkan
```

Arguments generated with `FfmpegJob` should work with any relatively recent FFmpeg build (assuming the correct flags are enabled), and running FFmpeg processes without using the argument builder should work on virtually all FFmpeg versions, regardless of flags.

# Testing
You must have a relatively recent version of FFmpeg installed and available on your system's `PATH` for tests to be run. Output files from testing will be written to your system's temp path.