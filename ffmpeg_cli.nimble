# Package

version       = "0.1.0"
author        = "."
description   = "Library for interfacing with the FFmpeg CLI to start, observe and terminate encode jobs with an intuitive API"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.10"

task docgen, "Generate library documentation":
    const srcDir = "src/ffmpeg_cli"

    echo "Generating documentation..."

    let files = srcDir.listFiles()
    for file in files:
        echo file
        if strutils.endsWith(file, ".nim"):
            echo "Generating docs for "&file
            exec "nimble doc "&file
