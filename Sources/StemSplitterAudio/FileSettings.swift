import AVFoundation

extension AVAudioFormat {
    /// Inställningar för att skriva formatet till en WAV-fil. Ljudfiler lagras alltid
    /// interfolierade, så flaggan för icke-interfolierat tas bort (annars loggar AVFoundation
    /// "Audio files cannot be non-interleaved" för varje fil). Bearbetningen i minnet påverkas inte.
    public var fileSettings: [String: Any] {
        var settings = self.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        return settings
    }
}
