#!/usr/bin/env swift

import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 4 else {
    fputs("usage: create-demo-gif.swift output.gif frame1.png frame2.png ...\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let frames = CommandLine.arguments.dropFirst(2).compactMap { path -> CGImage? in
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

guard frames.count == CommandLine.arguments.count - 2,
      let destination = CGImageDestinationCreateWithURL(
        output as CFURL,
        UTType.gif.identifier as CFString,
        frames.count,
        nil
      )
else {
    fputs("could not read every frame or create the GIF destination\n", stderr)
    exit(1)
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)

for frame in frames {
    CGImageDestinationAddImage(destination, frame, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 2.2]
    ] as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("could not finalize GIF\n", stderr)
    exit(1)
}
