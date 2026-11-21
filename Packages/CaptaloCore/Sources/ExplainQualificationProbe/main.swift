// Offline serializer for synthetic qualification fixtures. No transport or credentials.
import CaptaloCore
import Foundation

struct Fixture: Decodable {
    let id, source, profile: String
    let depth: ExplainDepth
    let style: ExplainStyle
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard (2...3).contains(args.count),
          let variant = ExplainInstructionVariant(rawValue: args.count == 3 ? args[2] : "control"),
          let candidate = ExplainCandidate(rawValue: args[0]) else {
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    let output: Data
    switch args[1] {
    case "config":
        output = try candidate.configuration(variant: variant)
    case "requests":
        let fixtures = try JSONDecoder().decode([Fixture].self, from: FileHandle.standardInput.readDataToEndOfFile())
        let bodies = try fixtures.map { fixture in
            let input = try ExplainInput(source: fixture.source, depth: fixture.depth, style: fixture.style, profile: fixture.profile)
            do {
                return ["id": fixture.id, "body": String(decoding: try candidate.requestBody(input, variant: variant), as: UTF8.self)]
            } catch ExplainInputError.oneWordMiddle {
                FileHandle.standardError.write(Data("\(fixture.id): Select a longer passage or choose another depth.\n".utf8))
                throw ExplainInputError.oneWordMiddle
            }
        }
        output = try JSONEncoder().encode(bodies)
    default:
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    FileHandle.standardOutput.write(output)
} catch {
    FileHandle.standardError.write(Data("Cannot serialize qualification input.\n".utf8))
    exit(1)
}
