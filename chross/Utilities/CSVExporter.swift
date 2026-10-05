import Foundation

enum CSVExporter {
    static func export(_ sessions: [WorkSession]) -> String {
        let header = [
            "Date", "Début", "Fin", "Projet", "Temps actif (s)", "Temps actif",
            "Hors sélection", "Inactif", "Taux horaire", "Devise", "Total facturé", "Tags", "Notes",
        ]
        var rows = [header.map(escape).joined(separator: ",")]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for session in sessions.sorted(by: { $0.startDate < $1.startDate }) {
            let endTime: String = session.endDate.map { timeFormatter.string(from: $0) } ?? ""
            let hourlyRate: String = session.billing.map { "\($0.hourlyRate)" } ?? ""
            let currencyCode: String = session.billing?.currencyCode ?? ""
            let billedTotal: String = session.billedTotal.map { "\($0)" } ?? ""

            var fields: [String] = []
            fields.append(dateFormatter.string(from: session.startDate))
            fields.append(timeFormatter.string(from: session.startDate))
            fields.append(endTime)
            fields.append(session.projectName)
            fields.append(String(Int(session.activeSeconds)))
            fields.append(DurationFormatter.format(session.activeSeconds))
            fields.append(DurationFormatter.format(session.outOfScopeSeconds))
            fields.append(DurationFormatter.format(session.idleSeconds))
            fields.append(hourlyRate)
            fields.append(currencyCode)
            fields.append(billedTotal)
            fields.append(session.tags.joined(separator: "; "))
            fields.append(session.notes)

            rows.append(fields.map(escape).joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
