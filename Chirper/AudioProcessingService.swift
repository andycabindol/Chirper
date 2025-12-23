import Foundation
import AVFoundation

struct AudioProcessingService {
    // MARK: - Duration
    
    static func duration(of buffer: AVAudioPCMBuffer) -> TimeInterval {
        let sampleRate = buffer.format.sampleRate
        return Double(buffer.frameLength) / sampleRate
    }
    
    // MARK: - Sample Extraction
    
    static func floatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }
        
        let frameLength = Int(buffer.frameLength)
        let channel = channelData[0] // Use first channel (mono)
        
        return Array(UnsafeBufferPointer(start: channel, count: frameLength))
    }
    
    // MARK: - Decoding
    
    static func decodeAnyAudioToPCMBuffer(url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Chirper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate buffer"])
        }
        
        try file.read(into: buffer)
        return buffer
    }
    
    // MARK: - Resampling
    
    static func resampleToTarget(
        buffer: AVAudioPCMBuffer,
        targetSampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        let sourceFormat = buffer.format
        let sourceRate = sourceFormat.sampleRate
        
        guard sourceRate != targetSampleRate else {
            return buffer
        }
        
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: sourceFormat.channelCount,
            interleaved: false
        )!
        
        let ratio = targetSampleRate / sourceRate
        let targetFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
            throw NSError(domain: "Chirper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Resampling setup failed"])
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            throw error
        }
        
        return outputBuffer
    }
    
    // MARK: - Detections → segments
    
    // Temporary structure to track species with segments during processing
    private struct SegmentedDetection {
        let species: String
        let start: TimeInterval
        let end: TimeInterval
        let confidence: Double
    }
    
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
        
        // Group by species and merge within each species
        var bySpecies: [String: [Detection]] = [:]
        for det in filtered {
            bySpecies[det.species, default: []].append(det)
        }
        
        var mergedDetections: [SegmentedDetection] = []
        
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
            
            // Convert to SegmentedDetection for cross-species processing
            for det in merged {
                mergedDetections.append(
                    SegmentedDetection(
                        species: species,
                        start: det.start,
                        end: det.end,
                        confidence: det.confidence
                    )
                )
            }
        }
        
        // Sort all detections across all species by start time
        mergedDetections.sort { $0.start < $1.start }
        
        // Now apply padding intelligently based on adjacent segments
        let targetPostPad: TimeInterval = 0.25
        var adjustedSegments: [(species: String, start: TimeInterval, end: TimeInterval, confidence: Double)] = []
        
        for (index, det) in mergedDetections.enumerated() {
            // Adjust detection times: start is 0.75s later, end is 0.75s earlier
            // This compensates for ML model inaccuracy in detection boundaries
            let adjustedStart = det.start + 0.75
            let adjustedEnd = det.end - 0.75
            
            // Ensure adjusted times are valid
            guard adjustedEnd > adjustedStart else { continue }
            
            // No padding before the call starts
            var start = adjustedStart
            var end = adjustedEnd
            
            // Check if there's a next segment that would overlap
            let nextSegmentStart: TimeInterval?
            if index + 1 < mergedDetections.count {
                // Also adjust the next segment's start time for comparison
                nextSegmentStart = mergedDetections[index + 1].start + 0.75
            } else {
                nextSegmentStart = nil
            }
            
            // Apply post-padding, but reduce it if next segment is too close
            if let nextStart = nextSegmentStart {
                let gap = nextStart - end
                // If gap is less than target padding, use the gap (or 0 if negative)
                let postPad = min(targetPostPad, max(0, gap - 0.01)) // 0.01s buffer to avoid exact overlap
                end = adjustedEnd + postPad
            } else {
                // No next segment, apply full padding
                end = adjustedEnd + targetPostPad
            }
            
            start = max(0, start)
            end = min(audioDuration, end)
            
            guard end - start >= minClipSeconds else { continue }
            
            adjustedSegments.append(
                (species: det.species, start: start, end: end, confidence: det.confidence)
            )
        }
        
        // Group back by species
        var result: [String: [Segment]] = [:]
        for adjSeg in adjustedSegments {
            let startSample = Int(adjSeg.start * sampleRate)
            let endSample = Int(adjSeg.end * sampleRate)
            
            result[adjSeg.species, default: []].append(
                Segment(
                    startSample: startSample,
                    endSample: endSample,
                    confidence: adjSeg.confidence
                )
            )
        }
        
        return result
    }
    
    // MARK: - Splicing
    
    static func extractSegment(
        segment: Segment,
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        return try extractSegment(
            segment: segment,
            from: buffer,
            sampleRate: sampleRate,
            trimStart: 0,
            trimEnd: 0
        )
    }
    
    static func extractSegment(
        segment: Segment,
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        trimStart: TimeInterval,
        trimEnd: TimeInterval
    ) throws -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "Chirper", code: -1, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }
        
        // Calculate base segment boundaries
        let baseStartSample = max(0, min(segment.startSample, Int(buffer.frameLength)))
        let baseEndSample = max(baseStartSample, min(segment.endSample, Int(buffer.frameLength)))
        
        // Apply trim offsets (trimStart adds to start, trimEnd subtracts from end)
        let trimStartSamples = Int(trimStart * sampleRate)
        let trimEndSamples = Int(trimEnd * sampleRate)
        
        let startSample = max(baseStartSample, min(baseStartSample + trimStartSamples, baseEndSample))
        let endSample = max(startSample, min(baseEndSample - trimEndSamples, baseEndSample))
        let frameCount = endSample - startSample
        
        guard frameCount > 0 else {
            throw NSError(domain: "Chirper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid segment"])
        }
        
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: buffer.format.channelCount, interleaved: false)!
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw NSError(domain: "Chirper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }
        
        outputBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        for channel in 0..<Int(buffer.format.channelCount) {
            let inputChannel = channelData[channel]
            let outputChannel = outputBuffer.floatChannelData![channel]
            
            memcpy(outputChannel, inputChannel.advanced(by: startSample), frameCount * MemoryLayout<Float>.size)
        }
        
        return outputBuffer
    }
    
    static func concatenateBuffers(
        _ buffers: [AVAudioPCMBuffer],
        sampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        guard !buffers.isEmpty else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No buffers to concatenate"]
            )
        }
        
        let totalSamples = buffers.reduce(0) {
            $0 + Int($1.frameLength)
        }
        
        guard let firstBuffer = buffers.first else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No buffers"]
            )
        }
        
        let format = firstBuffer.format
        
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(totalSamples)
        ) else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Concatenation allocation failed"]
            )
        }
        
        outBuffer.frameLength = AVAudioFrameCount(totalSamples)
        guard let dst = outBuffer.floatChannelData else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing channel data"]
            )
        }
        
        var writeIndex = 0
        for buffer in buffers {
            guard let src = buffer.floatChannelData else { continue }
            let length = Int(buffer.frameLength)
            guard length > 0 else { continue }
            
            for channel in 0..<Int(format.channelCount) {
                let srcChannel = src[channel]
                let dstChannel = dst[channel]
                memcpy(dstChannel.advanced(by: writeIndex), srcChannel, length * MemoryLayout<Float>.size)
            }
            writeIndex += length
        }
        
        return outBuffer
    }
    
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
