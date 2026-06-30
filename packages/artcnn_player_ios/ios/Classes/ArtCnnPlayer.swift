import AVFoundation
import CoreImage
import CoreML
import CoreVideo
import Flutter
import QuartzCore

final class ArtCnnPlayer {
  let textureId: Int64

  private let texture: ArtCnnVideoTexture
  private let textureRegistry: FlutterTextureRegistry
  private let ciContext = CIContext()
  private let processingQueue = DispatchQueue(label: "irisesce.artcnn.processing", qos: .userInitiated)
  private let modelInputWidth = 640
  private let modelInputHeight = 360
  private let modelOutputWidth = 1280
  private let modelOutputHeight = 720
  private let artCnnLumaBlend: Float = 0.65
  private let pixelBufferAttributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferMetalCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
  ]

  private var player = AVPlayer()
  private var videoOutput: AVPlayerItemVideoOutput?
  private var displayLink: CADisplayLink?
  private var artCnnModel: MLModel?
  private var artCnnEnabled = false
  private var isInferencing = false
  private var processedFrames: Int64 = 0
  private var skippedFrames: Int64 = 0
  private var width: Int64?
  private var height: Int64?
  private var frameRate: Double?
  private var lastInferenceMs: Double?
  private var lastError: String?
  private var sourcePath: String?
  private var diagnostics = "idle"
  private var lastLoggedProcessedFrame: Int64 = 0

  init(
    textureId: Int64,
    texture: ArtCnnVideoTexture,
    textureRegistry: FlutterTextureRegistry
  ) {
    self.textureId = textureId
    self.texture = texture
    self.textureRegistry = textureRegistry
    startDisplayLink()
  }

  func load(uri: String) throws {
    let url: URL
    if uri.hasPrefix("http://") || uri.hasPrefix("https://") || uri.hasPrefix("file://") {
      guard let parsedUrl = URL(string: uri) else {
        throw playerError("invalid_uri", "Invalid media URI: \(uri)")
      }
      url = parsedUrl
    } else {
      url = URL(fileURLWithPath: uri)
    }

    let item = AVPlayerItem(url: url)
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
    item.add(output)
    videoOutput = output
    player.replaceCurrentItem(with: item)
    sourcePath = url.path
    processedFrames = 0
    skippedFrames = 0
    lastInferenceMs = nil
    diagnostics = "loaded \(url.lastPathComponent)"
    log("load source=\(url.path)")
    collectDiagnostics(from: item.asset)
    lastError = nil
  }

  func loadFirstDocumentVideo() throws -> String {
    guard let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw playerError("documents_unavailable", "Documents directory is unavailable")
    }

    let supportedExtensions: Set<String> = ["mp4", "mov", "m4v", "hevc"]
    let knownUnsupportedExtensions: Set<String> = ["mkv", "avi"]
    let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
    guard let enumerator = FileManager.default.enumerator(
      at: documentsUrl,
      includingPropertiesForKeys: Array(resourceKeys),
      options: [.skipsPackageDescendants]
    ) else {
      throw playerError("documents_unavailable", "Cannot read Documents directory at \(documentsUrl.path)")
    }

    let videoFiles = enumerator
      .compactMap { $0 as? URL }
      .filter { url in
        let values = try? url.resourceValues(forKeys: resourceKeys)
        guard values?.isRegularFile == true && values?.isHidden != true else {
          return false
        }
        let fileExtension = url.pathExtension.lowercased()
        return supportedExtensions.contains(fileExtension) || knownUnsupportedExtensions.contains(fileExtension)
      }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

    if let playableUrl = videoFiles.first(where: { supportedExtensions.contains($0.pathExtension.lowercased()) }) {
      try load(uri: playableUrl.path)
      return playableUrl.lastPathComponent
    }

    if let unsupportedUrl = videoFiles.first(where: { knownUnsupportedExtensions.contains($0.pathExtension.lowercased()) }) {
      let message = "Found \(unsupportedUrl.lastPathComponent), but \(unsupportedUrl.pathExtension.uppercased()) is not supported by AVPlayer in phase 1. Remux it to MP4 or MOV without re-encoding for this test build."
      lastError = message
      throw playerError("document_video_unsupported", message)
    }

    do {
      let allFiles = try FileManager.default.contentsOfDirectory(atPath: documentsUrl.path).joined(separator: ", ")
      let suffix = allFiles.isEmpty ? "" : " Current files: \(allFiles)"
      let message = "No test video found in Documents. Put one .mp4, .mov, .m4v, or .hevc file in \(documentsUrl.path).\(suffix)"
      lastError = message
      throw playerError("document_video_not_found", message)
    } catch let error as PigeonError {
      throw error
    } catch {
      let message = "No test video found in Documents. Put one .mp4, .mov, .m4v, or .hevc file in \(documentsUrl.path)."
      lastError = message
      throw playerError("document_video_not_found", message)
    }
  }

  func play() {
    player.play()
  }

  func pause() {
    player.pause()
  }

  func seek(positionMs: Int64) {
    let time = CMTime(value: positionMs, timescale: 1000)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  func setArtCNNEnabled(_ enabled: Bool) {
    artCnnEnabled = enabled
    diagnostics = enabled ? "ArtCNN enabled" : "ArtCNN disabled"
    log(diagnostics)
    if enabled && artCnnModel == nil {
      processingQueue.async { [weak self] in
        self?.loadArtCnnModelIfNeeded()
      }
    }
  }

  func state() -> PlayerState {
    let durationMs = player.currentItem?.duration.toMilliseconds() ?? 0
    let positionMs = player.currentTime().toMilliseconds()
    return PlayerState(
      isPlaying: player.rate != 0,
      isBuffering: player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
      positionMs: positionMs,
      durationMs: durationMs,
      artCnnEnabled: artCnnEnabled,
      processedFrames: processedFrames,
      skippedFrames: skippedFrames,
      width: width,
      height: height,
      frameRate: frameRate,
      lastInferenceMs: lastInferenceMs,
      sourcePath: sourcePath,
      diagnostics: diagnostics,
      error: lastError
    )
  }

  func dispose() {
    displayLink?.invalidate()
    displayLink = nil
    player.pause()
    player.replaceCurrentItem(with: nil)
  }

  private func startDisplayLink() {
    displayLink = CADisplayLink(target: self, selector: #selector(onDisplayLink(_:)))
    displayLink?.add(to: .main, forMode: .common)
  }

  @objc private func onDisplayLink(_ link: CADisplayLink) {
    guard let output = videoOutput else {
      return
    }
    let hostTime = CACurrentMediaTime()
    let itemTime = output.itemTime(forHostTime: hostTime)
    guard output.hasNewPixelBuffer(forItemTime: itemTime),
          let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
      return
    }

    if !artCnnEnabled {
      publish(pixelBuffer)
      return
    }

    guard !isInferencing else {
      skippedFrames += 1
      return
    }
    isInferencing = true
    processingQueue.async { [weak self] in
      guard let self else {
        return
      }
      let started = CACurrentMediaTime()
      let outputBuffer = self.runArtCnn(input: pixelBuffer) ?? pixelBuffer
      self.lastInferenceMs = (CACurrentMediaTime() - started) * 1000
      self.processedFrames += 1
      if self.processedFrames - self.lastLoggedProcessedFrame >= 30 {
        self.lastLoggedProcessedFrame = self.processedFrames
        self.log("processed=\(self.processedFrames) skipped=\(self.skippedFrames) inferenceMs=\(String(format: "%.2f", self.lastInferenceMs ?? 0)) \(self.diagnostics)")
      }
      self.publish(outputBuffer)
      self.isInferencing = false
    }
  }

  private func publish(_ pixelBuffer: CVPixelBuffer) {
    texture.update(pixelBuffer: pixelBuffer)
    DispatchQueue.main.async { [textureRegistry, textureId] in
      textureRegistry.textureFrameAvailable(textureId)
    }
  }

  private func loadArtCnnModelIfNeeded() {
    guard artCnnModel == nil else {
      return
    }
    do {
      guard let url = artCnnModelUrl() else {
        lastError = "ArtCNN_C4F16.mlmodelc was not found in the app bundle"
        log(lastError ?? "missing ArtCNN model")
        return
      }
      artCnnModel = try MLModel(contentsOf: url)
      diagnostics = describe(model: artCnnModel)
      log("model loaded url=\(url.path) \(diagnostics)")
    } catch {
      lastError = "Failed to load ArtCNN model: \(error.localizedDescription)"
      log(lastError ?? "model load failed")
    }
  }

  private func artCnnModelUrl() -> URL? {
    let bundles = [
      Bundle.main,
      Bundle(for: ArtCnnPlayerPlugin.self),
      Bundle(for: ArtCnnPlayerPlugin.self).url(forResource: "artcnn_player_ios", withExtension: "bundle").flatMap(Bundle.init(url:)),
    ].compactMap { $0 }

    for bundle in bundles {
      if let url = bundle.url(forResource: "ArtCNN_C4F16", withExtension: "mlmodelc") {
        return url
      }
    }
    return nil
  }

  private func runArtCnn(input pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    loadArtCnnModelIfNeeded()
    guard let model = artCnnModel else {
      skippedFrames += 1
      return nil
    }
    do {
      guard let inputName = model.modelDescription.inputDescriptionsByName.first?.key else {
        lastError = "ArtCNN model has no input feature"
        return nil
      }
      let provider = try makeFeatureProvider(inputName: inputName, pixelBuffer: pixelBuffer)
      let prediction = try model.prediction(from: provider)
      for outputName in model.modelDescription.outputDescriptionsByName.keys {
        let outputValue = prediction.featureValue(for: outputName)
        if let outputBuffer = outputValue?.imageBufferValue {
          lastError = nil
          return outputBuffer
        }
        if let outputArray = outputValue?.multiArrayValue,
           let outputBuffer = makePixelBuffer(from: outputArray, source: pixelBuffer) {
          lastError = nil
          return outputBuffer
        }
      }
      lastError = "ArtCNN model did not return a pixel buffer"
      log(lastError ?? "missing output")
    } catch {
      lastError = "ArtCNN inference failed: \(error.localizedDescription)"
      log(lastError ?? "inference failed")
    }
    return nil
  }

  private func makeFeatureProvider(inputName: String, pixelBuffer: CVPixelBuffer) throws -> MLFeatureProvider {
    guard let inputDescription = artCnnModel?.modelDescription.inputDescriptionsByName[inputName],
          inputDescription.type == .multiArray else {
      return try MLDictionaryFeatureProvider(dictionary: [
        inputName: MLFeatureValue(pixelBuffer: pixelBuffer),
      ])
    }

    let inputArray = try makeInputArray(from: pixelBuffer)
    return try MLDictionaryFeatureProvider(dictionary: [
      inputName: MLFeatureValue(multiArray: inputArray),
    ])
  }

  private func makeInputArray(from source: CVPixelBuffer) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [1, 1, NSNumber(value: modelInputHeight), NSNumber(value: modelInputWidth)], dataType: .float32)
    guard let scaledBuffer = makeScaledBgraBuffer(from: source, width: modelInputWidth, height: modelInputHeight) else {
      throw playerError("preprocess_failed", "Failed to scale video frame for ArtCNN")
    }

    CVPixelBufferLockBaseAddress(scaledBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(scaledBuffer, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(scaledBuffer) else {
      throw playerError("preprocess_failed", "Scaled video frame has no base address")
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(scaledBuffer)
    let output = array.dataPointer.bindMemory(to: Float32.self, capacity: modelInputWidth * modelInputHeight)
    let strides = array.strides.map(\.intValue)
    let nStride = strides.count > 0 ? strides[0] : modelInputWidth * modelInputHeight
    let cStride = strides.count > 1 ? strides[1] : modelInputWidth * modelInputHeight
    let yStride = strides.count > 2 ? strides[2] : modelInputWidth
    let xStride = strides.count > 3 ? strides[3] : 1
    for y in 0..<modelInputHeight {
      let row = baseAddress.advanced(by: y * bytesPerRow).bindMemory(to: UInt8.self, capacity: modelInputWidth * 4)
      for x in 0..<modelInputWidth {
        let offset = x * 4
        let blue = Float32(row[offset])
        let green = Float32(row[offset + 1])
        let red = Float32(row[offset + 2])
        output[nStride * 0 + cStride * 0 + yStride * y + xStride * x] = (0.114 * blue + 0.587 * green + 0.299 * red) / 255.0
      }
    }
    return array
  }

  private func makeScaledBgraBuffer(from source: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
    var output: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      pixelBufferAttributes as CFDictionary,
      &output
    )
    guard status == kCVReturnSuccess, let output else {
      return nil
    }

    let image = CIImage(cvPixelBuffer: source)
    let scaleX = CGFloat(width) / image.extent.width
    let scaleY = CGFloat(height) / image.extent.height
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    ciContext.render(scaled, to: output)
    return output
  }

  private func makePixelBuffer(from array: MLMultiArray, source: CVPixelBuffer) -> CVPixelBuffer? {
    guard let colorBuffer = makeScaledBgraBuffer(from: source, width: modelOutputWidth, height: modelOutputHeight) else {
      diagnostics = "failed to scale source color for ArtCNN output"
      return nil
    }

    var output: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      modelOutputWidth,
      modelOutputHeight,
      kCVPixelFormatType_32BGRA,
      pixelBufferAttributes as CFDictionary,
      &output
    )
    guard status == kCVReturnSuccess, let output else {
      return nil
    }

    CVPixelBufferLockBaseAddress(output, [])
    CVPixelBufferLockBaseAddress(colorBuffer, .readOnly)
    defer {
      CVPixelBufferUnlockBaseAddress(colorBuffer, .readOnly)
      CVPixelBufferUnlockBaseAddress(output, [])
    }
    guard let baseAddress = CVPixelBufferGetBaseAddress(output),
          let colorBaseAddress = CVPixelBufferGetBaseAddress(colorBuffer) else {
      return nil
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
    let colorBytesPerRow = CVPixelBufferGetBytesPerRow(colorBuffer)
    let values = array.dataPointer.bindMemory(to: Float32.self, capacity: modelOutputWidth * modelOutputHeight)
    let shape = array.shape.map(\.intValue)
    let strides = array.strides.map(\.intValue)
    let yDimension = max(0, shape.count - 2)
    let xDimension = max(0, shape.count - 1)
    let outputHeight = min(modelOutputHeight, shape[safe: yDimension] ?? modelOutputHeight)
    let outputWidth = min(modelOutputWidth, shape[safe: xDimension] ?? modelOutputWidth)
    let nStride = strides.count > 0 ? strides[0] : modelOutputWidth * modelOutputHeight
    let cStride = strides.count > 1 ? strides[1] : modelOutputWidth * modelOutputHeight
    let yStride = strides.count > yDimension ? strides[yDimension] : modelOutputWidth
    let xStride = strides.count > xDimension ? strides[xDimension] : 1

    for y in 0..<modelOutputHeight {
      let row = baseAddress.advanced(by: y * bytesPerRow).bindMemory(to: UInt8.self, capacity: modelOutputWidth * 4)
      let colorRow = colorBaseAddress.advanced(by: y * colorBytesPerRow).bindMemory(to: UInt8.self, capacity: modelOutputWidth * 4)
      for x in 0..<modelOutputWidth {
        let offset = x * 4
        let blue = Float(colorRow[offset]) / 255.0
        let green = Float(colorRow[offset + 1]) / 255.0
        let red = Float(colorRow[offset + 2]) / 255.0
        let sourceY = max(0.001, 0.114 * blue + 0.587 * green + 0.299 * red)
        let modelY: Float
        if y < outputHeight && x < outputWidth {
          modelY = clamp(values[nStride * 0 + cStride * 0 + yStride * y + xStride * x], min: 0, max: 1)
        } else {
          modelY = sourceY
        }

        let blendedY = clamp(sourceY * (1.0 - artCnnLumaBlend) + modelY * artCnnLumaBlend, min: 0, max: 1)
        let cb = (blue - sourceY) * 0.565
        let cr = (red - sourceY) * 0.713
        let outRed = clamp(blendedY + 1.403 * cr, min: 0, max: 1)
        let outBlue = clamp(blendedY + 1.773 * cb, min: 0, max: 1)
        let outGreen = clamp((blendedY - 0.299 * outRed - 0.114 * outBlue) / 0.587, min: 0, max: 1)

        row[offset] = UInt8((outBlue * 255.0).rounded())
        row[offset + 1] = UInt8((outGreen * 255.0).rounded())
        row[offset + 2] = UInt8((outRed * 255.0).rounded())
        row[offset + 3] = 255
      }
    }
    diagnostics = "ArtCNN output shape=\(shape) strides=\(strides) color=preserved-y blend=\(artCnnLumaBlend)"
    return output
  }

  private func collectDiagnostics(from asset: AVAsset) {
    Task {
      do {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
          return
        }
        let size = try await track.load(.naturalSize)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        await MainActor.run {
          width = Int64(abs(size.width))
          height = Int64(abs(size.height))
          frameRate = Double(nominalFrameRate)
          diagnostics = "video \(Int(abs(size.width)))x\(Int(abs(size.height))) fps=\(String(format: "%.2f", Double(nominalFrameRate)))"
          log(diagnostics)
        }
      } catch {
        await MainActor.run {
          lastError = "Failed to read video diagnostics: \(error.localizedDescription)"
          log(lastError ?? "diagnostics failed")
        }
      }
    }
  }

  private func describe(model: MLModel?) -> String {
    guard let model else {
      return "model=nil"
    }
    let inputs = model.modelDescription.inputDescriptionsByName.map { name, description in
      "\(name):\(description.type)"
    }.sorted().joined(separator: ",")
    let outputs = model.modelDescription.outputDescriptionsByName.map { name, description in
      "\(name):\(description.type)"
    }.sorted().joined(separator: ",")
    return "model input=[\(inputs)] output=[\(outputs)] expected=\(modelInputWidth)x\(modelInputHeight)->\(modelOutputWidth)x\(modelOutputHeight) blend=\(artCnnLumaBlend)"
  }

  private func log(_ message: String) {
    print("[Irisesce.ArtCNN] \(message)")
  }

  private func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.max(minValue, Swift.min(maxValue, value))
  }

  private func playerError(_ code: String, _ message: String) -> PigeonError {
    PigeonError(code: code, message: message, details: nil)
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else {
      return nil
    }
    return self[index]
  }
}

private extension CMTime {
  func toMilliseconds() -> Int64 {
    guard isNumeric && !seconds.isNaN && !seconds.isInfinite else {
      return 0
    }
    return Int64((seconds * 1000).rounded())
  }
}
