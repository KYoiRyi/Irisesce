import AVFoundation
import Flutter
import Foundation

public final class ArtCnnPlayerPlugin: NSObject, FlutterPlugin, PlayerHostApi {
  private let textureRegistry: FlutterTextureRegistry
  private var nextPlayerId: Int64 = 1
  private var players: [Int64: ArtCnnPlayer] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = ArtCnnPlayerPlugin(textureRegistry: registrar.textures())
    PlayerHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: plugin)
  }

  init(textureRegistry: FlutterTextureRegistry) {
    self.textureRegistry = textureRegistry
  }

  func createPlayer() throws -> CreatedPlayer {
    let playerId = nextPlayerId
    nextPlayerId += 1

    let texture = ArtCnnVideoTexture()
    let textureId = textureRegistry.register(texture)
    let player = ArtCnnPlayer(
      textureId: textureId,
      texture: texture,
      textureRegistry: textureRegistry
    )
    players[playerId] = player
    return CreatedPlayer(playerId: playerId, textureId: textureId)
  }

  func load(playerId: Int64, uri: String) throws {
    try requirePlayer(playerId).load(uri: uri)
  }

  func play(playerId: Int64) throws {
    try requirePlayer(playerId).play()
  }

  func pause(playerId: Int64) throws {
    try requirePlayer(playerId).pause()
  }

  func seek(playerId: Int64, positionMs: Int64) throws {
    try requirePlayer(playerId).seek(positionMs: positionMs)
  }

  func setArtCNNEnabled(playerId: Int64, enabled: Bool) throws {
    try requirePlayer(playerId).setArtCNNEnabled(enabled)
  }

  func getState(playerId: Int64) throws -> PlayerState {
    try requirePlayer(playerId).state()
  }

  func dispose(playerId: Int64) throws {
    guard let player = players.removeValue(forKey: playerId) else {
      return
    }
    player.dispose()
    textureRegistry.unregisterTexture(player.textureId)
  }

  private func requirePlayer(_ playerId: Int64) throws -> ArtCnnPlayer {
    guard let player = players[playerId] else {
      throw PigeonError(
        code: "player_not_found",
        message: "Player \(playerId) does not exist",
        details: nil
      )
    }
    return player
  }
}
