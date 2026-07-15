#!/usr/bin/swift
import Foundation
import Speech

let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: macos-speech-transcribe.swift <video-or-audio-path> [locale] [timeout-seconds]")
    exit(1)
}

let path = args[1]
let locale = args.count > 2 ? args[2] : "pt_BR"
let timeoutSeconds = args.count > 3 ? (Int(args[3]) ?? 180) : 180

let status = SFSpeechRecognizer.authorizationStatus()
if status != .authorized {
    print("ERROR: Speech recognition not authorized (status \(status.rawValue)). Enable in System Settings > Privacy & Security > Speech Recognition.")
    exit(1)
}

let recognizer: SFSpeechRecognizer
if let specific = SFSpeechRecognizer(locale: Locale(identifier: locale)) {
    recognizer = specific
} else {
    print("WARNING: Locale-specific recognizer unavailable for \(locale). Falling back to default recognizer.")
    guard let fallback = SFSpeechRecognizer() else {
        print("ERROR: No speech recognizer available")
        exit(1)
    }
    recognizer = fallback
}

if !recognizer.isAvailable {
    print("ERROR: Speech recognizer is not available")
    exit(1)
}

let url = URL(fileURLWithPath: path)
let request = SFSpeechURLRecognitionRequest(url: url)
request.shouldReportPartialResults = true
if #available(macOS 10.15, *) {
    request.requiresOnDeviceRecognition = false
}

var finished = false
var latest = ""
var errorText = ""

let task = recognizer.recognitionTask(with: request) { result, error in
    if let result = result {
        latest = result.bestTranscription.formattedString
        if result.isFinal {
            finished = true
        }
    }
    if let error = error {
        errorText = error.localizedDescription
        finished = true
    }
}

let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
while !finished && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
}

if !finished {
    task.cancel()
    print("ERROR: Transcription timed out after \(timeoutSeconds) seconds")
    exit(1)
}

if !errorText.isEmpty {
    print("ERROR: \(errorText)")
    exit(1)
}

print("TRANSCRIPT_BEGIN")
print(latest)
print("TRANSCRIPT_END")
