import Foundation

/// Renders both test results as Markdown for the report.
nonisolated enum EvaluationReport {
    static func markdown(extraction: ExtractionSummary?, agent: [AgentQuestionResult], agentPassRate: Double) -> String {
        var out = "# Expenses evaluation\n\nGenerated \(Date().formatted(date: .long, time: .shortened)).\n\n"
        if let e = extraction {
            out += "## Extraction test\n\nFolder: `\(e.folder)` · model: `\(Config.extractionModel)` · files: \(e.files) · errors: \(e.errors)\n\n"
            out += String(format: "Overall field accuracy: **%.1f%%** · average %.1f s per file · %d tokens total\n\n",
                          e.overall * 100, e.averageSeconds, e.tokens)
            if !e.fields.isEmpty {
                out += "| Field | Correct | Of | Accuracy |\n|---|---|---|---|\n"
                for f in e.fields { out += String(format: "| %@ | %d | %d | %.1f%% |\n", f.field, f.passed, f.total, f.rate * 100) }
                out += "\n"
            }
            let mismatches = e.results.flatMap { r in r.mismatches.map { (r.fileName, $0) } }
            if !mismatches.isEmpty {
                out += "### Mismatches\n\n| File | Field | Expected | Actual |\n|---|---|---|---|\n"
                for (file, f) in mismatches { out += "| \(file) | \(f.field) | \(f.expected) | \(f.actual) |\n" }
                out += "\n"
            }
            let errors = e.results.compactMap { r in r.error.map { "- \(r.fileName): \($0)" } }
            if !errors.isEmpty { out += "### Errors\n\n" + errors.joined(separator: "\n") + "\n\n" }
        }
        if !agent.isEmpty {
            out += String(format: "## Agent test\n\nModel: `%@` · pass rate: **%.0f%%** (%d of %d)\n\n", Config.agentModel,
                          agentPassRate * 100, agent.filter(\.passed).count, agent.count)
            out += "| Question | Expected number | Tools used | Number found | Result |\n|---|---|---|---|---|\n"
            for q in agent {
                out += String(format: "| %@ | %.2f | %@ | %@ | %@ |\n", q.question, q.expectedNumber,
                              q.toolsUsed.joined(separator: ", "), q.numberPassed ? "yes" : "no", q.passed ? "pass" : "fail")
            }
            out += "\n### Answers\n\n"
            for q in agent { out += "**Q:** \(q.question)\n\n**A:** \(q.answer)\n\n" }
        }
        return out
    }
}

nonisolated struct ExtractionSummary {
    var folder: String
    var files: Int
    var errors: Int
    var overall: Double
    var averageSeconds: Double
    var tokens: Int
    var fields: [FieldAccuracy]
    var results: [ExtractionFileResult]
}
