import CaptaloCore
import CaptaloSpeech
import Foundation

/// captalo-speech-probe: the Release-built probe on the production speech code
/// (plan phase 3, unit 3D). It starts no child processes.
///
///   fetch     --models DIR --voices a,b          development download (HOME redirected by the caller)
///   manifest  --models DIR --voices a,b --out F  reviewed manifest update (make update-model-manifest)
///   verify    --models DIR --manifest F          size + sha256 per file
///   synthesize --bundle DIR --store DIR --manifest F --fixture F [--voices a,b] [--registry URL] [--speed S] --out F
///   control-request --url URL                    one GET (positive controls for the offline test)

struct Arguments {
    let command: String
    let values: [String: String]

    init(_ raw: [String]) {
        command = raw.first ?? ""
        var values: [String: String] = [:]
        var index = 1
        while index < raw.count {
            let key = raw[index]
            if key.hasPrefix("--"), index + 1 < raw.count {
                values[String(key.dropFirst(2))] = raw[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
        self.values = values
    }

    func url(_ key: String) throws -> URL {
        guard let value = values[key] else { throw ProbeError.missing(key) }
        return URL(fileURLWithPath: value)
    }

    func list(_ key: String) -> [String]? {
        values[key].map { $0.split(separator: ",").map(String.init) }
    }
}

enum ProbeError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case let .missing(key): "missing --\(key)"
        }
    }
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("captalo-speech-probe: \(message)\n".utf8))
    exit(code)
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    switch arguments.command {
    case "fetch":
        let models = try arguments.url("models")
        guard let voices = arguments.list("voices"), !voices.isEmpty else { throw ProbeError.missing("voices") }
        try await KokoroSynthesizer.fetchModels(into: models, voices: voices)
        print("fetched into \(models.path)")
    case "manifest":
        let models = try arguments.url("models")
        guard let voices = arguments.list("voices"), !voices.isEmpty else { throw ProbeError.missing("voices") }
        let manifest = try ModelManifest.scan(models, voices: voices, generated: arguments.list("generated") ?? [])
        try manifest.encoded().write(to: try arguments.url("out"))
        print("\(manifest.files.count) files, \(manifest.totalBytes) bytes, version \(manifest.contentHash)")
    case "verify":
        let manifest = try ModelManifest.load(from: try arguments.url("manifest"))
        if let failure = ManifestValidator.validate(try arguments.url("models"), against: manifest) {
            fail("verification failed: \(failure)", code: 2)
        }
        print("verified \(manifest.files.count) files, version \(manifest.contentHash)")
    case "synthesize":
        try await SynthesisProbe.run(arguments)
    case "control-request":
        guard let raw = arguments.values["url"], let url = URL(string: raw) else { throw ProbeError.missing("url") }
        let (_, response) = try await URLSession.shared.data(from: url)
        print("control response \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    default:
        fail("unknown command \(arguments.command.isEmpty ? "(none)" : arguments.command)", code: 64)
    }
} catch {
    fail("\(error)")
}
