import SwiftUI

struct SessionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkSession

    @State private var tagInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Modifier la session")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.chross)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("PROJET / CLIENT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Nom du projet / client", text: $session.projectName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("TAGS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    ForEach(session.tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                    TextField("Ajouter un tag…", text: $tagInput)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .onSubmit(addTag)
                        .frame(minWidth: 100)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("NOTES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextEditor(text: $session.notes)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(height: 140)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Terminé")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.chross)
                .background(Theme.accent, in: Capsule())
            }
        }
        .padding(28)
        .frame(width: 440, height: 560)
        .background(Theme.page)
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag).font(.callout).foregroundStyle(Theme.textPrimary)
            Button {
                session.tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.chross)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceRaised, in: Capsule())
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !session.tags.contains(trimmed) else { return }
        session.tags.append(trimmed)
        tagInput = ""
    }
}

#Preview {
    let session = WorkSession(projectName: "Refonte site — Client A", startDate: Date(), declaredItems: [])
    session.tags = ["urgent", "client VIP"]
    session.notes = "Repasser sur la page contact avant livraison."
    return SessionEditView(session: session)
}
