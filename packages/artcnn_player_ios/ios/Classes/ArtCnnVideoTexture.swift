import CoreVideo
import Flutter
import Foundation

final class ArtCnnVideoTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var latestPixelBuffer: CVPixelBuffer?

  func update(pixelBuffer: CVPixelBuffer) {
    lock.lock()
    latestPixelBuffer = pixelBuffer
    lock.unlock()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    guard let pixelBuffer = latestPixelBuffer else {
      lock.unlock()
      return nil
    }
    CVPixelBufferRetain(pixelBuffer)
    lock.unlock()
    return Unmanaged.passRetained(pixelBuffer)
  }
}
