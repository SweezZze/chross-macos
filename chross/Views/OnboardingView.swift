import SwiftUI

/// First-launch introduction: explains what chross does, asks for each permission at the
/// moment it's explained (never all at once), and sets the few preferences that matter.
/// Every step can be skipped — everything stays available later in Réglages.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    @State private var permissions = SystemPermissions()

    @AppStorage(AppPreferences.dailyGoalHoursKey) private var dailyGoalHours: Double = AppPreferences.defaultDailyGoalHours
    @AppStorage(AppPreferences.defaultIdleMinutesKey) private var defaultIdleMinutes: Double = AppPreferences.defaultIdleMinutes
    @AppStorage(WorkReminder.enabledKey) private var workReminderEnabled = true

    private let stepCount = 5

    var body: some View {
        ZStack {
            Theme.page.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: accessibility
                    case 2: notifications
                    case 3: preferences
                    default: ready
                    }
                }
                .frame(maxWidth: 520)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 24)

                footer
                    .frame(maxWidth: 520)
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 40)
        }
        .task { await permissions.poll() }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 24) {
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 40))
                .foregroundStyle(.black)
                .frame(width: 88, height: 88)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(spacing: 8) {
                Text("Bienvenue dans Chross")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Le chrono qui compte ton vrai temps de travail — et seulement celui-là.")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                feature("checklist", "Tu choisis les apps et les sites d'un projet", "Le reste est classé « hors sélection » et n'est pas compté.")
                feature("moon.zzz", "Pause automatique", "Le chrono s'arrête quand tu t'éloignes de l'ordinateur.")
                feature("eurosign.circle", "Facturation en un clic", "Taux horaire, arrondi, TVA et facture PDF à la fin de la session.")
            }
            .padding(20)
            .chrossCard(padding: 0)
        }
    }

    private var accessibility: some View {
        permissionStep(
            icon: "globe",
            title: "Détecter les sites web",
            text: "Pour savoir sur quel site tu travailles, Chross lit l'adresse de l'onglet actif de ton navigateur. macOS appelle ça l'autorisation « Accessibilité ».",
            details: [
                "Seule l'adresse de l'onglet affiché est lue — jamais le contenu des pages.",
                "Rien ne quitte ton Mac.",
            ],
            isGranted: permissions.accessibilityGranted,
            grantedText: "Accessibilité autorisée",
            buttonTitle: AccessibilityPermission.didPromptThisLaunch ? "Ouvrir les Réglages Système" : "Autoriser",
            action: { permissions.requestAccessibility() },
            footnote: "Dans Réglages Système → Confidentialité et sécurité → Accessibilité, active « chross ». Cette page se met à jour toute seule."
        )
    }

    private var notifications: some View {
        permissionStep(
            icon: "bell.badge",
            title: "Rappels et notifications",
            text: "Chross peut te prévenir quand tu travailles sur un de tes projets sans avoir lancé le chrono — la principale source de temps non facturé.",
            details: [
                "Un bouton « Démarrer » lance la session directement depuis la notification.",
                "Jamais plus d'un rappel toutes les 30 minutes.",
            ],
            isGranted: permissions.notifications == .granted,
            grantedText: "Notifications autorisées",
            buttonTitle: permissions.notifications == .denied ? "Ouvrir les Réglages Système" : "Autoriser les notifications",
            action: { Task { await permissions.requestNotifications() } },
            footnote: permissions.notifications == .denied
                ? "Les notifications ont été refusées : active-les pour « chross » dans Réglages Système → Notifications."
                : nil
        )
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(icon: "slider.horizontal.3", title: "Tes préférences", text: "Tu pourras tout changer plus tard dans Réglages.")

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Objectif quotidien").font(.callout.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        Text("Affiché dans la barre latérale").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Stepper(value: $dailyGoalHours, in: 1...16, step: 0.5) {
                        Text("\(dailyGoalHours.formatted()) h")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .fixedSize()
                }

                Divider().background(Theme.border)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Pause auto si inactif").font(.callout.weight(.medium)).foregroundStyle(Theme.textPrimary)
                    PillSegmentedControl(options: AppPreferences.idleOptions, label: AppPreferences.idleLabel, selection: $defaultIdleMinutes)
                }

                Divider().background(Theme.border)

                ThemedToggle("Rappel si je travaille sans chrono", isOn: $workReminderEnabled)

                ThemedToggle(
                    "Ouvrir Chross au démarrage du Mac",
                    isOn: Binding(
                        get: { permissions.launchAtLogin },
                        set: { permissions.setLaunchAtLogin($0) }
                    )
                )
            }
            .chrossCard()
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 80, height: 80)
                .background(Theme.accent, in: Circle())

            VStack(spacing: 8) {
                Text("Tout est prêt")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Lance ta première session depuis l'onglet Chrono.")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                statusRow("Détection des sites", isOn: permissions.accessibilityGranted)
                statusRow("Notifications", isOn: permissions.notifications == .granted)
                statusRow("Ouverture au démarrage", isOn: permissions.launchAtLogin)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .chrossCard(padding: 0)

            Text("Astuce : réorganise le menu de gauche en faisant glisser les onglets.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 0 && step < stepCount - 1 {
                Button("Retour") { go(to: step - 1) }
                    .buttonStyle(.chross)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Theme.accent : Color.white.opacity(0.18))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
            Spacer()
            Button {
                if step == stepCount - 1 {
                    onFinish()
                } else {
                    go(to: step + 1)
                }
            } label: {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.chross)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case 0: return "Commencer"
        case 1: return permissions.accessibilityGranted ? "Continuer" : "Plus tard"
        case 2: return permissions.notifications == .granted ? "Continuer" : "Plus tard"
        case stepCount - 1: return "Ouvrir Chross"
        default: return "Continuer"
        }
    }

    private func go(to newStep: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            step = min(max(newStep, 0), stepCount - 1)
        }
    }

    // MARK: - Pieces

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func stepHeader(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Theme.accent)
                .frame(width: 60, height: 60)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(text)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionStep(
        icon: String,
        title: String,
        text: String,
        details: [String],
        isGranted: Bool,
        grantedText: String,
        buttonTitle: String,
        action: @escaping () -> Void,
        footnote: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(icon: icon, title: title, text: text)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(details, id: \.self) { detail in
                    Label(detail, systemImage: "checkmark.shield")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if isGranted {
                Label(grantedText, systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.accentDim, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: action) {
                        Text(buttonTitle)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Theme.surfaceRaised, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1.5))
                    }
                    .buttonStyle(.chross)
                    if let footnote {
                        Text(footnote)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isGranted)
    }

    private func statusRow(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(Theme.textPrimary)
            Spacer()
            Label(isOn ? "Activé" : "Désactivé", systemImage: isOn ? "checkmark.circle.fill" : "minus.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(isOn ? Theme.accent : Theme.textTertiary)
        }
    }
}
