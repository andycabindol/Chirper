import Foundation
import AVFoundation

struct AudioProcessingService {
    // MARK: - Decode

    static func decodeAnyAudioToPCMBuffer(url: URL) throws -> AVAudioPCMBuffer {
        // First try AVAudioFile (covers most formats)
        do {
            let file = try AVAudioFile(forReading: url)
            let processingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: file.fileFormat.sampleRate,
                channels: file.fileFormat.channelCount,
                interleaved: false
            )!

            let frameCount = UInt32(file.length)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: frameCount
            ) else {
                throw NSError(
                    domain: "Chirper",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to allocate buffer"]
                )
            }

            try file.read(into: buffer)
            return makeMono(buffer: buffer)
        } catch {
            // Fallback with AVAssetReader if needed
            return try decodeWithAssetReader(url: url)
        }
    }

    private static func decodeWithAssetReader(url: URL) throws -> AVAudioPCMBuffer {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)

        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No audio track"]
            )
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: track.naturalTimeScale,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var samples: [Float] = []
        var sampleRate: Double = 44_100
        var channelCount: UInt32 = 2

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                sampleRate = asbd.pointee.mSampleRate
                channelCount = asbd.pointee.mChannelsPerFrame
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { ptr in
                let addr = ptr.baseAddress!
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: addr)
            }

            let count = length / MemoryLayout<Float>.size
            data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let floatPtr = ptr.bindMemory(to: Float.self)
                samples.append(
                    contentsOf: UnsafeBufferPointer(start: floatPtr.baseAddress, count: count)
                )
            }

            _ = numSamples // not used directly, but loop ensures full buffer read
            CMSampleBufferInvalidate(sampleBuffer)
        }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(samples.count / Int(channelCount))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate buffer"]
            )
        }

        buffer.frameLength = frameCount
        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(channelCount))
        for ch in 0..<Int(channelCount) {
            let dst = channels[ch]
            for i in 0..<Int(frameCount) {
                dst[i] = samples[i * Int(channelCount) + ch]
            }
        }

        return makeMono(buffer: buffer)
    }

    private static func makeMono(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 1 else { return buffer }

        let frameLength = Int(buffer.frameLength)
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let monoBuffer = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: buffer.frameCapacity
        ) else {
            return buffer
        }
        monoBuffer.frameLength = buffer.frameLength

        let src = buffer.floatChannelData!
        let dst = monoBuffer.floatChannelData![0]

        for i in 0..<frameLength {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += src[ch][i]
            }
            dst[i] = sum / Float(channelCount)
        }

        return monoBuffer
    }

    // MARK: - Resample

    static func resampleToTarget(
        buffer: AVAudioPCMBuffer,
        targetSampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        if buffer.format.sampleRate == targetSampleRate,
           buffer.format.commonFormat == .pcmFormatFloat32,
           buffer.format.channelCount == 1 {
            return buffer
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: buffer.format, to: targetFormat)!
        let ratio = targetSampleRate / buffer.format.sampleRate
        let newFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)

        guard let newBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: newFrameCapacity
        ) else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Resample buffer allocation failed"]
            )
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: newBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            throw error
        }

        return newBuffer
    }

    // MARK: - Helpers

    static func floatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData else { return [] }
        let mono = channelData[0]
        return Array(UnsafeBufferPointer(start: mono, count: frameLength))
    }

    static func duration(of buffer: AVAudioPCMBuffer) -> TimeInterval {
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    // MARK: - Detections → segments

    static func segments(
        from detections: [Detection],
        audioDuration: TimeInterval,
        sampleRate: Double,
        confidenceThreshold: Double,
        paddingSeconds: TimeInterval,
        mergeGapSeconds: TimeInterval,
        minClipSeconds: TimeInterval
    ) -> [String: [Segment]] {
        let filtered = detections.filter { $0.confidence >= confidenceThreshold }

        // Group by species
        var bySpecies: [String: [Detection]] = [:]
        for det in filtered {
            bySpecies[det.species, default: []].append(det)
        }

        var result: [String: [Segment]] = [:]

        for (species, dets) in bySpecies {
            let sorted = dets.sorted { $0.start < $1.start }
            var merged: [Detection] = []

            for det in sorted {
                if var last = merged.last {
                    let gap = det.start - last.end
                    if gap <= mergeGapSeconds {
                        // merge
                        last.end = max(last.end, det.end)
                        last.confidence = max(last.confidence, det.confidence)
                        merged[merged.count - 1] = last
                    } else {
                        merged.append(det)
                    }
                } else {
                    merged.append(det)
                }
            }

            var speciesSegments: [Segment] = []
            for det in merged {
                // Use very small fixed pre-padding so clips start just before the call,
                // and let the slider control the tail padding only.
                let prePad: TimeInterval = 0.05
                let postPad: TimeInterval = paddingSeconds

                var start = det.start - prePad
                var end = det.end + postPad
                start = max(0, start)
                end = min(audioDuration, end)

                guard end - start >= minClipSeconds else { continue }

                let startSample = Int(start * sampleRate)
                let endSample = Int(end * sampleRate)
                speciesSegments.append(
                    Segment(
                        startSample: startSample,
                        endSample: endSample,
                        confidence: det.confidence
                    )
                )
            }
            result[species] = speciesSegments
        }

        return result
    }

    // MARK: - Splicing

    static func spliceSegments(
        _ segments: [Segment],
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        let sortedSegments = segments.sorted { $0.startSample < $1.startSample }
        guard !sortedSegments.isEmpty else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No segments"]
            )
        }

        let totalSamples = sortedSegments.reduce(0) {
            $0 + ($1.endSample - $1.startSample)
        }
        let format = buffer.format

        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(totalSamples)
        ) else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Splice allocation failed"]
            )
        }

        outBuffer.frameLength = AVAudioFrameCount(totalSamples)
        guard let src = buffer.floatChannelData,
              let dst = outBuffer.floatChannelData else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing channel data"]
            )
        }

        let srcMono = src[0]
        let dstMono = dst[0]

        var writeIndex = 0
        for seg in sortedSegments {
            let length = seg.endSample - seg.startSample
            guard length > 0 else { continue }
            for i in 0..<length {
                dstMono[writeIndex + i] = srcMono[seg.startSample + i]
            }
            writeIndex += length
        }

        return outBuffer
    }
}


